import os
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

    /// Why the ledger-derived statistics screen can't publish figures.
    ///
    /// Both cases replace the ledger-dependent content with the statistics
    /// state column and an explanation. Hiding only individual cards would
    /// swap "lies with numbers" for "disappears without a word" — and the
    /// states worth noticing (version skew, byte damage to a `type` string, a
    /// half-finished migration) are exactly the ones that would vanish (#348
    /// verification, finding 3; #459).
    enum LedgerUnavailableReason: Equatable {
        /// The ledger threw on decode. `onLoadError` has already fired, so the
        /// user is seeing an alert too — the state column echoes the failure.
        case ledgerUnreadable
        /// The ledger decoded, but rows carry `type` tokens this build can't
        /// classify (#453). Nothing throws on this path, so without this state
        /// the failure would be entirely invisible.
        case ledgerPartiallyRead

        /// State-column copy explaining why ledger-derived content is hidden.
        var message: String {
            switch self {
            case .ledgerUnreadable:
                return Localized.text("statistics.ledger_unavailable.unreadable")
            case .ledgerPartiallyRead:
                // One catalogue entry rather than the two concatenated halves
                // this replaces: a sentence split across `+` freezes Russian
                // word order into every future translation (`Localized`).
                return Localized.text("statistics.ledger_unavailable.partial")
            }
        }
    }

    /// Log identifier for the silent partial-read path, so a support ticket
    /// can be grepped straight to the branch that suppressed the card.
    static var partialLedgerErrorID: String { "STATS-348-LEDGER-PARTIAL" }
    /// Log identifier for an unreadable alarm store.
    static var alarmStoreErrorID: String { "STATS-348-ALARMS-UNREADABLE" }
    /// Log identifier for a ledger that threw a `RepositoryError` on decode.
    ///
    /// The user gets an alert on this path — but only if the VC had already
    /// bound, and only if no other alert is up. An alert is therefore not a
    /// record that anything happened; this line is the record (#721).
    static var ledgerUnreadableErrorID: String { "STATS-721-LEDGER-UNREADABLE" }
    /// Log identifier for the load-failure alert actually reaching the user.
    static var alertShownErrorID: String { "STATS-721-ALERT-SHOWN" }
    /// Log identifier for a load-failure alert the screen could not show
    /// because something else was already presented. Distinct from
    /// `alertShownErrorID` so "the user was warned" and "the warning was
    /// dropped" can be told apart in a sysdiagnose (#721).
    static var alertDroppedErrorID: String { "STATS-721-ALERT-DROPPED" }
    /// Log identifier for a ledger read that threw something other than
    /// `TransactionRepository.RepositoryError`.
    ///
    /// Kept apart from `ledgerUnreadableErrorID` because the two mean opposite
    /// things to whoever greps them: the first is a known, handled data state,
    /// the second is a throw from a path that was not supposed to have one —
    /// a new error type, a neighbouring call that started throwing, a
    /// cancellation. Merging the IDs would hide the surprising case inside the
    /// expected one.
    static var unexpectedLedgerErrorID: String { "STATS-721-LEDGER-UNEXPECTED" }
    /// Log identifier for a wake median the card refused as not-a-time-of-day.
    ///
    /// Hiding the card is the honest outcome for the reader, but it looks
    /// exactly like a fresh install with no history — so without this line a
    /// real aggregation defect leaves the product with no trace at all, and a
    /// support ticket has nothing to grep. That is the trade #657 makes: it
    /// replaces a bug that shouted a wrong number with one that says nothing,
    /// and the shouting has to move into the log.
    static var wakeMedianOutOfDayErrorID: String { "STATS-657-WAKE-MEDIAN-OUT-OF-DAY" }

    /// A ledger read that threw something the screen has no specific copy
    /// for, wrapped so it can still reach the user as an alert (#721).
    ///
    /// The description is the screen's generic load-failure sentence rather
    /// than the underlying error's: `errorDescription` is what the alert body
    /// shows, and a decoder's English `debugDescription` in a Russian alert
    /// tells the user nothing they can act on. The specifics belong in the
    /// log, where `underlying` is printed in full.
    struct UnexpectedLedgerFailure: LocalizedError {
        let underlying: Error

        var errorDescription: String? { Localized.text("statistics.error.message") }
    }

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
                return Localized.text("statistics.savings.no_price")
            case .alarmStoreUnreadable:
                return Localized.text("statistics.savings.alarms_unreadable")
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
            return Localized.text("statistics.savings.free_alarms")
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
        ///
        /// Non-`nil` values are always inside ``minuteOfDayRange`` — see the
        /// initialiser.
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
        /// `true` when a median WAS produced upstream and this type refused it.
        ///
        /// Kept because «no median» and «a median we threw away» are different
        /// facts that happen to share a `nil`. Without it a rejected value in a
        /// short window is indistinguishable from short history, and the card
        /// offers to keep counting mornings towards a figure it has already
        /// decided it will not print. Being stored also puts it in `Equatable`,
        /// so a refused 1500 no longer compares equal to an honest absence.
        let medianWasRefused: Bool

        /// Minutes-since-midnight a wall clock can actually show.
        static let minuteOfDayRange = 0...(24 * 60 - 1)

        /// Drops a "median" that is not a time of day (#657).
        ///
        /// ``WallClockFormatter/string(minutesSinceMidnight:style:locale:)``
        /// clamps its input, which is the right call *for a formatter*: 1500
        /// must render as neither "25:00" nor next-day "1:00". But the clamp
        /// is the wrong end of the pipe for a statistic — it turns an
        /// aggregation defect into "23:59", a perfectly plausible wake time
        /// that nobody will ever report, where "25:00" would have had someone
        /// filing an issue by lunchtime. A figure the card cannot vouch for is
        /// better absent than plausible, so it is rejected here and the
        /// columns that would have carried it drop out.
        ///
        /// Today's pipeline cannot produce such a value: ``minuteOfDay`` reads
        /// `Calendar` hour/minute components, which are 0…23 and 0…59. This
        /// guards the *contract*, so a future aggregation (a circular median,
        /// a merged window, a decoded blob) fails by visible omission rather
        /// than by looking fine.
        init(
            medianMinutes: Int?,
            baselineMedianMinutes: Int?,
            recentSampleCount: Int,
            minimumSamples: Int
        ) {
            let median = WakeTimeStats.timeOfDay(
                medianMinutes, field: "median", consequence: "wake-time card suppressed"
            )
            self.medianMinutes = median
            self.baselineMedianMinutes = WakeTimeStats.timeOfDay(
                baselineMedianMinutes,
                field: "baseline",
                consequence: "comparison columns dropped, card still shown"
            )
            self.medianWasRefused = medianMinutes != nil && median == nil
            self.recentSampleCount = recentSampleCount
            self.minimumSamples = minimumSamples
        }

        /// Rejects a «median» that is not a time of day, loudly.
        ///
        /// Logged, not asserted, and the difference is deliberate: the tests
        /// for this guard feed 1440 and `25 * 60` through the public
        /// initialiser on purpose, so an `assertionFailure` here would take
        /// down the very suite that proves the guard works. The branch is
        /// unreachable in today's pipeline, which is exactly why the log has
        /// to survive into release — if it ever fires, nothing else will say so.
        /// `consequence` comes from the call site rather than being baked into
        /// the message, because the two fields do NOT have the same one: a
        /// refused median hides the card, a refused baseline only drops the
        /// comparison columns and leaves the card on screen — which this PR's
        /// own `testWakeTimeStats_outOfDayBaselineDropsOnlyTheComparison`
        /// asserts. A single shared sentence therefore told the truth in one
        /// call and lied in the other, and a wrong diagnosis is worse than a
        /// vague one: it sends whoever greps the ID looking for a card that
        /// never disappeared.
        private static func timeOfDay(
            _ minutes: Int?,
            field: String,
            consequence: String
        ) -> Int? {
            guard let minutes else { return nil }
            guard minuteOfDayRange.contains(minutes) else {
                AppLogger.ui.error(
                    """
                    [\(wakeMedianOutOfDayErrorID, privacy: .public)] \
                    \(field, privacy: .public) \(minutes, privacy: .public) is not a \
                    time of day — dropped, \(consequence, privacy: .public)
                    """
                )
                return nil
            }
            return minutes
        }

        /// `baseline − median`; positive = the user now gets up *earlier*.
        var deltaMinutes: Int? {
            guard let median = medianMinutes, let baseline = baselineMedianMinutes else {
                return nil
            }
            return baseline - median
        }

        /// Mornings still missing before the median can be shown.
        var samplesUntilReady: Int { max(0, minimumSamples - recentSampleCount) }

        /// `true` while the median is missing *because history is short* —
        /// the only case in which "Копим историю: нужно ещё N утр" is true.
        ///
        /// Separating it from the rejected-median case matters: there the
        /// window is full, `samplesUntilReady` is 0, and the same copy would
        /// read "нужно ещё 0 утр".
        var isAccumulating: Bool {
            medianMinutes == nil && !medianWasRefused && recentSampleCount < minimumSamples
        }

        /// `true` when there is neither a median to publish nor an honest
        /// "still accumulating" story to tell — the host hides the card.
        var hasNothingToShow: Bool { medianMinutes == nil && !isAccumulating }
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
    /// Returns `nil` when the recent window holds **no** wake instants at all
    /// — including every install that only ever wrote the legacy day-granular
    /// history, for which the card is omitted entirely — and, since #657, when
    /// a full window produced no median the card can vouch for. With between
    /// one and `minimumSamples − 1` mornings the struct comes back with a
    /// `nil` median so the card can say it's still accumulating, rather than
    /// publishing a "typical" time built from one morning.
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
        let stats = WakeTimeStats(
            medianMinutes: medianMinuteOfDay(
                recent, calendar: calendar, minimumSamples: minimumSamples
            ),
            baselineMedianMinutes: medianMinuteOfDay(
                baseline, calendar: calendar, minimumSamples: minimumSamples
            ),
            recentSampleCount: recent.count,
            minimumSamples: minimumSamples
        )
        // A full window whose median the struct refused leaves the card with
        // nothing to say: "Копим историю" would be a lie and a clamped 23:59
        // would be a fabrication. The host hides it instead (#657).
        return stats.hasNothingToShow ? nil : stats
    }

    // MARK: - Presentation strings

    /// "7:04" — minutes-since-midnight rendered as a wall clock.
    ///
    /// The hour cycle belongs to the reader, not to this line: the same median
    /// renders "7:04" for someone on 24-hour time and "7:04 AM" for someone on
    /// 12-hour time (#628). `locale` is injectable so the tests can pin both
    /// readings instead of inheriting whatever the CI runner is set to.
    static func clockText(minutes: Int, locale: Locale = AppLocale.display) -> String {
        WallClockFormatter.string(minutesSinceMidnight: minutes, style: .compact, locale: locale)
    }

    /// Caption above the third wake-time column.
    static func wakeDeltaCaption(minutes: Int) -> String {
        if minutes > 0 { return Localized.text("statistics.wake_time.delta_earlier") }
        if minutes < 0 { return Localized.text("statistics.wake_time.delta_later") }
        return Localized.text("statistics.wake_time.delta_unchanged")
    }

    /// "34 мин" — the delta magnitude; a flat comparison shows an em dash.
    ///
    /// The unit stays catalogue copy rather than becoming a
    /// `MeasurementFormatter`, which was measured rather than assumed:
    /// `.medium` reproduces «34 мин» byte for byte under `ru_RU`, but `.short`
    /// renders the same value as "34m" in English while `.medium` renders
    /// "34 min" — a choice between two spellings is a copy decision, and this
    /// one also has to keep the U+0020 that `SPWakeTimeCard.deltaAttributed`
    /// splits on to re-font the separator. Weekday names went the other way
    /// (``WeekdayNames``) because a table of seven symbols per locale is data
    /// no translator should retype; one abbreviation in a two-label phrase is
    /// not that.
    ///
    /// The em dash is a placeholder glyph, not copy: it means "no comparison",
    /// and it renders identically in every language.
    static func wakeDeltaValueText(minutes: Int) -> String {
        minutes == 0 ? "—" : Localized.format("statistics.wake_time.delta_value", abs(minutes))
    }

    /// "Нужно ещё 3 утра" — copy for a window below `minimumSamples`.
    static func wakeSamplesPendingText(_ missing: Int) -> String {
        Localized.format("statistics.wake_time.samples_pending", missing, morningWord(missing))
    }

    /// "1 утро / 2 утра / 5 утр".
    static func morningWord(_ count: Int) -> String {
        Plural.word(count, .mornings)
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
