import Foundation
import os

/// ViewModel for the V3 behavioural statistics screen (#235, `SPMore4.jsx`
/// `Stats()`, artboards 27/27a).
///
/// Aggregations exposed to the screen:
///   1. Calendar heatmap of the current month — per-day snooze status.
///   2. Average snoozes per weekday over the last 4 weeks (+ worst day).
///   3. 8-week snooze trend (better / same / worse than last week).
///   4. "Эта неделя" money — saved / spent / net for the current week (#348).
///   5. "Время подъёма" — median wake time vs. the preceding window (#348).
///
/// All aggregation maths lives in pure static functions that take an explicit
/// `today` so tests pin dates instead of racing the wall clock. `loadData()`
/// then publishes their outputs as one stored snapshot for the screen.
final class StatisticsViewModel {

    // MARK: - Day status (heatmap semantics)

    /// Semantics of a single heatmap cell, mirroring the JSX `'g'/'y'/'r'/'-'`
    /// statuses: woke = "встал сразу" (alarm dismissed, 0 snoozes),
    /// light = 1–2 snoozes, heavy = 3+, empty = no alarm / future / padding.
    enum DayStatus: Equatable {
        case woke
        case light
        case heavy
        case empty
    }

    /// Single square of the month-calendar heatmap.
    struct HeatmapDay: Equatable {
        let date: Date
        let status: DayStatus
        /// Charge count for the day (1 charge == 1 snooze).
        let snoozes: Int
        /// Total penalty roubles charged on the day — surfaces in the tooltip.
        let spent: Double
        /// `false` for the leading/trailing padding cells of adjacent months.
        let isInCurrentMonth: Bool
    }

    /// Tooltip payload for a tapped heatmap cell (artboard 27a).
    struct HeatmapTooltip: Equatable {
        /// "27 января"
        let dateText: String
        /// "Встал сразу" / "2 откладывания" / "Не было будильника"
        let statusText: String
        /// "· −150 ₽" when the day carried penalties, `nil` otherwise.
        let spentText: String?
        let status: DayStatus
    }

    // MARK: - Weekday distribution

    /// One bar of the "По дням недели" chart (Monday-first order).
    struct WeekdayStat: Equatable {
        /// Short label — "Пн" … "Вс".
        let label: String
        /// Average snoozes on this weekday across the 4-week window.
        let average: Double
        /// `true` for the single worst (highest-average) day.
        let isWorst: Bool
    }

    // MARK: - Weekly trend

    /// One bar of the 8-week "Динамика откладываний" chart.
    struct WeekTrendPoint: Equatable {
        let count: Int
        /// `true` for the current (rightmost) week.
        let isCurrent: Bool
    }

    enum TrendDirection: Equatable {
        case better
        case same
        case worse
    }

    // Money / wake-time value types live in `StatisticsViewModel+Money.swift`
    // (#348) alongside the aggregations that build them.

    // MARK: - Dependencies

    private let transactionRepository: TransactionRepository
    private let wakeStore: WakeEventStore
    /// Supplies the snooze price behind the "Сэкономили" counterfactual
    /// (#348) — a saved morning is worth whatever a snooze would have cost.
    private let alarmRepository: AlarmRepository
    private let defaults: UserDefaults

    /// UserDefaults key under which the all-time best streak is persisted.
    /// Centralised here so the read in `bestStreak` and the bump in `loadData`
    /// can never drift apart.
    private static let bestStreakKey = "best_streak"

    /// Monday-first gregorian calendar — the design grid is Пн…Вс regardless
    /// of the device locale's first weekday.
    static var mondayFirstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private let calendar: Calendar

    /// Read-only seam for the aggregations split into
    /// `StatisticsViewModel+Money.swift` — `private` is file-scoped, so the
    /// extension in the sibling file can't reach `calendar` directly.
    var aggregationCalendar: Calendar { calendar }

    // MARK: - State

