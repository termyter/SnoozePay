import UIKit

/// Money + wake-time aggregations of the statistics screen (#348,
/// `SPMore4.jsx` `Stats()`, artboard `27-stats`).
///
/// Split out of `StatisticsViewModel.swift` so the main type body stays under
/// SwiftLint's `type_body_length` ceiling — the same treatment
/// `StatisticsViewController+Cards.swift` gives the view controller. Nothing
/// here touches the behavioural aggregations.
///
/// `SavingsEstimate` is the **canonical** savings formula for the whole app
/// (PM decision, 2026-07-30): the streak banner on the alarms tab and the
/// streak modal currently divide by a different alarm pool and disagree with
/// this screen by up to 2×. They move onto this entry point in #347.
extension StatisticsViewModel {

    // MARK: - Data-health states

    /// Why the money card can't publish figures.
    ///
    /// Both cases keep the card on screen with an explanation. Hiding it
    /// instead would swap "lies with numbers" for "disappears without a
    /// word" — and the states worth noticing (version skew, byte damage to a
    /// `type` string, a half-finished migration) are exactly the ones that
    /// would vanish (#348 verification, finding 3).
    enum MoneyUnavailableReason: Equatable {
        /// The ledger threw on decode. `onLoadError` has already fired, so the
        /// user is seeing an alert too — this is the in-card echo of it.
        case ledgerUnreadable
        /// The ledger decoded, but rows carry `type` tokens this build can't
        /// classify (#453). Nothing throws on this path, so without this state
        /// the failure would be entirely invisible.
        case ledgerPartiallyRead

        /// In-card copy replacing the totals.
        var message: String {
            switch self {
            case .ledgerUnreadable:
                return "Не удалось прочитать историю списаний — данные за неделю скрыты"
            case .ledgerPartiallyRead:
                return "История списаний прочитана не полностью — данные за неделю скрыты, "
                     + "чтобы не показать заниженные суммы"
            }
        }
    }

    /// Log identifier for the silent partial-read path, so a support ticket
    /// can be grepped straight to the branch that suppressed the card.
    static var partialLedgerErrorID: String { "STATS-348-LEDGER-PARTIAL" }
    /// Log identifier for an unreadable alarm store.
    static var alarmStoreErrorID: String { "STATS-348-ALARMS-UNREADABLE" }

    /// Outcome of resolving the snooze price.
    enum SnoozePriceState: Equatable {
        /// A real price — including a legitimate 0 ₽ when every alarm is free.
        case known(Double)
        /// No alarm exists to price a morning with.
        case noPricedAlarms
        /// `stored_alarms` failed to decode; the user's alarms may well be
        /// priced, we just can't read them.
        case alarmStoreUnreadable

        var price: Double? {
            if case .known(let price) = self { return price }
            return nil
        }

        /// Caption explaining a "—" in the savings column, or `nil` when a
        /// price exists and no explanation is owed.
        var explanation: String? {
            switch self {
            case .known:
                return nil
            case .noPricedAlarms:
                return "Сэкономленное появится, когда у будильника будет цена снуза"
            case .alarmStoreUnreadable:
                return "Не удалось прочитать будильники — сэкономленное не посчитать"
            }
        }
    }

    /// Caption under the totals row, or `nil` when the numbers speak for
    /// themselves.
    ///
    /// Covers both ways a zero can mislead: a "—" that needs a reason, and a
    /// genuine `Сэкономили 0 ₽` on a week of clean mornings under free alarms,
    /// which otherwise reads as a broken screen (#348 verification, finding 5).
    var savingsNote: String? {
        guard !weekMoneySummary.isEmpty else { return nil }
        if weekMoneySummary.savingsUnavailable {
            return snoozePriceState.explanation
        }
        if case .known(let price) = snoozePriceState,
           price == 0,
           weekMoneyDays.contains(where: \.isCleanWake) {
            return "Снуз на ваших будильниках бесплатный — экономить нечего"
        }
        return nil
    }

    // MARK: - Canonical savings formula (shared entry point)

    /// The one place that answers "what is a clean morning worth, and what
    /// did N of them save?".
    ///
    /// Kept as a standalone namespace rather than free functions on the view
    /// model so non-statistics callers (`StreakModalViewController`,
    /// `AlarmsStreakBannerView`) can adopt it without importing a screen's
    /// view model semantics.
    enum SavingsEstimate {

