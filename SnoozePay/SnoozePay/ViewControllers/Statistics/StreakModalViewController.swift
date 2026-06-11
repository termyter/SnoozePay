import UIKit

/// Streak celebration modal — V3 design (de-monetized, issue #236).
///
/// V3 drops every money mention from the V2 sheet (`SPScreensV2.jsx`
/// `StreakModalV2()`): no "+350 ₽" hero, no "Сэкономили за неделю", no share
/// button. The celebration is purely behavioral — the habit is the reward.
///
/// Visual recipe:
/// - Black 92% overlay + radial money green glow background painted over the
///   underlying screen. Implemented with a custom-presentation host: backdrop
///   view + sheet card on top.
/// - Sheet anchored to the bottom with `bg2` fill, 28pt corners, 1pt
///   `strokeMoney` border, money-tinted glow shadow.
/// - 96×96 rounded-rect (28pt radius) with the money gradient and a flame
///   icon — sits centered at the top of the sheet.
/// - Caps "СЕРИЯ" in `money300`.
/// - h1 "N дней без откладываний" in `fg1`.
/// - Body — "Это уже не случайность — это привычка. Тело знает, что подъём
///   вовремя — это просто." in `fg3`.
/// - 7 day-pip row with the money gradient (numbered 1-7) below the body.
/// - Single `SPButton(.money, .lg, fullWidth: true)` "Закрыть" that dismisses.
final class StreakModalViewController: UIViewController {

    // MARK: - Configuration

    /// Number of consecutive snooze-free days. Drives the headline + the
    /// completed-square count in the 7-day visualizer.
    private let streakDays: Int

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
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()

    private let pipStrip = UIStackView()

    private let closeButton = SPButton(
        title: "Закрыть",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    // MARK: - Init

    /// - Parameter streakDays: Consecutive snooze-free days. `0` is
    ///   technically allowed (the modal would just look empty) — callers gate
    ///   via `presentStreakModalIfNeeded(...)` so this never lands at zero in
    ///   production.
    init(streakDays: Int) {
        self.streakDays = streakDays
        super.init(nibName: nil, bundle: nil)
        // Custom overlay presentation so we can paint our own backdrop with
        // a money-tinted radial glow.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    /// Transition shim for V2-era call sites that still compute a saved
    /// amount. V3 ignores the money figure entirely — the parameter exists
    /// only so in-flight branches keep compiling; new code should call
    /// `init(streakDays:)`.
    convenience init(streakDays: Int, savedAmount: Decimal) {
        _ = savedAmount
        self.init(streakDays: streakDays)
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
        capsLabel.attributedText = NSAttributedString(
            string: "СЕРИЯ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.money300
            ]
        )
        capsLabel.textAlignment = .center
        capsLabel.numberOfLines = 0
        capsLabel.translatesAutoresizingMaskIntoConstraints = false

        headlineLabel.text = "\(streakDays) \(Self.dayWord(for: streakDays)) без откладываний"
        headlineLabel.font = AppTypography.h1
        headlineLabel.textColor = AppColors.fg1
        headlineLabel.textAlignment = .center
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.text = "Это уже не случайность — это привычка. "
            + "Тело знает, что подъём вовремя — это просто."
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
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
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

        let stack = UIStackView(arrangedSubviews: [
            flameBadge,
            capsLabel,
            headlineLabel,
            bodyLabel,
            pipWrap,
            closeButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        stack.setCustomSpacing(AppSpacing.sp5, after: flameBadge)
        stack.setCustomSpacing(AppSpacing.sp2, after: capsLabel)
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

            // Button stretches to the full stack width.
            closeButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

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

    // MARK: - Helpers

    /// Russian plural for "день / дня / дней". The streak-modal headline hits
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
    /// alarm penalties.
    ///
    /// The V3 modal no longer renders money, but the alarms-list streak
    /// banner (`AlarmsStreakBannerView`) still surfaces this estimate, so the
    /// helper stays here as the single source of the savings math.
    /// Follow-up #142: replace with the exact `expectedPenalty * snoozesSaved`
    /// once the per-alarm history surface lands.
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