    private(set) var charges: [Transaction] = []
    private(set) var wakeDays: Set<Date> = []
    /// Days on which the user *attempted* a snooze — every `.charge` row,
    /// including ones later rolled back by a refund. `charges` deliberately
    /// drops the rolled-back ones (they never rang), but a morning the user
    /// pressed snooze on is not a morning they saved money, so the money
    /// counterfactual keys off this wider set (#348 review, finding 3).
    private(set) var attemptedSnoozeDays: Set<Date> = []
    /// Exact wake instants (#348) — empty for installs that only recorded
    /// day-granular wakes before the timestamp key shipped.
    private(set) var wakeTimes: [Date] = []
    /// Snooze price behind the "Сэкономили" counterfactual. `nil` means "we
    /// have no honest price" — see `snoozePriceState` for *why*. Distinct
    /// from a genuine 0 ₽ price when every alarm is free.
    var snoozePrice: Double? { snoozePriceState.price }
    /// Why ledger-derived statistics can't publish figures, or `nil` when
    /// they can.
    ///
    /// Money aggregates built on a partial ledger overstate savings and
    /// understate spending (#348 review, finding 1), so the screen withholds
    /// every ledger-derived block and names the failure rather than silently
    /// rendering a plausible-looking zero (#348 verification, finding 3).
    private(set) var ledgerUnavailableReason: LedgerUnavailableReason?
    /// Convenience for call sites that only need "can we publish money".
    var ledgerReadable: Bool { ledgerUnavailableReason == nil }

    /// How the snooze price resolved — separates "no alarm to price a morning
    /// with" from "the alarm store is damaged", which used to collapse into
    /// one `nil` and produce a misleading, unactionable caption
    /// (#348 verification, finding 4).
    private(set) var snoozePriceState: SnoozePriceState = .noPricedAlarms
    private(set) var streak: Int = 0

    /// Precomputed on `loadData` so the bars and the totals are derived from
    /// one snapshot — recomputing them lazily read `Date()` twice and ran the
    /// aggregation twice per `viewWillAppear` (#348 review, finding 6).
    private(set) var weekMoneyDays: [WeekMoneyDay] = []
    private(set) var weekMoneySummary = MoneySummary.empty
    private(set) var wakeTimeStats: WakeTimeStats?
    /// Every behavioural aggregate is published from the same `loadData()`
    /// snapshot as the money summary. Keeping these stored avoids a midnight
    /// split where one card asks `Date()` before the boundary and another
    /// asks after it (#459).
    private(set) var heatmapDays: [HeatmapDay] = []
    private(set) var weekdayStats: [WeekdayStat] = []
    private(set) var worstWeekdayName: String?
    private(set) var weeklyTrend: [WeekTrendPoint] = []
    private(set) var trendDiff = 0

    var onDataUpdated: (() -> Void)?
    /// Fired when the transaction repository fails to decode the persisted
    /// ledger. The VC presents an alert so a corrupt blob shows the user a
    /// banner instead of a misleading "ноль откладываний" state (issue #72).
    var onLoadError: ((LocalizedError) -> Void)?

    // MARK: - Init

