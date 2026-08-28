import os
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
/// ## Two modes, and why
///
/// The money figure is an estimate the app *broadcasts* — it goes on screen and
/// into a social share. So it renders only when it is defensible:
/// `Mode.savings` needs a positive streak **and** a positive amount the caller
/// actually computed from real alarms. Everything else (streak ≤ 0, savings ≤ 0,
/// or a caller that couldn't read the alarms at all) degrades to
/// `Mode.behavioral` — the V3 sheet, no number, no share button. A wrong rouble
/// figure is worse than no rouble figure.
///
/// Visual recipe (`.savings`):
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
/// - h3 "Сэкономили за неделю" in `fg1`, then supporting body in `fg3`.
/// - 7 day-pip row (`SPStreakPipStrip`).
/// - `SPButton(.money, .lg)` "Поделиться победой" → `UIActivityViewController`,
///   plus a `SPButton(.quiet, .md)` "Закрыть".
///
/// `.behavioral` drops the hero + share button and restores the V3 copy
/// ("СЕРИЯ" / "N дней без откладываний" / habit line).
final class StreakModalViewController: UIViewController {

    // MARK: - Mode

    /// What the sheet is allowed to claim.
    enum Mode: Equatable {
        /// Positive, caller-computed savings — money hero + share CTA.
        case savings(Decimal)
        /// No trustworthy figure — V3 behavioral sheet, no money, no share.
        case behavioral
    }

    // MARK: - Configuration

    /// Number of consecutive snooze-free days. Drives the caption + the
    /// completed-square count in the 7-day visualizer.
    private let streakDays: Int

    private let mode: Mode

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
    /// Money hero. `SPGradientTextLabel` re-masks itself from its own
    /// `layoutSubviews` — driving that from the controller's
    /// `viewDidLayoutSubviews` never worked, because the label (sheet → stack →
    /// label) still measures zero when the controller's callback fires (#347
    /// review).
    private let amountLabel = SPGradientTextLabel(
        colors: SPSupport.moneyGradientColors,
        locations: SPSupport.moneyGradientLocations,
        startPoint: SPSupport.gradientStart,
        endPoint: SPSupport.gradientEnd
    )
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()

    private lazy var pipStrip = SPStreakPipStrip(completed: streakDays)