        /// Price of a single snooze: the arithmetic mean of `penaltyAmount`
        /// across **enabled** alarms.
        ///
        /// - A disabled alarm's penalty is not a price the user is currently
        ///   exposed to, so it only enters the mean when every alarm is off
        ///   (an approximate price beats none).
        /// - Free alarms (`penaltyAmount == 0`) **are** included. Skipping
        ///   them used to value a clean morning under a 0 ₽ alarm at the
        ///   price of the user's *other* alarm, whose counterfactual is
        ///   exactly zero (#348 review, finding 4).
        /// - `nil` — not `0` — when there is no alarm to price at all, or
        ///   when the alarm store can't be read. Callers must render that as
        ///   "unknown", never as "you saved nothing".
        static func snoozePrice(alarms: [Alarm]) -> Double? {
            let enabled = alarms.filter(\.enabled)
            let pool = enabled.isEmpty ? alarms : enabled
            let prices = pool.map(\.penaltyAmount).filter { $0.isFinite && $0 >= 0 }
            guard !prices.isEmpty else { return nil }
            return prices.reduce(0, +) / Double(prices.count)
        }

        /// Roubles kept by `cleanDays` mornings that cost nothing.
        /// `nil` propagates an unknown price rather than collapsing to 0.
        static func saved(cleanDays: Int, alarms: [Alarm]) -> Double? {
            guard let price = snoozePrice(alarms: alarms) else { return nil }
            return saved(cleanDays: cleanDays, price: price)
        }

        /// Price-injected variant for callers that already resolved a price.
        static func saved(cleanDays: Int, price: Double) -> Double {
            Double(max(0, cleanDays)) * price
        }

        /// UI-facing variant of the canonical formula. A zero result is not a
        /// savings figure worth showing in a streak celebration, and `nil`
        /// also preserves the distinction between an unknown price and 0 ₽.
        static func savedDisplayAmount(cleanDays: Int, alarms: [Alarm]) -> Decimal? {
            guard let saved = saved(cleanDays: cleanDays, alarms: alarms) else { return nil }
            return displayAmount(from: saved)
        }

        /// Price-injected display variant for callers that already hold a
        /// checked alarm-price snapshot.
        static func savedDisplayAmount(cleanDays: Int, price: Double?) -> Decimal? {
            guard let price else { return nil }
            return displayAmount(from: saved(cleanDays: cleanDays, price: price))
        }

        private static func displayAmount(from saved: Double) -> Decimal? {
            guard saved.isFinite, saved > 0 else { return nil }
            // Keep the UI's Decimal amount free of binary Double artefacts
            // (50.0 must not become 49.999… before MoneyFormatter truncates).
            return Decimal(string: String(format: "%.2f", saved))
        }
    }

    /// Convenience forwarder kept so existing call sites and tests read
    /// naturally; the formula itself lives in `SavingsEstimate`.
    static func snoozePrice(alarms: [Alarm]) -> Double? {
        SavingsEstimate.snoozePrice(alarms: alarms)
    }

    // MARK: - "Эта неделя" money summary

    /// One column of the "ЭТА НЕДЕЛЯ" money chart — a green "saved" stack and
    /// a red "lost" stack, exactly like `SPMore4.jsx` `Stats()`.
    struct WeekMoneyDay: Equatable {
        /// Short weekday label — "Пн" … "Вс".
        let label: String
        /// Counterfactual roubles kept by not snoozing that morning. `nil`
        /// when the snooze price is unknown — the day is still clean, we just
        /// can't put a number on it.
        let saved: Double?
        /// Penalty roubles actually charged that day.
        let spent: Double
        /// `true` when the user demonstrably got up that day without paying
        /// and without even attempting a snooze. Tracked separately from
        /// `saved` so a clean day still counts as an observation when the
        /// price is unknown (#348 review, finding 4).
        let isCleanWake: Bool
        /// `false` for days of the current week that haven't happened yet —
        /// those render as an empty column instead of a misleading zero.
        let isPastOrToday: Bool

        /// Height contribution of the green stack; 0 while the price is
        /// unknown, since an unpriced day has no bar to draw.
        var savedHeightValue: Double { saved ?? 0 }
    }

    /// The three money totals under the week chart: "Сэкономили / Потратили /
    /// Чистый".
    struct MoneySummary: Equatable {
        /// `nil` when the snooze price is unknown — rendered as "—".
        let saved: Double?
        let spent: Double
        /// Past days of the week that carried *any* evidence: a wake event or
        /// a charge. Drives the empty state, so a week of confirmed wakes
        /// under free alarms no longer claims "данных пока нет"
        /// (#348 review, finding 4).
        let observedDays: Int