    init(
        repository: TransactionRepository = .shared,
        wakeStore: WakeEventStore = .shared,
        alarmRepository: AlarmRepository = .shared,
        defaults: UserDefaults = .standard,
        calendar: Calendar = StatisticsViewModel.mondayFirstCalendar
    ) {
        self.transactionRepository = repository
        self.wakeStore = wakeStore
        self.alarmRepository = alarmRepository
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Load

    func loadData() {
        // Capture clock and wake history before any storage read. The hero,
        // heatmap and money/trend snapshots must describe one instant even if
        // midnight or a new dismissal lands while the ledger is decoding.
        let now = Date()
        let capturedWakeDays = wakeStore.wakeDays()
        let capturedWakeTimes = wakeStore.wakeTimes()

        // Checked read so a corrupt ledger surfaces an alert instead of a
        // deceptive zero-state (issue #72). Streak shares the same in-memory
        // list so the banner and the number can't contradict (issue #117).
        do {
            let allTransactions = try transactionRepository.fetchAllChecked()
            // Exclude charges that were refunded by an offsetting credit so a
            // snooze that failed to schedule (#130) doesn't count as a real
            // snooze in either total spend or count (issue #133). `realCharges`
            // is the shared filter used by `currentStreak` so the count and the
            // streak can never drift on what "a real snooze" means.
            charges = TransactionRepository.realCharges(from: allTransactions)
            attemptedSnoozeDays = Self.attemptedSnoozeDays(
                from: allTransactions, calendar: calendar
            )
            // A successful decode can still be partial: since #453 an
            // unrecognised `type` token decodes to `.unknown` instead of
            // throwing, and every aggregate silently skips those rows. That
            // inflates "Сэкономили" by exactly the days whose charges dropped
            // out, so it disqualifies every ledger-derived statistic just like
            // a hard failure.
            let unknownTokens = transactionRepository.lastLoadUnrecognizedTypes
            if unknownTokens.isEmpty {
                ledgerUnavailableReason = nil
                streak = StreakCalculator.currentStreak(
                    transactions: allTransactions,
                    wakeDays: capturedWakeDays,
                    now: now,
                    calendar: calendar
                )
            } else {
                ledgerUnavailableReason = .ledgerPartiallyRead
                // An unrecognised row might be a skipped charge. Do not
                // promote an uncertain streak into the persisted best record.
                streak = 0
                // Nothing throws on this path, so this log is the only trace
                // an incident leaves — version skew, byte damage to a `type`
                // string, or a half-finished migration all land here.
                AppLogger.repository.error(
                    """
                    [\(Self.partialLedgerErrorID, privacy: .public)] Statistics suppressed: \
                    ledger carries \(unknownTokens.count, privacy: .public) unrecognised \
                    type token(s): \(unknownTokens.sorted().joined(separator: ","), privacy: .public)
                    """
                )
            }
        } catch let error as TransactionRepository.RepositoryError {
            resetLedgerState()
            onLoadError?(error)
        } catch {
            resetLedgerState()
        }
        wakeDays = capturedWakeDays
        wakeTimes = capturedWakeTimes
        loadSnoozePrice()

        // Bump persisted best streak only forward — never reset on streak = 0,
        // so the user's all-time record survives a slip-up.
        if ledgerReadable, streak > defaults.integer(forKey: Self.bestStreakKey) {
            defaults.set(streak, forKey: Self.bestStreakKey)
        }
        recomputeSnapshots(today: now)
        onDataUpdated?()
    }

    /// Collapses every ledger-derived figure to its "we don't know" value.
    /// Zeroing `charges` alone used to leave `ledgerReadable == true`, which
    /// let a heatmap, streak or money total render from a ledger it never
    /// managed to read (#348 review, finding 1; #459).
    private func resetLedgerState() {
        charges = []
        attemptedSnoozeDays = []
        streak = 0
        ledgerUnavailableReason = .ledgerUnreadable
    }

    /// Reads the alarms that price a saved morning.
    ///
    /// Checked read: `stored_alarms` and `stored_transactions` are independent
    /// blobs, so a broken alarm store raises no ledger banner of its own — a
    /// lossy read here would silently collapse "Сэкономили" to nothing while
    /// the Будильники tab loudly reports the same store as corrupt (#348
    /// review, finding 5).
    ///
    /// The two failure modes stay separate: "you have no alarm with a price"
    /// is actionable advice, "your alarm store is damaged" is a different
    /// problem with a different fix, and telling the second user the first
    /// thing sends them to edit an alarm that is already priced
    /// (#348 verification, finding 4).
    private func loadSnoozePrice() {
        do {
            let alarms = try alarmRepository.fetchAllChecked()
            if let price = Self.snoozePrice(alarms: alarms) {
                snoozePriceState = .known(price)
            } else {
                snoozePriceState = .noPricedAlarms
            }
        } catch {
            snoozePriceState = .alarmStoreUnreadable
            AppLogger.repository.error(
                """
                [\(Self.alarmStoreErrorID, privacy: .public)] Savings unpriced: \
                alarm store unreadable: \(String(describing: error), privacy: .public)
                """
            )
        }
    }

    /// Rebuilds every statistics snapshot from one `today`, so cards cannot
    /// come from different reads of the clock. A ledger failure clears every
    /// ledger-dependent publication instead of letting an empty `charges`
    /// array masquerade as a perfect, snooze-free history (#459).
    ///
    /// `today` is a parameter so tests can pin it — see the money-bars test
    /// and `StatisticsSnapshotTests`, which drive different days through this
    /// method to prove every visible aggregate moves together.
    func recomputeSnapshots(today: Date) {
        guard ledgerReadable else {
            weekMoneyDays = []
            weekMoneySummary = .empty
            heatmapDays = []
            weekdayStats = []
            worstWeekdayName = nil
            weeklyTrend = []
            trendDiff = 0
            wakeTimeStats = Self.wakeTimeStats(
                today: today, wakeTimes: wakeTimes, calendar: calendar
            )
            return
        }

        weekMoneyDays = Self.weekMoneyDays(
            today: today,
            inputs: MoneyInputs(
                charges: charges,
                wakeDays: wakeDays,
                attemptedSnoozeDays: attemptedSnoozeDays,
                snoozePrice: snoozePrice
            ),
            calendar: calendar
        )
        weekMoneySummary = Self.moneySummary(days: weekMoneyDays)
        wakeTimeStats = Self.wakeTimeStats(
            today: today, wakeTimes: wakeTimes, calendar: calendar
        )

        let snoozesByDay = Self.snoozesByDay(charges: charges, calendar: calendar)

        heatmapDays = Self.monthGrid(
            today: today,
            snoozesByDay: snoozesByDay,
            wakeDays: wakeDays,
            calendar: calendar
        )
        let averages = Self.weekdayAverages(
            today: today, snoozesByDay: snoozesByDay, calendar: calendar
        )
        let worst = Self.worstIndex(of: averages)
        weekdayStats = zip(Self.weekdayShortLabels, averages.indices).map { label, index in
            WeekdayStat(label: label, average: averages[index], isWorst: index == worst)
        }
        worstWeekdayName = worst.map { Self.weekdayFullNames[$0] }
        let counts = Self.weeklyCounts(
            today: today, snoozesByDay: snoozesByDay, calendar: calendar
        )
        weeklyTrend = counts.enumerated().map { index, count in
            WeekTrendPoint(count: count, isCurrent: index == counts.count - 1)
        }
        trendDiff = Self.trendDiff(weeklyCounts: counts)
    }

    // MARK: - Hero (Серия)

    /// All-time best streak, persisted across launches, never reset on a slip.
    var bestStreak: Int {
        defaults.integer(forKey: Self.bestStreakKey)
    }

    /// "Последний срыв: 8 января" — date of the most recent charge, or the
    /// "no slips yet" caption for a clean ledger.
    var lastSlipText: String {
        guard let latest = charges.map(\.createdAt).max() else {
            return "Срывов ещё не было"
        }
        return "Последний срыв: \(Self.dayMonthText(latest))"
    }

    // MARK: - Heatmap

    /// Weekday header labels for the heatmap grid, Monday-first.
    static let weekdayShortLabels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    /// `heatmapDays` is a calendar grid for the snapshot month. Cells run
    /// Monday-first, one row per week, and cover full weeks so the count is
    /// always a multiple of 7 (28–42 cells depending on the month's span).
    /// Tooltip payload for a tapped heatmap cell (artboard 27a).
    func tooltip(for day: HeatmapDay) -> HeatmapTooltip {
        HeatmapTooltip(
            dateText: Self.dayMonthText(day.date),
            statusText: Self.statusText(for: day),
            spentText: day.spent > 0 ? "· −\(MoneyFormatter.string(day.spent))" : nil,
            status: day.status
        )
    }

    // MARK: - Weekday distribution (last 4 weeks)

    // `weekdayStats` holds seven Monday-first bars: the average snooze count
    // per weekday over the snapshot's trailing 28-day window.
    // `worstWeekdayName` is its full lowercase name ("среда"), or `nil`
    // when the window carries no snoozes.
    // MARK: - 8-week trend

    // `weeklyTrend` holds eight calendar weeks oldest → newest; the last
    // point is the snapshot's current week.
    /// This week's snoozes minus last week's. Negative = improving.
    var trendDirection: TrendDirection {
        Self.direction(forDiff: trendDiff)
    }

    var trendHeadline: String {
        Self.headline(for: trendDirection)
    }

    var trendSubtitle: String {
        Self.subtitle(forDiff: trendDiff)
    }

    /// Snooze count of the current week — the big number next to "Эта неделя".
    var thisWeekCount: Int {
        weeklyTrend.last?.count ?? 0
    }

    // MARK: - Pure aggregation (static, deterministic for tests)

    /// Per-day snooze count + penalty total, keyed by `startOfDay`.
    /// One `.charge` transaction == one snooze (the firing flow records
    /// exactly one charge per snooze).
    static func snoozesByDay(
        charges: [Transaction],
        calendar: Calendar
    ) -> [Date: (count: Int, spent: Double)] {
        var byDay: [Date: (count: Int, spent: Double)] = [:]
        for charge in charges where charge.type == .charge {
            let day = calendar.startOfDay(for: charge.createdAt)
            let current = byDay[day] ?? (0, 0)
            byDay[day] = (current.count + 1, current.spent + charge.amount)
        }
        return byDay
    }

    /// Maps a day's raw data onto the heatmap semantics. `woke` requires an
    /// explicit wake event — a quiet day without one renders "не было
    /// будильника" (dark), per the issue's missing-data fallback.
    static func dayStatus(snoozes: Int, woke: Bool) -> DayStatus {
        if snoozes >= 3 { return .heavy }
        if snoozes >= 1 { return .light }
        return woke ? .woke : .empty
    }

    /// Builds the month-calendar grid for the month containing `today`.
    /// Pads to full Monday-first weeks; padding / future days are `.empty`.
    static func monthGrid(
        today: Date,
        snoozesByDay: [Date: (count: Int, spent: Double)],
        wakeDays: Set<Date>,
        calendar: Calendar
    ) -> [HeatmapDay] {
        let todayStart = calendar.startOfDay(for: today)
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: todayStart),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
            // `monthInterval.end` is the first instant of the next month —
            // step back one day to stay inside the displayed month.
            let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
            let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDayOfMonth)
        else { return [] }

