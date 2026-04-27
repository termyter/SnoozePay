import UIKit

/// Sticky header for the alarms list — composes a balance card and an
/// optional low-balance warning banner. Lives at the top of the screen
/// above the scrolling table view; pinned to the safe-area so it never
/// scrolls away.
///
/// Visual recipe:
/// - **Balance card**: same SPBalanceCard chrome (`bg2` raised surface,
///   28pt vertical / 24pt horizontal padding, 28pt corner radius). Caps
///   header "БАЛАНС", `moneyLg` value, a centered "Хватит на ~N
///   откладываний" hint **below** the value, and a trailing
///   `SPButton(.money, .sm)` "Пополнить" placed to the right of the
///   value row. The centered hint placement is a direct fix for PM
///   feedback (chat1.md line 971) — the previous layout put the hint
///   inline with the value and PM called it out as misaligned.
/// - **Warning banner**: `SPCard(.warn)` shown when balance ≤ 100. Caps
///   "БАЛАНС ПОЧТИ ПУСТ", current balance meta, and a small
///   `SPButton(.warn, .sm)` "Пополнить". Slot collapses (`isHidden`)
///   when balance > 100; the surrounding stack absorbs the gap.
///
/// The view exposes two callbacks (`onBalanceTopUpTap` and
/// `onWarnTopUpTap`) so the controller can wire whichever destination
/// it wants — callers don't need to know about the internal SPButton
/// instances.
final class SPAlarmsListHeader: UIView {

    // MARK: - Public API

    /// Triggered when the user taps the "Пополнить" pill on the balance
    /// card.
    var onBalanceTopUpTap: (() -> Void)?

    /// Triggered when the user taps the "Пополнить" pill on the
    /// low-balance warning banner.
    var onWarnTopUpTap: (() -> Void)?

    /// Update the balance card. `hint` is rendered as a centered line
    /// below the balance number — pass `nil` to hide.
    func setBalance(_ balance: Decimal, hint: String?) {
        balanceValueLabel.text = balance.formattedRubles()
        if let hint = hint, !hint.isEmpty {
            balanceHintLabel.text = hint
            balanceHintLabel.isHidden = false
        } else {
            balanceHintLabel.isHidden = true
        }
        // Remask the gradient on the value once layout reflows so the
        // mask tracks the new digit width (#137 SPBalanceCard pattern).
        setNeedsLayout()
    }

    /// Toggle the low-balance warning banner. When `visible == true`
    /// the banner shows the supplied `balance` in its meta line.
    func setWarning(visible: Bool, balance: Decimal) {
        warningBanner.isHidden = !visible
        warningMetaLabel.text = "Сейчас: \(balance.formattedRubles())"
    }

    // MARK: - Subviews

    private let stack = UIStackView()

    // Balance card
    private let balanceCard = SPCard(tone: .raised, padding: 24, cornerRadius: AppRadius.xl)
    private let balanceCapsLabel = UILabel()
    private let balanceValueLabel = UILabel()
    private let balanceValueGradient = CAGradientLayer()
    private let balanceHintLabel = UILabel()
    private let balanceTopUpButton = SPButton(
        title: "Пополнить",
        variant: .money,
        size: .sm,
        icon: UIImage(systemName: "plus.circle.fill")
    )
    private let radialOverlay = AlarmsHeaderRadialOverlayView()