        static let empty = MoneySummary(saved: nil, spent: 0, observedDays: 0)

        /// `nil` whenever `saved` is — a net figure needs both halves.
        var net: Double? {
            guard let saved else { return nil }
            return saved - spent
        }

        /// `true` when the week recorded nothing at all to report.
        var isEmpty: Bool { observedDays == 0 }

        /// `true` when there is something to report but no honest price to
        /// report savings with.
        var savingsUnavailable: Bool { saved == nil && !isEmpty }
    }

    // MARK: - "Время подъёма"

    /// Figures behind the "ВРЕМЯ ПОДЪЁМА" card. Minutes are minutes-since-
    /// midnight so the view can format them without re-deriving dates.
    struct WakeTimeStats: Equatable {
        /// **Median** wake time over the recent window — `nil` until the
        /// window holds `minimumSamples` mornings.
        ///
        /// Median, not mean (PM decision, 2026-07-30): one 00:30 dismissal
        /// among thirteen 07:00 mornings drags a mean by ~28 minutes and
        /// turns the headline into an artefact of a single outlier.
        let medianMinutes: Int?
        /// Median of the window immediately before it — `nil` when that
        /// window is below `minimumSamples`, in which case the card drops the
        /// "Раньше было" / "Раньше на" columns instead of faking a baseline.
        let baselineMedianMinutes: Int?
        /// Mornings recorded in the recent window; surfaced so the card can
        /// say how many more are needed.
        let recentSampleCount: Int
        /// Mornings required per window before a figure is shown at all.
        let minimumSamples: Int

        /// `baseline − median`; positive = the user now gets up *earlier*.
        var deltaMinutes: Int? {
            guard let median = medianMinutes, let baseline = baselineMedianMinutes else {
                return nil
            }
            return baseline - median
        }

        /// Mornings still missing before the median can be shown.
        var samplesUntilReady: Int { max(0, minimumSamples - recentSampleCount) }
    }

    // MARK: - Pure aggregation — money

    /// Calendar days carrying at least one `.charge` row, refunded or not.
    ///
    /// A refunded charge means the user *pressed snooze* and the scheduler
    /// refused (#130). `realCharges` rightly drops it from spend and from the
    /// snooze count — the alarm never re-rang — but treating that morning as
    /// "saved" would tell the user they resisted when they didn't
    /// (#348 review, finding 3).
    static func attemptedSnoozeDays(
        from transactions: [Transaction],
        calendar: Calendar
    ) -> Set<Date> {
        Set(
            transactions
                .filter { $0.type == .charge }
                .map { calendar.startOfDay(for: $0.createdAt) }
        )
    }

    /// Everything the money chart needs out of persistence, captured once so
    /// the bars and the totals provably share one snapshot.
    struct MoneyInputs {
        /// Real (non-refunded) charges — already `realCharges`-filtered.
        let charges: [Transaction]
        let wakeDays: Set<Date>
        let attemptedSnoozeDays: Set<Date>
        /// `nil` when no honest snooze price exists.
        let snoozePrice: Double?

        init(
            charges: [Transaction] = [],
            wakeDays: Set<Date> = [],
            attemptedSnoozeDays: Set<Date> = [],
            snoozePrice: Double? = nil
        ) {
            self.charges = charges
            self.wakeDays = wakeDays
            self.attemptedSnoozeDays = attemptedSnoozeDays
            self.snoozePrice = snoozePrice
        }
    }

