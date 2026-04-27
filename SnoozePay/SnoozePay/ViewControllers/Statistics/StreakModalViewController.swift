import UIKit

/// Streak celebration modal — section "28 · Streak модалка" in
/// `docs/design/snoozepay-2026-04-27/project/SnoozePay - All Screens.html`.
///
/// Visual recipe:
/// - `pageSheet` with a medium detent (~440pt) and a 28pt top corner radius
///   so the sheet reads as one of the brand `r-sheet` surfaces (matches
///   `--sp-radius-xl` from `tokens.css`).
/// - 🔥 flame icon with the money tint at the top.
/// - Big amount line ("+350 ₽") drawn at `AppTypography.moneyXl` and masked
///   with the money gradient, reusing the same CALayer + image-mask trick
///   from `SPBalanceCard.applyValueGradient(...)` so the gradient tracks
///   the rendered glyph outlines.
/// - Caption "{D} дней без откладываний" in `AppTypography.body` / `fg2`.
/// - 7-day visualizer: a horizontal stack of 7 squares.
///   * `completed` days are filled with the money gradient.
///   * `today` is outline-only with a 2pt money stroke and the day number
///     drawn in money tint.
///   * `future` days fall back to `whiteOverlay08` so they read as muted.
/// - A primary `SPButton(.money, .lg, fullWidth: true)` "Отлично, продолжаю"
///   dismisses the sheet.
///
/// The "saved" amount on the hero number is the sum of penalties the user
/// did NOT pay during the streak window. Computing that exactly would require
/// knowing the would-have-fired schedule for each alarm in the window — too
/// much for one PR. Until a follow-up wires up `expectedPenalty * snoozesSaved`,
/// we approximate with `streakDays * defaultPenalty` (50 ₽/day fallback when
/// no alarms exist) so the modal still tells a coherent story.
final class StreakModalViewController: UIViewController {

    // MARK: - Configuration

    /// Number of consecutive snooze-free days. Drives the caption + the
    /// completed-square count in the 7-day visualizer.
    private let streakDays: Int

    /// Approximate roubles saved across the streak — the value the hero
    /// number renders. See class doc comment for the approximation caveat.
    private let savedAmount: Decimal

    // MARK: - Subviews