    private let shareButton = SPButton(
        title: "Поделиться победой",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    private lazy var closeButton = SPButton(
        title: "Закрыть",
        // With a share CTA above it the close button is secondary; alone it is
        // the only action, so it keeps the V3 money treatment.
        variant: mode == .behavioral ? .money : .quiet,
        size: mode == .behavioral ? .lg : .md,
        fullWidth: true
    )

    // MARK: - Init

    /// - Parameters:
    ///   - streakDays: Consecutive snooze-free days.
    ///   - savedAmount: Money the user did not lose, computed by the caller
    ///     from its checked alarm-price snapshot (`SavingsEstimate`).
    ///     Pass `nil` when there is no trustworthy figure — a corrupted alarm
    ///     store, no priced alarms, a zero-price alarm — and the sheet falls
    ///     back to the behavioral celebration instead of inventing a number.
    ///     The modal deliberately does **not** read the repository itself: the
    ///     `try?`-swallowed read it did before review turned a corrupted
    ///     `saved_alarms` blob into a confident, shareable "+350 ₽".
    init(streakDays: Int, savedAmount: Decimal?) {
        self.streakDays = streakDays
        self.mode = Self.mode(streakDays: streakDays, savedAmount: savedAmount)
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
        // NB: the money hero is deliberately absent here — `SPGradientTextLabel`
        // owns its own mask timing. This callback runs before the label has a
        // resolved size, so masking from here is a no-op.
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
        let copy = Self.copy(streakDays: streakDays, mode: mode)

        capsLabel.attributedText = NSAttributedString(
            string: copy.caps,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.money300
            ]
        )
        capsLabel.textAlignment = .center
        capsLabel.numberOfLines = 0
        capsLabel.translatesAutoresizingMaskIntoConstraints = false

        if case .savings(let amount) = mode {
            configureAmountLabel(amount)
        }

        headlineLabel.text = copy.headline
        headlineLabel.font = mode == .behavioral ? AppTypography.h1 : AppTypography.h3
        headlineLabel.textColor = AppColors.fg1
        headlineLabel.textAlignment = .center
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.text = copy.body
        bodyLabel.font = AppTypography.body
        bodyLabel.textColor = AppColors.fg3
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureAmountLabel(_ amount: Decimal) {
        amountLabel.font = AppTypography.moneyXl
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontForContentSizeCategory = false
        // Long figures shrink instead of clipping — a truncated amount reads as
        // a different (wrong) number. `applyGradientMask` mirrors both settings
        // when it rasterises the mask, and honours `.center` (#347 review).
        amountLabel.numberOfLines = 1
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5
        // Flat fallback in case the mask can't rasterise (zero-width label on a
        // pathological layout) — the number stays readable, just untinted.
        amountLabel.textColor = AppColors.money400
        amountLabel.text = Self.formatSavedAmount(amount)
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureButtons() {
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
    }

    private func layout() {
        let showsMoney = mode != .behavioral

        let buttonsStack = UIStackView(
            arrangedSubviews: showsMoney ? [shareButton, closeButton] : [closeButton]
        )
        buttonsStack.axis = .vertical
        buttonsStack.alignment = .fill
        buttonsStack.spacing = AppSpacing.sp2
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        var arranged: [UIView] = [flameBadge, capsLabel]
        if showsMoney { arranged.append(amountLabel) }
        arranged.append(contentsOf: [headlineLabel, bodyLabel, pipStrip, buttonsStack])

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        stack.setCustomSpacing(AppSpacing.sp5, after: flameBadge)
        stack.setCustomSpacing(AppSpacing.sp2, after: capsLabel)
        if showsMoney { stack.setCustomSpacing(AppSpacing.sp1, after: amountLabel) }
        stack.setCustomSpacing(AppSpacing.sp2, after: headlineLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: bodyLabel)
        stack.setCustomSpacing(AppSpacing.sp6, after: pipStrip)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
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
            pipStrip.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ]
        // Caption / hero / headline / body stretch full-width so the centred
        // text alignment has the whole sheet to centre in.
        let fullWidthLabels = [capsLabel, headlineLabel, bodyLabel] + (showsMoney ? [amountLabel] : [])
        for label in fullWidthLabels {
            constraints.append(label.leadingAnchor.constraint(equalTo: stack.leadingAnchor))
            constraints.append(label.trailingAnchor.constraint(equalTo: stack.trailingAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        guard case .savings(let amount) = mode else { return }
        // A double tap would otherwise present on top of the in-flight share
        // sheet, which UIKit refuses — and the second tap reads to the user as
        // "the button is broken" (#347 review).
        guard presentedViewController == nil else { return }

        let activity = UIActivityViewController(
            activityItems: [Self.shareText(streakDays: streakDays, savedAmount: amount)],
            applicationActivities: nil
        )
        activity.completionWithItemsHandler = { activityType, completed, _, error in
            let channel = activityType?.rawValue ?? "unknown"
            if let error {
                let reason = error.localizedDescription
                AppLogger.ui.error(
                    "streak share failed via \(channel, privacy: .public): \(reason, privacy: .public)"
                )
            } else {
                let outcome = completed ? "completed" : "cancelled"
                AppLogger.ui.info(
                    "streak share via \(channel, privacy: .public) \(outcome, privacy: .public)"
                )
            }
        }
        // iPad popover anchor — the system picker insists on a source view.
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        present(activity, animated: true)
    }
}

// MARK: - Copy + savings math

/// Kept in an extension so the statics stay unit-testable without inflating the
/// view controller's body past the SwiftLint type-body cap.
extension StreakModalViewController {

    /// The strings the sheet renders, per mode.
    struct Copy: Equatable {
        let caps: String
        let headline: String
        let body: String
    }

    /// Decide what the sheet may claim. Money needs *both* a real streak and a
    /// positive, caller-computed amount:
    /// - `streakDays <= 0` — nothing was earned. (Statistics currently opens the
    ///   sheet with `max(streak, 1)`, which would otherwise mint 50 ₽ out of a
    ///   zero — or unreadable — streak; that call site needs its own fix,
    ///   tracked with #348.)
    /// - `savedAmount == nil` — the caller had no trustworthy figure.
    /// - `savedAmount <= 0` — a 0 ₽ alarm price is legal (`Alarm.swift`), and
    ///   "+0 ₽ / Сэкономили за неделю / Поделиться победой" is a joke at the
    ///   user's expense.
    static func mode(streakDays: Int, savedAmount: Decimal?) -> Mode {
        guard streakDays > 0, let savedAmount, savedAmount > 0 else { return .behavioral }
        return .savings(savedAmount)
    }

    static func copy(streakDays: Int, mode: Mode) -> Copy {
        switch mode {
        case .savings:
            return Copy(
                caps: streakCaption(for: streakDays),
                headline: savingsHeadline(for: streakDays),
                // The design read "Деньги вернули на баланс" — but nothing was
                // ever charged, so there is nothing to return. Same promise,
                // honest wording.
                body: "Эти деньги остались у вас на балансе. "
                    + "Потратьте их на следующей слабой неделе."
            )
        case .behavioral:
            return Copy(
                caps: "СЕРИЯ",
                headline: "\(streakDays) \(dayWord(for: streakDays)) без откладываний",
                body: "Это уже не случайность — это привычка. "
                    + "Тело знает, что подъём вовремя — это просто."
            )
        }
    }

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

    /// Money the user did **not** spend across `streakDays` snooze-free days,
    /// or `nil` when no defensible figure exists.
    ///
    /// Formula: `average(alarm.penaltyAmount) × streakDays`, over the alarms
    /// the caller has already loaded and error-handled.
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
    /// formula over one default-priced 50 ₽ alarm.
    ///
    /// Returns `nil` — never a stand-in number — when the inputs can't support
    /// the claim: non-positive streak, no alarms, no *parsable* alarm price, or
    /// a zero total (0 ₽ alarms are legal). The pre-review version answered
    /// "50 ₽/day" in those cases, which is how an unreadable alarm store became
    /// a confident, shareable "+350 ₽".
    ///
}
