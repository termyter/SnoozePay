import UIKit

/// Streak celebration modal — money-hero layout (issue #347).
///
/// History: V2 (`SPScreensV2.jsx` `StreakModalV2()`, artboard `28-streak`) led
/// with the saved amount and offered a share CTA. V3 (#236) stripped every
/// money mention and left a single "Закрыть". PM re-opened the call on
/// 2026-07-30 (#347): the sheet leads with **the money saved**, the streak
/// drops to the caption line, and the primary CTA shares the win. This file is
/// that decision — V2's information hierarchy on top of V3's spacing polish
/// (#289).
///
/// Visual recipe:
/// - Black 92% overlay + radial money green glow background painted over the
///   underlying screen. Implemented with a custom-presentation host: backdrop
///   view + sheet card on top.
/// - Sheet anchored to the bottom with `bg2` fill, 28pt corners, 1pt
///   `strokeMoney` border, money-tinted glow shadow.
/// - 96×96 rounded-rect (28pt radius) with the money gradient and a flame
///   icon — sits centered at the top of the sheet.
/// - Caps "СЕРИЯ · N ДНЕЙ БЕЗ ОТКЛАДЫВАНИЙ" in `money300` — the streak is the
///   caption now, not the headline.
/// - Hero `moneyXl` "+350 ₽" with the money gradient masked onto the glyphs.
/// - h3 "Сэкономили за неделю" in `fg1`.
/// - Body — "Эти деньги остались у вас на балансе…" in `fg3`.
/// - 7 day-pip row (`SPStreakPipStrip`) below the body.
/// - `SPButton(.money, .lg)` "Поделиться победой" → `UIActivityViewController`,
///   plus a `SPButton(.quiet, .md)` "Закрыть".
final class StreakModalViewController: UIViewController {

    // MARK: - Configuration

    /// Number of consecutive snooze-free days. Drives the caption + the
    /// completed-square count in the 7-day visualizer.
    private let streakDays: Int

    /// Caller-supplied saved amount. `nil` means "work it out yourself" — see
    /// `resolvedSavings`.
    private let savedAmountOverride: Decimal?

    /// Money the user did not lose over the streak. Resolved once, lazily, so
    /// the repository read happens on the main-thread `viewDidLoad` pass and
    /// not inside `init`.
    private lazy var resolvedSavings: Decimal = savedAmountOverride
        ?? Self.estimatedSavings(
            for: streakDays,
            alarms: (try? AlarmRepository.shared.fetchAllChecked()) ?? []
        )

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

    private lazy var pipStrip = SPStreakPipStrip(completed: streakDays)

