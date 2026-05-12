import UIKit

/// Streak celebration modal — V2 design (`docs/design/v2-handoff/components/`
/// `SPScreensV2.jsx` lines 653-732, `StreakModalV2()`).
///
/// Visual recipe:
/// - Black 92% overlay + radial money green glow background painted over the
///   underlying screen. Implemented with a custom-presentation host: backdrop
///   view + sheet card on top.
/// - Sheet anchored to the bottom with `bg2` fill, 28pt corners, 1pt
///   `strokeMoney` border, money-tinted glow shadow.
/// - 96×96 rounded-rect (28pt radius) with the money gradient and a flame
///   icon — sits centered at the top of the sheet.
/// - Caps "Серия · N дней без откладываний" in `money300`.
/// - Hero amount "+350 ₽" at `moneyXl` masked with the money gradient via
///   the shared `UILabel.applyGradientMask(_:)` helper.
/// - h3 "Сэкономили за неделю" in `fg1`.
/// - Body — "Деньги вернули на баланс. Потратьте их на следующей слабой
///   неделе." in `fg3`.
/// - 7 day-pip row with the money gradient (numbered 1-7) below the body.
/// - Primary `SPButton(.money, .lg, fullWidth: true)` "Поделиться победой"
///   that pops a `UIActivityViewController` so the streak goes onto socials.
/// - Secondary `SPButton(.quiet, .md, fullWidth: true)` "Закрыть" that
///   dismisses.
///
/// Saved amount carries the same estimation caveat as before — see
/// `estimatedSavings(for:alarms:)`.
final class StreakModalViewController: UIViewController {

    // MARK: - Configuration

    /// Number of consecutive snooze-free days. Drives the caption + the
    /// completed-square count in the 7-day visualizer.
    private let streakDays: Int

    /// Approximate roubles saved across the streak — the value the hero
    /// number renders.
    private let savedAmount: Decimal

    // MARK: - Subviews

    /// Sheet card — contains every visible widget. Anchored to the bottom
    /// of the screen, padded by safe-area + screenInset.
    private let sheet = UIView()
    private let backdrop = UIView()
    private let backdropGlow = CAGradientLayer()

    private let flameBadge = UIView()
    private let flameBadgeGradient = CAGradientLayer()
    private let flameIcon = UIImageView()

    private let capsLabel = UILabel()
    private let amountLabel = UILabel()
    private let amountGradient = CAGradientLayer()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()

    private let pipStrip = UIStackView()

    private let primaryButton = SPButton(
        title: "Поделиться победой",
        variant: .money,
        size: .lg,
        fullWidth: true
    )
    private let secondaryButton = SPButton(
        title: "Закрыть",
        variant: .quiet,
        size: .md,
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
        // Custom overlay presentation so we can paint our own backdrop with
        // a money-tinted radial glow.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureBackdrop()
        configureSheet()
        configureFlameBadge()
        configureLabels()
        configurePipStrip()
        configureButtons()
        layout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropGlow.frame = view.bounds
        flameBadgeGradient.frame = flameBadge.bounds
        amountLabel.applyGradientMask(amountGradient)
        // Shadow path tracks the sheet's rounded rect so the soft glow doesn't
        // pay an offscreen pass on every layout while the sheet animates in.
        sheet.layer.shadowPath = UIBezierPath(
            roundedRect: sheet.bounds,
            cornerRadius: AppRadius.xl
        ).cgPath
    }

    // MARK: - Configuration

    private func configureBackdrop() {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Radial money glow as a CAGradientLayer (.radial) above the dim.
        backdropGlow.type = .radial
        backdropGlow.colors = [
            AppColors.money400.withAlphaComponent(0.30).cgColor,
            UIColor.clear.cgColor
        ]
        backdropGlow.locations = [0.0, 1.0]
        backdropGlow.startPoint = CGPoint(x: 0.5, y: 0.75)
        backdropGlow.endPoint = CGPoint(x: 1.1, y: 1.35)
        view.layer.addSublayer(backdropGlow)

        // Tap on the backdrop dismisses.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        backdrop.addGestureRecognizer(tap)
    }