    /// Seven Monday-first columns of the current week's money chart.
    ///
    /// - **Потратили** (`spent`) — factual: the penalty roubles charged that
    ///   day. Derived from `snoozesByDay`, which only ever sums `.charge`
    ///   rows out of the already refund-filtered `charges` list, so neither
    ///   `.refund` nor any future transaction kind can leak into the total.
    /// - **Сэкономили** (`saved`) — counterfactual: a morning is worth one
    ///   snooze price when the user was demonstrably woken (a wake event
    ///   exists), paid nothing, **and** never even attempted a snooze. Days
    ///   without a wake event contribute nothing — we can't claim savings on
    ///   a day we have no evidence an alarm rang.
    /// - Future days of the current week are marked `isPastOrToday == false`
    ///   and contribute nothing, so Wednesday's chart doesn't imply the user
    ///   already saved money on Saturday.
    static func weekMoneyDays(
        today: Date,
        inputs: MoneyInputs,
        calendar: Calendar
    ) -> [WeekMoneyDay] {
        let charges = inputs.charges
        let wakeDays = inputs.wakeDays
        let attemptedSnoozeDays = inputs.attemptedSnoozeDays
        let snoozePrice = inputs.snoozePrice
        let todayStart = calendar.startOfDay(for: today)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: todayStart) else { return [] }
        let byDay = snoozesByDay(charges: charges, calendar: calendar)
        return weekdayShortLabels.indices.map { offset in
            let label = weekdayShortLabels[offset]
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: week.start),
                calendar.startOfDay(for: day) <= todayStart
            else {
                return WeekMoneyDay(
                    label: label, saved: nil, spent: 0, isCleanWake: false, isPastOrToday: false
                )
            }
            let dayStart = calendar.startOfDay(for: day)
            let data = byDay[dayStart] ?? (count: 0, spent: 0)
            let isClean = data.count == 0
                && !attemptedSnoozeDays.contains(dayStart)
                && wakeDays.contains(dayStart)
            return WeekMoneyDay(
                label: label,
                saved: isClean ? snoozePrice : nil,
                spent: data.spent,
                isCleanWake: isClean,
                isPastOrToday: true
            )
        }
    }

    /// Totals of the week columns — "Чистый" falls out of `saved − spent`
    /// and is free to go negative on a bad week. `saved` stays `nil` while
    /// the week holds clean mornings we have no price for.
    static func moneySummary(days: [WeekMoneyDay]) -> MoneySummary {
        let past = days.filter(\.isPastOrToday)
        let cleanDays = past.filter(\.isCleanWake)
        let pricedSavings = cleanDays.compactMap(\.saved)
        // Either every clean day is priced or none is — the price is a single
        // screen-wide figure — so a partial map means "unknown".
        let saved = cleanDays.isEmpty
            ? (past.isEmpty ? nil : 0)
            : (pricedSavings.count == cleanDays.count ? pricedSavings.reduce(0, +) : nil)
        let spent = past.reduce(0) { $0 + $1.spent }
        let observedDays = past.filter { $0.isCleanWake || $0.spent > 0 }.count
        return MoneySummary(saved: saved, spent: spent, observedDays: observedDays)
    }

    // MARK: - Pure aggregation — wake time

    /// Span of each half of the wake-time comparison. Two weeks is long
    /// enough to absorb a single overslept morning yet short enough that
    /// "раньше было" still describes recent behaviour.
    static var wakeTimeWindowDays: Int { 14 }

    /// Mornings required in a window before its median is shown at all
    /// (PM decision, 2026-07-30). Below five, a "median" is a coin flip
    /// between two mornings and the headline moves on noise.
    static var wakeTimeMinimumSamples: Int { 5 }

    /// Minutes since local midnight.
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Earliest recorded wake instant per calendar day. `WakeEventStore`
    /// already dedupes on write, but a legacy blob (or a test fixture) can
    /// hold several instants for one day, and the *first* dismissal is the
    /// actual подъём.
    static func firstWakePerDay(times: [Date], calendar: Calendar) -> [Date: Date] {
        var result: [Date: Date] = [:]
        for time in times {
            let day = calendar.startOfDay(for: time)
            if let existing = result[day], existing <= time { continue }
            result[day] = time
        }
        return result
    }

    /// Median minute-of-day, or `nil` below `minimumSamples`.
    ///
    /// Even sample counts average the two middle values, matching the usual
    /// definition. Deliberately not a circular median: wake times cluster in
    /// the morning, so the midnight wrap a circular statistic guards against
    /// can't realistically dominate, and a plain median stays explainable.
    static func medianMinuteOfDay(
        _ times: [Date],
        calendar: Calendar,
        minimumSamples: Int = 1
    ) -> Int? {
        guard times.count >= max(1, minimumSamples) else { return nil }
        let minutes = times.map { minuteOfDay($0, calendar: calendar) }.sorted()
        let middle = minutes.count / 2
        if minutes.count % 2 == 1 { return minutes[middle] }
        return Int((Double(minutes[middle - 1] + minutes[middle]) / 2).rounded())
    }

    /// Typical wake time over the trailing `windowDays`, compared with the
    /// `windowDays` before that.
    ///
    /// Returns `nil` only when the recent window holds **no** wake instants
    /// at all — including every install that only ever wrote the legacy
    /// day-granular history, for which the card is omitted entirely. With
    /// between one and `minimumSamples − 1` mornings the struct comes back
    /// with a `nil` median so the card can say it's still accumulating,
    /// rather than publishing a "typical" time built from one morning.
    static func wakeTimeStats(
        today: Date,
        wakeTimes: [Date],
        calendar: Calendar,
        windowDays: Int = StatisticsViewModel.wakeTimeWindowDays,
        minimumSamples: Int = StatisticsViewModel.wakeTimeMinimumSamples
    ) -> WakeTimeStats? {
        let todayStart = calendar.startOfDay(for: today)
        guard
            windowDays > 0,
            let recentStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: todayStart),
            let baselineStart = calendar.date(byAdding: .day, value: -windowDays, to: recentStart)
        else { return nil }
        let firstWakes = firstWakePerDay(times: wakeTimes, calendar: calendar)
        let recent = firstWakes.filter { $0.key >= recentStart && $0.key <= todayStart }.map(\.value)
        guard !recent.isEmpty else { return nil }
        let baseline = firstWakes.filter { $0.key >= baselineStart && $0.key < recentStart }.map(\.value)
        return WakeTimeStats(
            medianMinutes: medianMinuteOfDay(
                recent, calendar: calendar, minimumSamples: minimumSamples
            ),
            baselineMedianMinutes: medianMinuteOfDay(
                baseline, calendar: calendar, minimumSamples: minimumSamples
            ),
            recentSampleCount: recent.count,
            minimumSamples: minimumSamples
        )
    }

    // MARK: - Presentation strings

    /// "7:04" — minutes-since-midnight rendered as a wall clock.
    static func clockText(minutes: Int) -> String {
        let normalised = max(0, minutes)
        return String(format: "%d:%02d", normalised / 60, normalised % 60)
    }

    /// Caption above the third wake-time column.
    static func wakeDeltaCaption(minutes: Int) -> String {
        if minutes > 0 { return "Раньше на" }
        if minutes < 0 { return "Позже на" }
        return "Без изменений"
    }

    /// "34 мин" — the delta magnitude; a flat comparison shows an em dash.
    static func wakeDeltaValueText(minutes: Int) -> String {
        minutes == 0 ? "—" : "\(abs(minutes)) мин"
    }

    /// "Нужно ещё 3 утра" — copy for a window below `minimumSamples`.
    static func wakeSamplesPendingText(_ missing: Int) -> String {
        "Копим историю: нужно ещё \(missing) \(morningWord(missing))"
    }

    /// "1 утро / 2 утра / 5 утр".
    static func morningWord(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 { return "утр" }
        switch mod10 {
        case 1: return "утро"
        case 2, 3, 4: return "утра"
        default: return "утр"
        }
    }

    /// Plain-text signed money — "+800 ₽" / "−400 ₽" / "0 ₽", with the
    /// typographic minus (U+2212) the design copy uses.
    ///
    /// Kept alongside `signedMoneyAttributed` because VoiceOver reads
    /// `accessibilityLabel`, not attributed runs; the two must agree, so they
    /// share `MoneyFormatter` and this sign logic.
    static func signedMoneyText(_ amount: Double?) -> String {
        guard let amount else { return "—" }
        let rounded = amount.rounded()
        guard rounded != 0 else { return MoneyFormatter.string(Decimal(0)) }
        return "\(moneySign(rounded))\(MoneyFormatter.string(Decimal(abs(rounded))))"
    }

    /// Mono-font variant of `signedMoneyText`.
    ///
    /// Money labels render in JetBrains Mono, where U+0020 takes a full
    /// ~0.6em cell and turns "800 ₽" into "800  ₽". `MoneyFormatter.attributed`
    /// re-fonts just the separator with the proportional sans — the same fix
    /// the wallet history rows use (#348 review, finding 2).
    static func signedMoneyAttributed(
        _ amount: Double?,
        digitsFont: UIFont,
        color: UIColor
    ) -> NSAttributedString {
        guard let amount else {
            return NSAttributedString(
                string: "—", attributes: [.font: digitsFont, .foregroundColor: color]
            )
        }
        let rounded = amount.rounded()
        return MoneyFormatter.attributed(
            Decimal(abs(rounded)),
            digitsFont: digitsFont,
            prefix: rounded == 0 ? "" : moneySign(rounded),
            color: color
        )
    }

    /// "+" / "−" (U+2212). Zero carries no sign.
    static func moneySign(_ amount: Double) -> String {
        if amount < 0 { return "−" }
        if amount > 0 { return "+" }
        return ""
    }
}