    private let shareButton = SPButton(
        title: "Поделиться победой",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    private let closeButton = SPButton(
        title: "Закрыть",
        variant: .quiet,
        size: .md,
        fullWidth: true
    )

    // MARK: - Init

    /// - Parameters:
    ///   - streakDays: Consecutive snooze-free days. `0` is technically
    ///     allowed (the modal would just look empty) — callers gate via
    ///     `presentStreakModalIfNeeded(...)` so this never lands at zero in
    ///     production.
    ///   - savedAmount: Money the user did not lose. Pass `nil` (the default)
    ///     to let the modal derive it from the user's alarms via
    ///     `estimatedSavings(for:alarms:)` — that's what the alarms-list
    ///     milestone path does, so its number matches the streak banner.
    init(streakDays: Int, savedAmount: Decimal? = nil) {
        self.streakDays = streakDays
        self.savedAmountOverride = savedAmount
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
        capsLabel.attributedText = NSAttributedString(
            string: Self.streakCaption(for: streakDays),
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
        // No `adjustsFontSizeToFitWidth` here: `applyGradientMask` rasterises
        // the mask with the label's nominal font, so an auto-shrunk label would
        // render a mask larger than the glyphs it is supposed to clip.
        amountLabel.numberOfLines = 1
        amountLabel.textColor = AppColors.money400   // safety-net pre-mask
        amountLabel.text = Self.formatSavedAmount(resolvedSavings)
        amountLabel.translatesAutoresizingMaskIntoConstraints = false

        amountGradient.colors = SPSupport.moneyGradientColors
        amountGradient.locations = SPSupport.moneyGradientLocations
        amountGradient.startPoint = SPSupport.gradientStart
        amountGradient.endPoint = SPSupport.gradientEnd

        headlineLabel.text = Self.savingsHeadline(for: streakDays)
        headlineLabel.font = AppTypography.h3
        headlineLabel.textColor = AppColors.fg1
        headlineLabel.textAlignment = .center
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        // Design copy read "Деньги вернули на баланс" — but nothing was ever
        // charged, so there is nothing to return. Same promise, honest wording.
        bodyLabel.text = "Эти деньги остались у вас на балансе. "
            + "Потратьте их на следующей слабой неделе."
        bodyLabel.font = AppTypography.body
        bodyLabel.textColor = AppColors.fg3
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureButtons() {
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
    }

    private func layout() {
        let buttonsStack = UIStackView(arrangedSubviews: [shareButton, closeButton])
        buttonsStack.axis = .vertical
        buttonsStack.alignment = .fill
        buttonsStack.spacing = AppSpacing.sp2
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [
            flameBadge,
            capsLabel,
            amountLabel,
            headlineLabel,
            bodyLabel,
            pipStrip,
            buttonsStack
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        stack.setCustomSpacing(AppSpacing.sp5, after: flameBadge)
        stack.setCustomSpacing(AppSpacing.sp2, after: capsLabel)
        stack.setCustomSpacing(AppSpacing.sp1, after: amountLabel)
        stack.setCustomSpacing(AppSpacing.sp2, after: headlineLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: bodyLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: pipStrip)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(stack)

        NSLayoutConstraint.activate([
            // Sheet anchored to the bottom with screen-inset margins (16 — #289).
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp4),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp4),
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
            buttonsStack.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            buttonsStack.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            // Pip row stretches but the strip itself centres inside.
            pipStrip.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            pipStrip.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            // Caption / hero / body stretch full-width so multi-line centres.
            capsLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            capsLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            amountLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            amountLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
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
        let activity = UIActivityViewController(
            activityItems: [Self.shareText(streakDays: streakDays, savedAmount: resolvedSavings)],
            applicationActivities: nil
        )
        // iPad popover anchor — the system picker insists on a source view.
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        present(activity, animated: true)
    }

    // MARK: - Copy helpers

    /// Caps caption above the money hero, e.g.
    /// `"СЕРИЯ · 7 ДНЕЙ БЕЗ ОТКЛАДЫВАНИЙ"`.
    static func streakCaption(for streakDays: Int) -> String {
        "СЕРИЯ · \(streakDays) \(dayWord(for: streakDays).uppercased()) БЕЗ ОТКЛАДЫВАНИЙ"
    }

    /// h3 line under the hero. The design artboard shows the 7-day case
    /// ("Сэкономили за неделю"); other streak lengths spell the day count out
    /// so the sentence stays true (a 3-day streak did not save "за неделю").
    static func savingsHeadline(for streakDays: Int) -> String {
        streakDays == 7
            ? "Сэкономили за неделю"
            : "Сэкономили за \(streakDays) \(dayWord(for: streakDays))"
    }

    /// Format the saved amount as `+1 234 ₽` with the brand thousand separator.
    static func formatSavedAmount(_ amount: Decimal) -> String {
        "+\(amount.formattedRubles())"
    }

    /// Text handed to `UIActivityViewController` by "Поделиться победой".
    /// Wording fixed by PM on 2026-07-30 (#347).
    static func shareText(streakDays: Int, savedAmount: Decimal) -> String {
        "Я не откладываю будильник \(streakDays) \(dayWord(for: streakDays)) "
            + "и сэкономил \(savedAmount.formattedRubles()) — SnoozePay"
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

    // MARK: - Savings math

    /// Default rouble-per-day estimate when callers can't compute the exact
    /// "would-have-paid" amount. 50 ₽ matches the default `Alarm.penaltyAmount`
    /// so the approximation tracks the average user.
    private static let defaultDailyPenalty: Decimal = 50

    /// Money the user did **not** spend across `streakDays` snooze-free days.
    ///
    /// Formula: `average(alarm.penaltyAmount) × streakDays`, falling back to
    /// 50 ₽/day when the user has no alarms at all.
    ///
    /// Rationale — a streak day (per `StreakCalculator`) is a day the user woke
    /// on the alarm and was **not** charged. Had they snoozed instead, the
    /// ledger would carry one `.charge` at that alarm's `penaltyAmount`, so
    /// "one avoided snooze per streak day, priced at what the user's alarms
    /// actually cost" is the honest lower bound: it never claims credit for a
    /// day outside the streak, and it under-counts rather than over-counts
    /// users who would have snoozed twice. The ledger cannot supply an exact
    /// figure — a snooze that never happened leaves no row — so an estimate is
    /// unavoidable; the design's own artboard (7 days → +350 ₽) is exactly this
    /// formula at the default price.
    ///
    /// Deliberately the single savings implementation in the app: the
    /// alarms-list streak banner (`AlarmsStreakBannerView`) and the Statistics
    /// hero both call it, so no two surfaces can quote different numbers.
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
