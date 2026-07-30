import Foundation

/// Money + wake-time aggregations of the statistics screen (#348,
/// `SPMore4.jsx` `Stats()`, artboard `27-stats`).
///
/// Split out of `StatisticsViewModel.swift` so the main type body stays under
/// SwiftLint's `type_body_length` ceiling — the same treatment
/// `StatisticsViewController+Cards.swift` gives the view controller. Nothing
/// here touches the behavioural aggregations.
extension StatisticsViewModel {

    // MARK: - "Эта неделя" money summary

    /// One column of the "ЭТА НЕДЕЛЯ" money chart — a green "saved" stack and
    /// a red "lost" stack, exactly like `SPMore4.jsx` `Stats()`.
    struct WeekMoneyDay: Equatable {
        /// Short weekday label — "Пн" … "Вс".
        let label: String
        /// Counterfactual roubles kept by not snoozing that morning.
        let saved: Double
        /// Penalty roubles actually charged that day.
        let spent: Double
        /// `false` for days of the current week that haven't happened yet —
        /// those render as an empty column instead of a misleading zero.
        let isPastOrToday: Bool
    }

    /// The three money totals under the week chart: "Сэкономили / Потратили /
    /// Чистый".
    struct MoneySummary: Equatable {
        let saved: Double
        let spent: Double
        var net: Double { saved - spent }
        /// `true` when the period carries neither savings nor charges — the
        /// card then shows a neutral "нет данных" line instead of `+0 ₽`
        /// triplets that read like a bug.
        var isEmpty: Bool { saved == 0 && spent == 0 }
    }

    // MARK: - "Время подъёма"

    /// Averages behind the "ВРЕМЯ ПОДЪЁМА" card. Minutes are minutes-since-
    /// midnight so the view can format them without re-deriving dates.
    struct WakeTimeStats: Equatable {
        /// Mean wake time over the recent window.
        let averageMinutes: Int
        /// Mean wake time over the window immediately before it — `nil` when
        /// that window recorded no wakes, in which case the card drops the
        /// "Раньше было" / "Раньше на" columns instead of faking a baseline.
        let baselineMinutes: Int?
        /// `baseline − average`; positive = the user now gets up *earlier*.
        /// `nil` whenever `baselineMinutes` is.
        var deltaMinutes: Int? {
            guard let baseline = baselineMinutes else { return nil }
            return baseline - averageMinutes
        }
    }

    // MARK: - Instance accessors

    /// Seven Monday-first columns for the current week's money chart.
    var weekMoneyDays: [WeekMoneyDay] {
        Self.weekMoneyDays(
            today: Date(),
            charges: charges,
            wakeDays: wakeDays,
            snoozePrice: snoozePrice,
            calendar: aggregationCalendar
        )
    }

    /// "Сэкономили / Потратили / Чистый" totals for the current week.
    var weekMoneySummary: MoneySummary {
        Self.moneySummary(days: weekMoneyDays)
    }

    /// Wake-time averages, or `nil` when the recent window recorded no exact
    /// wake instants at all — the card is then omitted rather than showing a
    /// made-up time (issue #348: "не выдумывать фейковые числа").
    var wakeTimeStats: WakeTimeStats? {
        Self.wakeTimeStats(
            today: Date(),
            wakeTimes: wakeTimes,
            calendar: aggregationCalendar
        )
    }

    // MARK: - Pure aggregation — money

    /// Price of one snooze, used to value a clean morning in the "Сэкономили"
    /// counterfactual.
    ///
    /// Formula: arithmetic mean of `penaltyAmount` across **enabled** alarms.
    /// A disabled alarm's penalty isn't a price the user is currently exposed
    /// to, so it only enters the mean when every alarm is off (better an
    /// approximate price than none). With no alarms at all the price is 0 —
    /// there is no honest number to multiply a clean morning by, and the card
    /// then renders its "нет данных" state rather than an invented figure.
    static func snoozePrice(alarms: [Alarm]) -> Double {
        let enabled = alarms.filter(\.enabled)
        let pool = enabled.isEmpty ? alarms : enabled
        let prices = pool.map(\.penaltyAmount).filter { $0.isFinite && $0 > 0 }
        guard !prices.isEmpty else { return 0 }
        return prices.reduce(0, +) / Double(prices.count)
    }