    private let flameIcon = UIImageView()
    private let amountLabel = UILabel()
    private let amountGradient = CAGradientLayer()
    private let captionLabel = UILabel()
    private let dayStrip = UIStackView()
    private let primaryButton = SPButton(
        title: "Отлично, продолжаю",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    // MARK: - Init

    /// - Parameters:
    ///   - streakDays: Consecutive snooze-free days. `0` is technically
    ///     allowed (the modal would just look empty) — callers gate via
    ///     `presentStreakModalIfNeeded(...)` so this never lands at zero
    ///     in production.
    ///   - savedAmount: Money the user did not lose. Caller computes this;
    ///     see `StreakModalViewController.estimatedSavings(for:)` for the
    ///     default 50 ₽/day fallback used when no transaction history is
    ///     available.
    init(streakDays: Int, savedAmount: Decimal) {
        self.streakDays = streakDays
        self.savedAmount = savedAmount
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // Medium detent ≈ 440pt — close enough to the spec without
            // pinning a brittle .custom() resolver. Top-corner radius
            // matches `--sp-radius-xl` so the sheet reads as one of the
            // existing `r-sheet` surfaces.
            sheet.detents = [.medium()]
            sheet.preferredCornerRadius = AppRadius.xl
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg1
        configureFlameIcon()
        configureAmountLabel()
        configureCaptionLabel()
        configureDayStrip()
        configureButton()
        layout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyAmountGradient()
    }

    // MARK: - Configuration

    private func configureFlameIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
        flameIcon.image = UIImage(systemName: "flame.fill", withConfiguration: config)
        flameIcon.tintColor = AppColors.money500
        flameIcon.contentMode = .scaleAspectFit
        flameIcon.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureAmountLabel() {
        amountLabel.font = AppTypography.moneyXl
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontForContentSizeCategory = false
        // Neutral colour as a safety net — `applyAmountGradient` promotes
        // this to a gradient text mask once layout resolves.
        amountLabel.textColor = AppColors.fg1
        amountLabel.text = Self.formatSavedAmount(savedAmount)
        amountLabel.translatesAutoresizingMaskIntoConstraints = false

        amountGradient.colors = SPSupport.moneyGradientColors
        amountGradient.locations = SPSupport.moneyGradientLocations
        amountGradient.startPoint = SPSupport.gradientStart
        amountGradient.endPoint = SPSupport.gradientEnd
    }

    private func configureCaptionLabel() {
        captionLabel.text = "\(streakDays) \(Self.dayWord(for: streakDays)) без откладываний"
        captionLabel.font = AppTypography.body
        captionLabel.textColor = AppColors.fg2
        captionLabel.textAlignment = .center
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureDayStrip() {
        dayStrip.axis = .horizontal
        dayStrip.distribution = .fillEqually
        dayStrip.alignment = .fill
        dayStrip.spacing = AppSpacing.sp2
        dayStrip.translatesAutoresizingMaskIntoConstraints = false
        // Render 7 squares — clamped to [0, 7] for visualisation. Streaks
        // longer than 7 days still show a fully-filled strip; the hero
        // number carries the absolute count.
        let completed = max(0, min(7, streakDays - 1))
        let todayIndex = max(0, min(6, streakDays - 1))
        for index in 0..<7 {
            let kind: DaySquareView.Kind
            if index < completed {
                kind = .completed
            } else if index == todayIndex && streakDays >= 1 && streakDays <= 7 {
                kind = .today(dayNumber: index + 1)
            } else {
                kind = .future
            }
            let square = DaySquareView(kind: kind)
            dayStrip.addArrangedSubview(square)
        }
    }

    private func configureButton() {
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
    }

    private func layout() {
        let stack = UIStackView(arrangedSubviews: [
            flameIcon,
            amountLabel,
            captionLabel,
            dayStrip,
            primaryButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp4
        stack.setCustomSpacing(AppSpacing.sp2, after: flameIcon)
        stack.setCustomSpacing(AppSpacing.sp5, after: captionLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: dayStrip)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            flameIcon.heightAnchor.constraint(equalToConstant: 56),
            flameIcon.widthAnchor.constraint(equalToConstant: 56),
            dayStrip.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            dayStrip.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            primaryButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: AppSpacing.sp6
            ),
            stack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp5
            )
        ])
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    // MARK: - Gradient text mask
    //
    // Same recipe as `SPBalanceCard.applyValueGradient(...)` — install the
    // money gradient as a sublayer of the label and mask it with a raster
    // of the rendered glyphs. CoreText doesn't expose CSS's
    // `-webkit-background-clip: text` so the mask trick is the cheapest
    // way to keep the gradient tracking the digit baseline across font /
    // size / theme transitions.

    private func applyAmountGradient() {
        let textBounds = amountLabel.bounds
        guard textBounds.width > 0, textBounds.height > 0 else { return }
        if amountGradient.superlayer !== amountLabel.layer {
            amountLabel.layer.addSublayer(amountGradient)
        }
        amountGradient.frame = textBounds

        let renderer = UIGraphicsImageRenderer(size: textBounds.size)
        let mask = renderer.image { _ in
            (amountLabel.text ?? "").draw(
                in: textBounds,
                withAttributes: [
                    .font: amountLabel.font as Any,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: { () -> NSParagraphStyle in
                        let style = NSMutableParagraphStyle()
                        style.alignment = .center
                        return style
                    }()
                ]
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = textBounds
        maskLayer.contents = mask.cgImage
        amountGradient.mask = maskLayer
        amountLabel.textColor = .clear
    }

    // MARK: - Helpers

    /// Format the saved amount as `+1 234 ₽` with the brand thousand separator.
    /// Reuses `Decimal.formattedRubles()` to stay consistent with the balance
    /// card and the firing top-up sheet.
    static func formatSavedAmount(_ amount: Decimal) -> String {
        "+\(amount.formattedRubles())"
    }

    /// Russian plural for "день / дня / дней". The streak-modal caption hits
    /// all three forms across the 3 / 7 / 14 / 30 milestones plus future
    /// arbitrary streaks, so we do the full Slavic-plural switch instead of
    /// hardcoding "дней".
    static func dayWord(for count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 { return "дней" }
        switch mod10 {
        case 1: return "день"
        case 2, 3, 4: return "дня"
        default: return "дней"
        }
    }

    /// Default rouble-per-day estimate when callers can't compute the exact
    /// "would-have-paid" amount. 50 ₽ matches the default `Alarm.penaltyAmount`
    /// so the approximation tracks the average user.
    private static let defaultDailyPenalty: Decimal = 50

    /// Approximate the saved amount over `streakDays`. Uses the default
    /// 50 ₽/day when no alarms exist, otherwise averages the registered
    /// alarm penalties. Follow-up #142: replace with the exact
    /// `expectedPenalty * snoozesSaved` once the per-alarm history surface
    /// lands.
    static func estimatedSavings(for streakDays: Int, alarms: [Alarm]) -> Decimal {
        guard streakDays > 0 else { return 0 }
        let dailyPenalty: Decimal
        if alarms.isEmpty {
            dailyPenalty = defaultDailyPenalty
        } else {
            // Format-string round-trip dodges the `Double → Decimal`
            // binary-fraction surprise (50.0 → 49.99999…).
            let total = alarms.reduce(Decimal(0)) { partial, alarm in
                let parsed = Decimal(string: String(format: "%.2f", alarm.penaltyAmount)) ?? Decimal(0)
                return partial + parsed
            }
            var average = total
            var divisor = Decimal(alarms.count)
            var rounded = Decimal()
            NSDecimalDivide(&rounded, &average, &divisor, .plain)
            dailyPenalty = rounded
        }
        return dailyPenalty * Decimal(streakDays)
    }
}

// MARK: - Day square

/// One of the seven squares rendered above the primary CTA. The visual
/// recipe maps 1:1 onto the design spec:
/// - `.completed` → money-gradient fill, no text.
/// - `.today` → transparent fill with a 2pt money stroke and the day
///   number drawn in money tint.
/// - `.future` → `whiteOverlay08` fill so future days read as muted.
private final class DaySquareView: UIView {
    enum Kind {
        case completed
        case today(dayNumber: Int)
        case future
    }

    private let kind: Kind
    private let label = UILabel()
    private var gradientLayer: CAGradientLayer?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        layer.cornerRadius = AppRadius.md
        layer.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        // Square via 1:1 aspect — fill-equally distribution sets the width.
        widthAnchor.constraint(equalTo: heightAnchor).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = AppFonts.mono(.bold, 14)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        applyKind()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Strokes / overlays are dynamic colours — re-resolve their cgColor
        // representations for the current trait so a light/dark switch
        // doesn't leave the previous theme's hex baked into CALayer.
        applyKind()
    }

    private func applyKind() {
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        layer.borderWidth = 0
        backgroundColor = .clear
        label.text = nil

        switch kind {
        case .completed:
            let gradient = CAGradientLayer()
            gradient.colors = SPSupport.moneyGradientColors
            gradient.locations = SPSupport.moneyGradientLocations
            gradient.startPoint = SPSupport.gradientStart
            gradient.endPoint = SPSupport.gradientEnd
            gradient.frame = bounds
            layer.insertSublayer(gradient, at: 0)
            gradientLayer = gradient
        case .today(let dayNumber):
            backgroundColor = .clear
            layer.borderWidth = 2
            layer.borderColor = AppColors.money500.cgColor
            label.text = "\(dayNumber)"
            label.textColor = AppColors.money500
        case .future:
            backgroundColor = AppColors.whiteOverlay08
        }
    }
}