        var days: [HeatmapDay] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            let day = calendar.startOfDay(for: cursor)
            let isInMonth = day >= monthInterval.start && day < monthInterval.end
            let data = snoozesByDay[day] ?? (0, 0)
            let isPastOrToday = day <= todayStart
            let status: DayStatus
            if isInMonth && isPastOrToday {
                status = dayStatus(snoozes: data.count, woke: wakeDays.contains(day))
            } else {
                status = .empty
            }
            days.append(
                HeatmapDay(
                    date: day,
                    status: status,
                    snoozes: isInMonth && isPastOrToday ? data.count : 0,
                    spent: isInMonth && isPastOrToday ? data.spent : 0,
                    isInCurrentMonth: isInMonth
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Average snoozes per weekday (Monday-first) across the trailing 28-day
    /// window ending today. 28 days = exactly 4 occurrences of each weekday,
    /// so the average is `total / 4`.
    static func weekdayAverages(
        today: Date,
        snoozesByDay: [Date: (count: Int, spent: Double)],
        calendar: Calendar
    ) -> [Double] {
        let todayStart = calendar.startOfDay(for: today)
        // Calendar weekday is 1 = Sunday … 7 = Saturday; remap Monday-first.
        let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]
        var totals = [Int: Int]()
        for offset in 0..<28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            totals[weekday, default: 0] += snoozesByDay[day]?.count ?? 0
        }
        return mondayFirstWeekdays.map { Double(totals[$0] ?? 0) / 4.0 }
    }