    /// Seven Monday-first columns of the current week's money chart.
    ///
    /// - **Потратили** (`spent`) — factual: the penalty roubles charged that
    ///   day. Derived from `snoozesByDay`, which only ever sums `.charge`
    ///   rows out of the already refund-filtered `charges` list, so new
    ///   transaction kinds can't leak into the total.
    /// - **Сэкономили** (`saved`) — counterfactual: a morning the user was
    ///   demonstrably woken on (a wake event exists) *and* paid nothing for
    ///   is worth one snooze price. Days with no wake event contribute 0 —
    ///   we can't claim savings on a day we have no evidence an alarm rang.
    /// - Future days of the current week are marked `isPastOrToday == false`
    ///   and contribute nothing, so Wednesday's chart doesn't imply the user
    ///   already saved money on Saturday.
    static func weekMoneyDays(
        today: Date,
        charges: [Transaction],
        wakeDays: Set<Date>,
        snoozePrice: Double,
        calendar: Calendar
    ) -> [WeekMoneyDay] {
        let todayStart = calendar.startOfDay(for: today)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: todayStart) else { return [] }
        let byDay = snoozesByDay(charges: charges, calendar: calendar)
        return weekdayShortLabels.indices.map { offset in
            let label = weekdayShortLabels[offset]
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: week.start),
                calendar.startOfDay(for: day) <= todayStart
            else {
                return WeekMoneyDay(label: label, saved: 0, spent: 0, isPastOrToday: false)
            }
            let dayStart = calendar.startOfDay(for: day)
            let data = byDay[dayStart] ?? (count: 0, spent: 0)
            let saved = (data.count == 0 && wakeDays.contains(dayStart)) ? snoozePrice : 0
            return WeekMoneyDay(label: label, saved: saved, spent: data.spent, isPastOrToday: true)
        }
    }

    /// Totals of the week columns — "Чистый" falls out of `saved − spent`
    /// and is free to go negative on a bad week.
    static func moneySummary(days: [WeekMoneyDay]) -> MoneySummary {
        MoneySummary(
            saved: days.reduce(0) { $0 + $1.saved },
            spent: days.reduce(0) { $0 + $1.spent }
        )
    }

    // MARK: - Pure aggregation — wake time

    /// Span of each half of the wake-time comparison. Two weeks is long
    /// enough to absorb a single overslept morning yet short enough that
    /// "раньше было" still describes recent behaviour.
    static var wakeTimeWindowDays: Int { 14 }

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

    /// Arithmetic mean of the minute-of-day values, rounded to the nearest
    /// minute. Deliberately not a circular mean: wake times cluster in the
    /// morning, so the midnight wrap-around a circular mean guards against
    /// can't realistically occur, and a plain mean stays explainable.
    static func averageMinuteOfDay(_ times: [Date], calendar: Calendar) -> Int? {
        guard !times.isEmpty else { return nil }
        let total = times.reduce(0) { $0 + minuteOfDay($1, calendar: calendar) }
        return Int((Double(total) / Double(times.count)).rounded())
    }

    /// "В среднем" over the trailing `windowDays`, compared with the
    /// `windowDays` before that.
    ///
    /// Returns `nil` when the recent window holds no exact wake instants —
    /// including every install that only ever wrote the legacy day-granular
    /// wake history. The card is then omitted entirely; inventing a time
    /// from a bare calendar day would be a fabricated number.
    static func wakeTimeStats(
        today: Date,
        wakeTimes: [Date],
        calendar: Calendar,
        windowDays: Int = StatisticsViewModel.wakeTimeWindowDays
    ) -> WakeTimeStats? {
        let todayStart = calendar.startOfDay(for: today)
        guard
            windowDays > 0,
            let recentStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: todayStart),
            let baselineStart = calendar.date(byAdding: .day, value: -windowDays, to: recentStart)
        else { return nil }
        let firstWakes = firstWakePerDay(times: wakeTimes, calendar: calendar)
        let recent = firstWakes.filter { $0.key >= recentStart && $0.key <= todayStart }.map(\.value)
        guard let average = averageMinuteOfDay(recent, calendar: calendar) else { return nil }
        let baseline = firstWakes.filter { $0.key >= baselineStart && $0.key < recentStart }.map(\.value)
        return WakeTimeStats(
            averageMinutes: average,
            baselineMinutes: averageMinuteOfDay(baseline, calendar: calendar)
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

    /// Signed money used by the summary row: "+800 ₽" / "−400 ₽" / "0 ₽".
    /// Uses the typographic minus (U+2212) to match the design copy.
    static func signedMoneyText(_ amount: Double) -> String {
        let rounded = amount.rounded()
        if rounded == 0 { return MoneyFormatter.string(0.0) }
        let sign = rounded < 0 ? "−" : "+"
        return "\(sign)\(MoneyFormatter.string(abs(rounded)))"
    }
}