    private func configureSheet() {
        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.backgroundColor = AppColors.bg2
        sheet.layer.cornerRadius = AppRadius.xl
        sheet.layer.cornerCurve = .continuous
        sheet.layer.borderColor = AppColors.strokeMoney
            .resolvedColor(with: traitCollection).cgColor
        sheet.layer.borderWidth = 1
        sheet.layer.shadowColor = AppColors.money500.cgColor
        sheet.layer.shadowOpacity = 0.30
        sheet.layer.shadowOffset = CGSize(width: 0, height: -12)
        sheet.layer.shadowRadius = 32
        view.addSubview(sheet)
    }

    private func configureFlameBadge() {
        flameBadge.translatesAutoresizingMaskIntoConstraints = false
        flameBadge.layer.cornerRadius = AppRadius.xl
        flameBadge.layer.cornerCurve = .continuous
        flameBadge.layer.shadowColor = AppColors.money500.cgColor
        flameBadge.layer.shadowOpacity = 0.40
        flameBadge.layer.shadowOffset = CGSize(width: 0, height: 12)
        flameBadge.layer.shadowRadius = 24

        flameBadgeGradient.colors = SPSupport.moneyGradientColors
        flameBadgeGradient.locations = SPSupport.moneyGradientLocations
        flameBadgeGradient.startPoint = SPSupport.gradientStart
        flameBadgeGradient.endPoint = SPSupport.gradientEnd
        flameBadgeGradient.cornerRadius = AppRadius.xl
        flameBadge.layer.insertSublayer(flameBadgeGradient, at: 0)

        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
        flameIcon.image = UIImage(systemName: "flame.fill", withConfiguration: config)
        flameIcon.tintColor = AppColors.fgOnMoney
        flameIcon.contentMode = .scaleAspectFit
        flameIcon.translatesAutoresizingMaskIntoConstraints = false
        flameBadge.addSubview(flameIcon)

        NSLayoutConstraint.activate([
            flameBadge.widthAnchor.constraint(equalToConstant: 96),
            flameBadge.heightAnchor.constraint(equalToConstant: 96),
            flameIcon.centerXAnchor.constraint(equalTo: flameBadge.centerXAnchor),
            flameIcon.centerYAnchor.constraint(equalTo: flameBadge.centerYAnchor)
        ])
    }

    private func configureLabels() {
        let capsText = "СЕРИЯ · \(streakDays) \(Self.dayWord(for: streakDays).uppercased()) "
            + "БЕЗ ОТКЛАДЫВАНИЙ"
        capsLabel.attributedText = NSAttributedString(
            string: capsText,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.money300
            ]
        )
        capsLabel.textAlignment = .center
        capsLabel.numberOfLines = 0
        capsLabel.translatesAutoresizingMaskIntoConstraints = false

        amountLabel.font = AppTypography.moneyXl
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontForContentSizeCategory = false
        amountLabel.textColor = AppColors.money400   // safety-net pre-mask
        amountLabel.text = Self.formatSavedAmount(savedAmount)
        amountLabel.translatesAutoresizingMaskIntoConstraints = false

        amountGradient.colors = SPSupport.moneyGradientColors
        amountGradient.locations = SPSupport.moneyGradientLocations
        amountGradient.startPoint = SPSupport.gradientStart
        amountGradient.endPoint = SPSupport.gradientEnd

        headlineLabel.text = "Сэкономили за неделю"
        headlineLabel.font = AppTypography.h3
        headlineLabel.textColor = AppColors.fg1
        headlineLabel.textAlignment = .center
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.text = "Деньги вернули на баланс. Потратьте их на следующей слабой неделе."
        bodyLabel.font = AppTypography.body
        bodyLabel.textColor = AppColors.fg3
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configurePipStrip() {
        pipStrip.axis = .horizontal
        pipStrip.distribution = .fillEqually
        pipStrip.spacing = AppSpacing.sp1
        pipStrip.alignment = .fill
        pipStrip.translatesAutoresizingMaskIntoConstraints = false
        // 7 numbered green pips. Streaks < 7 fade out future pips by lowering
        // their alpha; streaks ≥ 7 keep all seven at full intensity.
        let completed = max(0, min(7, streakDays))
        for index in 0..<7 {
            let pip = makePip(number: index + 1, lit: index < completed)
            pipStrip.addArrangedSubview(pip)
        }
    }