    // Warning banner
    private let warningBanner = SPCard(tone: .warn, padding: AppSpacing.sp4, cornerRadius: AppRadius.lg)
    private let warningCapsLabel = UILabel()
    private let warningMetaLabel = UILabel()
    private let warningTopUpButton = SPButton(
        title: "Пополнить",
        variant: .warn,
        size: .sm
    )

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        radialOverlay.frame = balanceCard.bounds
        applyValueGradient()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        radialOverlay.setNeedsDisplay()
    }

    // MARK: - Configuration

    private func configure() {
        // Outer stack — vertical, 12pt gap between balance card and the
        // optional warning banner. Pinned to the view's layoutMargins so
        // the screen edges resolve to AppSpacing.screenInset (16pt) by
        // default — the controller assigns directionalLayoutMargins to
        // override.
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        stack.alignment = .fill
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])

        configureBalanceCard()
        configureWarningBanner()

        stack.addArrangedSubview(balanceCard)
        stack.addArrangedSubview(warningBanner)
        // Hidden by default — controller flips on view appear.
        warningBanner.isHidden = true
    }

    // swiftlint:disable:next function_body_length
    private func configureBalanceCard() {
        // Internal layout:
        //   ┌─────────────────────────────────┐
        //   │ БАЛАНС                          │
        //   │ 1 234 ₽           [+ Пополнить] │
        //   │       ~5 откладываний (centered)│
        //   └─────────────────────────────────┘
        balanceCard.translatesAutoresizingMaskIntoConstraints = false

        // Radial overlay sits behind content so subviews stack above it.
        radialOverlay.translatesAutoresizingMaskIntoConstraints = false
        radialOverlay.isUserInteractionEnabled = false
        balanceCard.insertSubview(radialOverlay, at: 0)

        balanceCapsLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceCapsLabel.attributedText = NSAttributedString(
            string: "БАЛАНС",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )

        balanceValueLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceValueLabel.font = AppTypography.moneyLg
        balanceValueLabel.textColor = AppColors.fg1
        balanceValueLabel.adjustsFontForContentSizeCategory = false
        balanceValueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        balanceTopUpButton.translatesAutoresizingMaskIntoConstraints = false
        balanceTopUpButton.addTarget(
            self,
            action: #selector(balanceTopUpTapped),
            for: .touchUpInside
        )

        // Value row — value pinned leading, top-up button trailing.
        let valueRow = UIView()
        valueRow.translatesAutoresizingMaskIntoConstraints = false
        valueRow.addSubview(balanceValueLabel)
        valueRow.addSubview(balanceTopUpButton)

        balanceHintLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceHintLabel.font = AppTypography.meta
        balanceHintLabel.textColor = AppColors.fg3
        balanceHintLabel.textAlignment = .center
        balanceHintLabel.numberOfLines = 1
        balanceHintLabel.isHidden = true

        // Caps + value row + centered hint — vertical stack inside the
        // card. Custom spacing keeps the hint visually separate from the
        // value (matches the JSX `gap-y-2` after value).
        let innerStack = UIStackView(arrangedSubviews: [
            balanceCapsLabel, valueRow, balanceHintLabel
        ])
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.axis = .vertical
        innerStack.alignment = .fill
        innerStack.spacing = 8
        innerStack.setCustomSpacing(8, after: balanceCapsLabel)
        innerStack.setCustomSpacing(10, after: valueRow)
        balanceCard.addSubview(innerStack)

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: balanceCard.layoutMarginsGuide.topAnchor),
            innerStack.bottomAnchor.constraint(equalTo: balanceCard.layoutMarginsGuide.bottomAnchor),
            innerStack.leadingAnchor.constraint(equalTo: balanceCard.layoutMarginsGuide.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: balanceCard.layoutMarginsGuide.trailingAnchor),

            balanceValueLabel.leadingAnchor.constraint(equalTo: valueRow.leadingAnchor),
            balanceValueLabel.topAnchor.constraint(equalTo: valueRow.topAnchor),
            balanceValueLabel.bottomAnchor.constraint(equalTo: valueRow.bottomAnchor),

            balanceTopUpButton.trailingAnchor.constraint(equalTo: valueRow.trailingAnchor),
            balanceTopUpButton.centerYAnchor.constraint(equalTo: balanceValueLabel.centerYAnchor),
            balanceTopUpButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: balanceValueLabel.trailingAnchor,
                constant: AppSpacing.sp3
            )
        ])

        // Wire the gradient layer to the value label — masked to glyph
        // outlines on every layout pass.
        balanceValueGradient.colors = SPSupport.moneyGradientColors
        balanceValueGradient.locations = SPSupport.moneyGradientLocations
        balanceValueGradient.startPoint = SPSupport.gradientStart
        balanceValueGradient.endPoint = SPSupport.gradientEnd
    }

    private func configureWarningBanner() {
        warningBanner.translatesAutoresizingMaskIntoConstraints = false

        warningCapsLabel.translatesAutoresizingMaskIntoConstraints = false
        warningCapsLabel.attributedText = NSAttributedString(
            string: "БАЛАНС ПОЧТИ ПУСТ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fgOnWarn
            ]
        )

        warningMetaLabel.translatesAutoresizingMaskIntoConstraints = false
        warningMetaLabel.font = AppTypography.meta
        warningMetaLabel.textColor = AppColors.fgOnWarn.withAlphaComponent(0.85)
        warningMetaLabel.numberOfLines = 1

        warningTopUpButton.translatesAutoresizingMaskIntoConstraints = false
        warningTopUpButton.addTarget(
            self,
            action: #selector(warnTopUpTapped),
            for: .touchUpInside
        )

        let textStack = UIStackView(arrangedSubviews: [warningCapsLabel, warningMetaLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [textStack, warningTopUpButton])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AppSpacing.sp3
        row.distribution = .fill

        warningBanner.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: warningBanner.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: warningBanner.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: warningBanner.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: warningBanner.layoutMarginsGuide.trailingAnchor)
        ])

        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        warningTopUpButton.setContentHuggingPriority(.required, for: .horizontal)
        warningTopUpButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    // MARK: - Gradient masking

    private func applyValueGradient() {
        // Same recipe as SPBalanceCard.applyValueGradient — render the
        // glyph outlines into an offscreen image and use it as the
        // gradient layer's mask. Re-runs every layout so font / size
        // changes refresh the mask.
        let textBounds = balanceValueLabel.bounds
        guard textBounds.width > 0, textBounds.height > 0 else { return }
        if balanceValueGradient.superlayer !== balanceValueLabel.layer {
            balanceValueLabel.layer.addSublayer(balanceValueGradient)
        }
        balanceValueGradient.frame = textBounds

        let renderer = UIGraphicsImageRenderer(size: textBounds.size)
        let mask = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            (balanceValueLabel.text ?? "").draw(
                in: textBounds,
                withAttributes: [
                    .font: balanceValueLabel.font as Any,
                    .foregroundColor: UIColor.white
                ]
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = textBounds
        maskLayer.contents = mask.cgImage
        balanceValueGradient.mask = maskLayer
        // Hide the label paint so we don't double-render.
        balanceValueLabel.textColor = .clear
    }

    // MARK: - Actions

    @objc private func balanceTopUpTapped() {
        onBalanceTopUpTap?()
    }

    @objc private func warnTopUpTapped() {
        onWarnTopUpTap?()
    }
}

// MARK: - Radial overlay

/// Reuses the SPBalanceCard radial-highlight recipe (80% × 60% money tint
/// at top-right). Kept private to this file so the SP* primitive isn't
/// touched.
private final class AlarmsHeaderRadialOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            AppColors.money400.withAlphaComponent(0.18).cgColor,
            UIColor.clear.cgColor
        ]
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: [0.0, 1.0]
        ) else { return }
        let centerPoint = CGPoint(x: rect.maxX, y: rect.minY)
        let radius = max(rect.width, rect.height) * 0.6
        context.drawRadialGradient(
            gradient,
            startCenter: centerPoint,
            startRadius: 0,
            endCenter: centerPoint,
            endRadius: radius,
            options: []
        )
    }
}
