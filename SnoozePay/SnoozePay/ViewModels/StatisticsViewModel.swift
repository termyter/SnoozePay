import Foundation

/// ViewModel for the V3 behavioural statistics screen (#235, `SPMore4.jsx`
/// `Stats()`, artboards 27/27a).
///
/// V3 drops every money / wake-time metric (those duplicate the Wallet) and
/// exposes three behavioural aggregations instead:
///   1. Calendar heatmap of the current month — per-day snooze status.
///   2. Average snoozes per weekday over the last 4 weeks (+ worst day).
///   3. 8-week snooze trend (better / same / worse than last week).
///
/// All aggregation maths lives in pure static functions that take an explicit
/// `today` so tests pin dates instead of racing the wall clock; the instance
/// properties are thin wrappers over those functions plus the loaded state.
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

    // MARK: - Dependencies

    private let transactionRepository: TransactionRepository
    private let wakeStore: WakeEventStore
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

    // MARK: - State

    private(set) var charges: [Transaction] = []
    private(set) var wakeDays: Set<Date> = []
    private(set) var streak: Int = 0

    var onDataUpdated: (() -> Void)?
    /// Fired when the transaction repository fails to decode the persisted
    /// ledger. The VC presents an alert so a corrupt blob shows the user a
    /// banner instead of a misleading "ноль откладываний" state (issue #72).
    var onLoadError: ((LocalizedError) -> Void)?

    // MARK: - Init

    init(
        repository: TransactionRepository = .shared,
        wakeStore: WakeEventStore = .shared,
        defaults: UserDefaults = .standard,
        calendar: Calendar = StatisticsViewModel.mondayFirstCalendar
    ) {
        self.transactionRepository = repository
        self.wakeStore = wakeStore
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Load

    func loadData() {
        // Checked read so a corrupt ledger surfaces an alert instead of a
        // deceptive zero-state (issue #72). Streak shares the same in-memory
        // list so the banner and the number can't contradict (issue #117).
        do {
            let allTransactions = try transactionRepository.fetchAllChecked()
            // Exclude charges that were refunded by an offsetting top-up so a
            // snooze that failed to schedule (#130) doesn't count as a real
            // snooze in either total spend or count (issue #133). `realCharges`
            // is the shared filter used by `currentStreak` so the count and the
            // streak can never drift on what "a real snooze" means.
            charges = TransactionRepository.realCharges(from: allTransactions)
            streak = transactionRepository.currentStreak(from: allTransactions)
        } catch let error as TransactionRepository.RepositoryError {
            charges = []
            streak = 0
            onLoadError?(error)
        } catch {
            charges = []
            streak = 0
        }
        wakeDays = wakeStore.wakeDays()

        // Bump persisted best streak only forward — never reset on streak = 0,
        // so the user's all-time record survives a slip-up.
        if streak > defaults.integer(forKey: Self.bestStreakKey) {
            defaults.set(streak, forKey: Self.bestStreakKey)
        }
        onDataUpdated?()
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

    /// Calendar grid for the month containing today. Cells run Monday-first,
    /// row per week, covering full weeks so the count is always a multiple
    /// of 7 (28–42 cells depending on the month's span).
    var heatmapDays: [HeatmapDay] {
        Self.monthGrid(
            today: Date(),
            snoozesByDay: Self.snoozesByDay(charges: charges, calendar: calendar),
            wakeDays: wakeDays,
            calendar: calendar
        )
    }

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

    /// 7 bars Monday-first, each the average snooze count for that weekday
    /// over the trailing 28-day window.
    var weekdayStats: [WeekdayStat] {
        let averages = Self.weekdayAverages(
            today: Date(),
            snoozesByDay: Self.snoozesByDay(charges: charges, calendar: calendar),
            calendar: calendar
        )
        let worst = Self.worstIndex(of: averages)
        return zip(Self.weekdayShortLabels, averages.indices).map { label, index in
            WeekdayStat(label: label, average: averages[index], isWorst: index == worst)
        }
    }

    /// Full lowercase name of the worst weekday ("среда"), `nil` when the
    /// 4-week window carries no snoozes at all.
    var worstWeekdayName: String? {
        let averages = Self.weekdayAverages(
            today: Date(),
            snoozesByDay: Self.snoozesByDay(charges: charges, calendar: calendar),
            calendar: calendar
        )
        guard let index = Self.worstIndex(of: averages) else { return nil }
        return Self.weekdayFullNames[index]
    }

    // MARK: - 8-week trend

    /// 8 calendar weeks oldest → newest; the last point is the current week.
    var weeklyTrend: [WeekTrendPoint] {
        let counts = Self.weeklyCounts(
            today: Date(),
            snoozesByDay: Self.snoozesByDay(charges: charges, calendar: calendar),
            calendar: calendar
        )
        return counts.enumerated().map { index, count in
            WeekTrendPoint(count: count, isCurrent: index == counts.count - 1)
        }
    }

    /// This week's snoozes minus last week's. Negative = improving.
    var trendDiff: Int {
        let counts = Self.weeklyCounts(
            today: Date(),
            snoozesByDay: Self.snoozesByDay(charges: charges, calendar: calendar),
            calendar: calendar
        )
        return Self.trendDiff(weeklyCounts: counts)
    }

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
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 { return "откладываний" }
        switch mod10 {
        case 1: return "откладывание"
        case 2, 3, 4: return "откладывания"
        default: return "откладываний"
        }
    }

    /// "8 января" — shared by the hero meta line and the heatmap tooltip.
    static func dayMonthText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}