    private func makePip(number: Int, lit: Bool) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.sm
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.heightAnchor.constraint(equalToConstant: 32).isActive = true
        view.widthAnchor.constraint(equalToConstant: 32).isActive = true

        if lit {
            let gradient = CAGradientLayer()
            gradient.colors = SPSupport.moneyGradientColors
            gradient.locations = SPSupport.moneyGradientLocations
            gradient.startPoint = SPSupport.gradientStart
            gradient.endPoint = SPSupport.gradientEnd
            gradient.cornerRadius = AppRadius.sm
            // Defer the frame assignment to the next runloop so the sublayer
            // tracks the resolved bounds set by the 32×32 anchors above.
            DispatchQueue.main.async {
                gradient.frame = view.bounds
            }
            view.layer.insertSublayer(gradient, at: 0)
        } else {
            view.backgroundColor = AppColors.whiteOverlay08
        }

        let label = UILabel()
        label.text = "\(number)"
        label.font = AppFonts.mono(.bold, 13)
        label.textColor = lit ? AppColors.fgOnMoney : AppColors.fg3
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func configureButtons() {
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
    }

    private func layout() {
        let pipWrap = UIView()
        pipWrap.translatesAutoresizingMaskIntoConstraints = false
        pipWrap.addSubview(pipStrip)
        NSLayoutConstraint.activate([
            pipStrip.centerXAnchor.constraint(equalTo: pipWrap.centerXAnchor),
            pipStrip.topAnchor.constraint(equalTo: pipWrap.topAnchor),
            pipStrip.bottomAnchor.constraint(equalTo: pipWrap.bottomAnchor),
            pipStrip.leadingAnchor.constraint(greaterThanOrEqualTo: pipWrap.leadingAnchor),
            pipStrip.trailingAnchor.constraint(lessThanOrEqualTo: pipWrap.trailingAnchor)
        ])

        let buttonsStack = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        buttonsStack.axis = .vertical
        buttonsStack.spacing = AppSpacing.sp2
        buttonsStack.alignment = .fill
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [
            flameBadge,
            capsLabel,
            amountLabel,
            headlineLabel,
            bodyLabel,
            pipWrap,
            buttonsStack
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        stack.setCustomSpacing(AppSpacing.sp5, after: flameBadge)
        stack.setCustomSpacing(AppSpacing.sp2, after: capsLabel)
        stack.setCustomSpacing(AppSpacing.sp2, after: amountLabel)
        stack.setCustomSpacing(AppSpacing.sp2, after: headlineLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: bodyLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: pipWrap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(stack)

        NSLayoutConstraint.activate([
            // Sheet anchored to the bottom with screen-inset margins.
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp3),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp3),
            sheet.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp4
            ),

            // Stack inside sheet, 28pt padded.
            stack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: AppSpacing.sp6),
            stack.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -AppSpacing.sp6),
            stack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: AppSpacing.sp6),
            stack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -AppSpacing.sp6),

            // Buttons stretch to the full stack width.
            primaryButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            secondaryButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            secondaryButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            // Pip wrap row stretches but the strip itself centres inside.
            pipWrap.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            pipWrap.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            // Headline + body stretch full-width so multi-line centres.
            capsLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            capsLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            bodyLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        let text = "SnoozePay: \(streakDays) \(Self.dayWord(for: streakDays)) подряд без откладываний — "
            + "сэкономлено \(Self.formatSavedAmount(savedAmount))."
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // iPad popover anchor — the system picker insists on a source view.
        activity.popoverPresentationController?.sourceView = primaryButton
        activity.popoverPresentationController?.sourceRect = primaryButton.bounds
        present(activity, animated: true)
    }

    // MARK: - Helpers

    /// Format the saved amount as `+1 234 ₽` with the brand thousand separator.
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
