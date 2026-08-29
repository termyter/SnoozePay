import UIKit

// MARK: - Onboarding-only helper views
//
// Bespoke per-screen primitives used by the V2 onboarding flow. They aren't
// re-used outside this folder (specs are page-specific), so they live here
// instead of the shared `Views/DesignSystem/SP*` family. Kept in their own
// file so `OnboardingViewController+Pages.swift` stays under the
// `file_length: 600` SwiftLint warning.

/// Thin UIView wrapper that owns a CAGradientLayer and resizes it on layout.
/// Used by the page-1 warm glow so its frame tracks the host view's bounds
/// without polluting the page's responder chain.
final class OnboardingGlowHostView: UIView {

    private let glow: CAGradientLayer

    init(layer: CAGradientLayer, size: CGFloat) {
        self.glow = layer
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        self.layer.insertSublayer(glow, at: 0)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds
        CATransaction.commit()
    }
}

/// "−50 ₽" warn pill used as the hero accent on Onboarding step 1. Pure
/// presentation — gradient fill + warm shadow + mono label.
final class OnboardingPenaltyPill: UIView {

    private let gradient: CAGradientLayer
    private let label = UILabel()

    init() {
        gradient = CAGradientLayer()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureChrome()
        configureLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureChrome() {
        gradient.colors = SPSupport.warnGradientColors
        gradient.locations = SPSupport.warnGradientLocations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        layer.insertSublayer(gradient, at: 0)
        // Warm shadow per JSX `boxShadow: 0 8px 24px rgba(245,158,11,.30)`.
        layer.shadowColor = AppColors.warn500.cgColor
        layer.shadowOpacity = 0.30
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 24
        layer.masksToBounds = false
    }

    private func configureLabel() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "−\(MoneyFormatter.string(50))"
        label.font = AppTypography.moneySm  // mono digits for the penalty pill (#289)
        label.textColor = AppColors.fgOnWarn
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let radius = bounds.height / 2
        gradient.cornerRadius = radius
        layer.cornerRadius = radius
        CATransaction.commit()
    }
}

/// Numbered explainer row used on Onboarding step 2 — 32×32 badge with a
/// mono digit, title h4, body meta.
final class OnboardingStepRow: UIView {

    init(number: String, title: String, body: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let badge = makeBadge(number: number)
        let titleLabel = makeTitle(text: title)
        let bodyLabel = makeBody(text: body)

        addSubview(badge)
        addSubview(titleLabel)
        addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 32),
            badge.heightAnchor.constraint(equalToConstant: 32),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor),
            badge.topAnchor.constraint(equalTo: topAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            bottomAnchor.constraint(greaterThanOrEqualTo: badge.bottomAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: bodyLabel.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeBadge(number: String) -> UILabel {
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = number
        badge.font = AppTypography.buttonSm
        badge.textAlignment = .center
        badge.textColor = AppColors.fg2
        badge.backgroundColor = AppColors.whiteOverlay08
        badge.layer.cornerRadius = AppRadius.xs + 2      // 10pt — matches JSX
        badge.layer.masksToBounds = true
        return badge
    }

    private func makeTitle(text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = AppTypography.h4
        label.textColor = .white
        label.numberOfLines = 0
        return label
    }

    private func makeBody(text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = AppTypography.meta
        label.textColor = AppColors.fg2
        label.numberOfLines = 0
        return label
    }
}

/// Pill-shaped page indicator dot. Active = 24×6 with money gradient,
/// inactive = 6×6 with whiteOverlay12.
final class OnboardingPageDot: UIView {

    private let gradient = CAGradientLayer()

    init(isActive: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 3
        layer.masksToBounds = true
        if isActive {
            gradient.colors = SPSupport.moneyGradientColors
            gradient.locations = SPSupport.moneyGradientLocations
            gradient.startPoint = SPSupport.gradientStart
            gradient.endPoint = SPSupport.gradientEnd
            layer.insertSublayer(gradient, at: 0)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 24),
                heightAnchor.constraint(equalToConstant: 6)
            ])
        } else {
            backgroundColor = AppColors.whiteOverlay12
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 6),
                heightAnchor.constraint(equalToConstant: 6)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}