    /// Index of the single worst (highest) average; `nil` when every value
    /// is zero — "Чаще всего" makes no sense on a clean month.
    static func worstIndex(of averages: [Double]) -> Int? {
        guard let maxValue = averages.max(), maxValue > 0 else { return nil }
        return averages.firstIndex(of: maxValue)
    }

    /// Snooze totals for the trailing 8 calendar weeks (Monday-start),
    /// oldest → newest; the final entry is the week containing `today`.
    static func weeklyCounts(
        today: Date,
        snoozesByDay: [Date: (count: Int, spent: Double)],
        calendar: Calendar,
        weeks: Int = 8
    ) -> [Int] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return Array(repeating: 0, count: weeks)
        }
        return (0..<weeks).reversed().map { weeksAgo -> Int in
            guard
                let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: currentWeek.start),
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)
            else { return 0 }
            return snoozesByDay
                .filter { $0.key >= weekStart && $0.key < weekEnd }
                .reduce(0) { $0 + $1.value.count }
        }
    }

    static func trendDiff(weeklyCounts counts: [Int]) -> Int {
        guard counts.count >= 2 else { return 0 }
        return counts[counts.count - 1] - counts[counts.count - 2]
    }

    static func direction(forDiff diff: Int) -> TrendDirection {
        if diff < 0 { return .better }
        if diff > 0 { return .worse }
        return .same
    }

    static func headline(for direction: TrendDirection) -> String {
        switch direction {
        case .better: return "Становится лучше"
        case .same: return "Стабильно"
        case .worse: return "Чаще, чем неделю назад"
        }
    }

    /// "−2 к прошлой неделе" / "+3 к прошлой неделе" / the same-level caption.
    /// Uses the typographic minus (U+2212) per the design copy.
    static func subtitle(forDiff diff: Int) -> String {
        if diff == 0 { return "Столько же, сколько на прошлой неделе" }
        let sign = diff < 0 ? "−" : "+"
        return "\(sign)\(abs(diff)) к прошлой неделе"
    }

    // MARK: - Presentation strings

    /// Full lowercase weekday names, Monday-first — "Чаще всего — среда".
    static let weekdayFullNames = [
        "понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"
    ]

    /// Value rendered above a weekday bar: whole averages drop the fraction
    /// ("4"), fractional ones keep a single decimal with the Russian comma
    /// ("1,5").
    static func barValueText(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Tooltip status copy with the Russian declension of "откладывание".
    static func statusText(for day: HeatmapDay) -> String {
        switch day.status {
        case .woke:
            return "Встал сразу"
        case .light, .heavy:
            return "\(day.snoozes) \(snoozeWord(day.snoozes))"
        case .empty:
            return "Не было будильника"
        }
    }

    /// "1 откладывание / 2 откладывания / 5 откладываний".
    static func snoozeWord(_ count: Int) -> String {
        Plural.word(count, .snoozes)
    }

    /// "8 января" — shared by the hero meta line and the heatmap tooltip.
    static func dayMonthText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.display
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}