/// Deposit option card used on Onboarding step 3 — title h4, "ПОПУЛЯРНО"
/// caps tag when applicable, description meta, trailing mono amount. When
/// `isSelectedOption` is true the fill takes a 8% money tint, the border
/// becomes `money400` at 40%, and the amount glyph switches to `money300`.
final class OnboardingDepositOptionView: UIControl {

    private let option: OnboardingViewController.DepositOption
    /// Trims the card's vertical padding on compact-height devices (#244).
    private let isCompact: Bool
    private let titleLabel = UILabel()
    private let popularLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let amountLabel = UILabel()

    var onTap: (() -> Void)?

    var isSelectedOption: Bool = false {
        didSet { applySelection() }
    }

    override var isHighlighted: Bool {
        didSet { SPSupport.animatePress(self, pressed: isHighlighted) }
    }

    init(option: OnboardingViewController.DepositOption, isCompact: Bool = false) {
        self.option = option
        self.isCompact = isCompact
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureChrome()
        configureLabels()
        installLayout()
        applySelection()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureChrome() {
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.masksToBounds = true
    }

    private func configureLabels() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = option.title
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = .white

        popularLabel.translatesAutoresizingMaskIntoConstraints = false
        if option.isPopular {
            popularLabel.attributedText = NSAttributedString(
                string: "ПОПУЛЯРНО",
                attributes: [
                    .font: AppFonts.sans(.bold, 10),
                    .kern: 10 * 0.12,
                    .foregroundColor: AppColors.money300
                ]
            )
        } else {
            popularLabel.isHidden = true
        }

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.text = option.description
        descriptionLabel.font = AppTypography.meta
        descriptionLabel.textColor = AppColors.fg3
        descriptionLabel.numberOfLines = 0
        // The amount label is incompressible; the description is the side that
        // must give. Saying so explicitly keeps the engine from ever widening
        // the text column to satisfy this label's single-line intrinsic width.
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.attributedText = MoneyFormatter.attributed(
            option.amount, digitsFont: AppTypography.moneyMd
        )
        amountLabel.font = AppTypography.moneyMd
        amountLabel.textColor = AppColors.fg1
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func installLayout() {
        // The spacer soaks up the slack once the row is stretched to the
        // stack's width (below), so the two labels keep their intrinsic
        // widths instead of one of them growing on a hugging tie (#519).
        let titleSpacer = UIView()
        titleSpacer.translatesAutoresizingMaskIntoConstraints = false
        titleSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        let titleRow = UIStackView(arrangedSubviews: [titleLabel, popularLabel, titleSpacer])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.spacing = AppSpacing.sp2
        titleRow.alignment = .center

        // `.fill`, not `.leading`: under `.leading` each arranged subview keeps
        // its own intrinsic width, so the multi-line description asked for its
        // full single-line width inside a column the incompressible amount
        // label had already capped. On the one card whose title row carries a
        // second visible label — the "ПОПУЛЯРНО" tag — the engine settled that
        // by squeezing the description to 8pt and wrapping it one character
        // per line, 550pt tall, blowing the card up to 608pt (#534).
        let textStack = UIStackView(arrangedSubviews: [titleRow, descriptionLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .fill

        let rowStack = UIStackView(arrangedSubviews: [textStack, amountLabel])
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = AppSpacing.sp3
        rowStack.isUserInteractionEnabled = false

        // 16pt canonical → 12pt vertical on SE so three cards clear the CTA.
        let verticalPad: CGFloat = isCompact ? 12 : 16
        addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: verticalPad),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPad),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
        ])
    }

    private func applySelection() {
        if isSelectedOption {
            backgroundColor = AppColors.money400.withAlphaComponent(0.08)
            layer.borderColor = AppColors.money400.withAlphaComponent(0.40).cgColor
            amountLabel.textColor = AppColors.money300
        } else {
            backgroundColor = AppColors.whiteOverlay06
            layer.borderColor = AppColors.whiteOverlay08.resolvedColor(with: traitCollection).cgColor
            amountLabel.textColor = AppColors.fg1
        }
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}
