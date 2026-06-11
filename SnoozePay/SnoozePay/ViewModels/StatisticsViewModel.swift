import Foundation
import UIKit

/// ViewModel for the statistics screen.
final class StatisticsViewModel {

    enum Period: Int, CaseIterable {
        case week = 0, month, allTime

        var title: String {
            switch self {
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .allTime: return "Всё время"
            }
        }

        /// Number of calendar days covered by this period.
        var dayCount: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .allTime: return 0 // variable
            }
        }
    }

    // MARK: - Dependencies

    private let transactionRepository: TransactionRepository
    private let defaults: UserDefaults

    /// UserDefaults key under which the all-time best streak is persisted.
    /// Centralised here so the read in `bestStreak` and the bump in `loadData`
    /// can never drift apart (a typo in either site would silently reset the
    /// user's record).
    private static let bestStreakKey = "best_streak"

    // MARK: - State

    private(set) var selectedPeriod: Period = .week
    private(set) var charges: [Transaction] = []
    private(set) var streak: Int = 0

    var onDataUpdated: (() -> Void)?
    /// Fired when the transaction repository fails to decode the persisted
    /// ledger. The VC presents an alert so a corrupt blob shows the user a
    /// banner instead of a misleading "ноль откладываний" empty state
    /// (issue #72).
    var onLoadError: ((LocalizedError) -> Void)?

    // MARK: - Init

    init(
        repository: TransactionRepository = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.transactionRepository = repository
        self.defaults = defaults
    }

    // MARK: - Load

    func loadData(period: Period = .week) {
        selectedPeriod = period
        let since = startDate(for: period)

        // Use the checked variant so a corrupt ledger surfaces an alert
        // instead of a deceptive zero-state — without this the user sees
        // "₽0 / 0 откладываний" and assumes the app reset, which is much
        // worse than a "не удалось загрузить" message (issue #72).
        //
        // Streak is computed from the same in-memory transaction list rather
        // than re-reading via `currentStreak()` — that earlier path silently
        // returned 0 on a transient decode glitch and contradicted the
        // banner we surface here (issue #117). Sharing one read keeps the
        // banner and the streak number consistent.
        do {
            let allTransactions = try transactionRepository.fetchAllChecked()
            if period == .allTime {
                charges = allTransactions.filter { $0.type == .charge }
            } else {
                charges = allTransactions
                    .filter { $0.type == .charge && $0.createdAt >= since }
            }
            streak = transactionRepository.currentStreak(from: allTransactions)
        } catch let error as TransactionRepository.RepositoryError {
            charges = []
            streak = 0
            onLoadError?(error)
        } catch {
            charges = []
            streak = 0
        }

        // Bump persisted best streak only forward — never reset on streak = 0,
        // so the user's all-time record survives a slip-up. Skipped on a
        // decode failure because `streak == 0` is a fallback, not a truth.
        if streak > defaults.integer(forKey: Self.bestStreakKey) {
            defaults.set(streak, forKey: Self.bestStreakKey)
        }
        onDataUpdated?()
    }

    // MARK: - Computed stats

    var totalSpent: Double { charges.reduce(0) { $0 + $1.amount } }
    var snoozeCount: Int { charges.count }

    /// fmtRub suffix style ("250 ₽") — design v3 retired the ₽-prefix format.
    var totalSpentFormatted: String {
        MoneyFormatter.string(max(totalSpent, 0))
    }
    var snoozeCountFormatted: String { "\(snoozeCount)" }

    // MARK: - Presentation-ready (extracted from StatisticsViewController.refresh)

    /// Colour for the "spent" headline. Orange when there's actual spend to
    /// surface, secondary grey for the empty state. Lives in the VM so the
    /// view doesn't reach into model values to make presentation decisions.
    var spentColor: UIColor {
        totalSpent > 0 ? AppColors.accentOrange : .secondaryLabel
    }

    /// Colour for the snooze-count headline — same secondary-label-on-empty
    /// convention as `spentColor`.
    var snoozeCountColor: UIColor {
        snoozeCount > 0 ? .label : .secondaryLabel
    }

    /// Whether the motivation banner should be visible. Hidden when there's
    /// nothing to motivate against (totalSpent == 0).
    var motivationVisible: Bool {
        totalSpent > 0
    }

    /// Whether the user has an active streak worth celebrating. When false the
    /// view shows a zero-state caption (`streakZeroMessage`) instead of the
    /// "X days without snoozing" / best-result lines.
    var streakActive: Bool {
        streak > 0
    }

    /// Caption shown when the user has no active streak.
    var streakZeroMessage: String {
        "0 дней без откладываний"
    }

    /// Average spending per day for the selected period.
    var averagePerDay: Double {
        let days: Int
        switch selectedPeriod {
        case .week:
            days = 7
        case .month:
            days = 30
        case .allTime:
            // Calculate actual days from earliest charge to now
            guard let earliest = charges.min(by: { $0.createdAt < $1.createdAt }) else { return 0 }
            days = max(Calendar.current.dateComponents([.day], from: earliest.createdAt, to: Date()).day ?? 1, 1)
        }
        guard days > 0 else { return 0 }
        return totalSpent / Double(days)
    }

    var averagePerDayFormatted: String {
        String(format: "%.1f / утро", averagePerDay)
    }

    /// All-time best streak, persisted across launches and never reset on a slip-up.
    var bestStreak: Int {
        defaults.integer(forKey: Self.bestStreakKey)
    }

    var bestStreakFormatted: String {
        "Лучший результат: \(bestStreak) \(dayWord(bestStreak))"
    }

    var motivationalMessage: String {
        guard totalSpent > 0 else { return "Отлично! Вы не откладывали будильник." }
        let coffees = Int(totalSpent / 150)
        if coffees > 0 {
            return "\(MoneyFormatter.string(totalSpent)) на лень = \(coffees) кофе! ☕"
        }
        return "Продолжайте в том же духе!"
    }

    var streakMessage: String {
        guard streak > 0 else { return "" }
        return "\(streak) \(dayWord(streak)) без откладываний"
    }

    /// Daily chart data for the selected period (last 7 or 30 days)
    var dailyChartData: [(label: String, amount: Double)] {
        let calendar = Calendar.current
        let dayCount: Int
        switch selectedPeriod {
        case .week: dayCount = 7
        case .month: dayCount = 30
        case .allTime: return [] // No chart for all time
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = selectedPeriod == .week ? "EE" : "d"

        return (0..<dayCount).reversed().map { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else {
                return ("", 0)
            }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

            let dayTotal = charges
                .filter { $0.createdAt >= start && $0.createdAt < end }
                .reduce(0) { $0 + $1.amount }

            return (dayFormatter.string(from: date), dayTotal)
        }
    }

    // MARK: - Heatmap

    /// Single square in the GitHub-style heatmap calendar.
    /// `intensity` is bucketed 0..4 (5 buckets) so the view can pick a tint
    /// from the money palette without re-running the bucket logic per cell.
    struct HeatmapCell {
        let date: Date
        let amount: Double
        let intensity: Int
    }

    /// 7-column grid of squares spanning the selected period. The order is
    /// chronological (oldest → newest) so a flow-layout collection view fills
    /// rows top-to-bottom, left-to-right with weekday alignment.
    ///
    /// Period sizing:
    /// - `.week` → 7 cells (1 row).
    /// - `.month` → ~35 cells (5 rows of 7).
    /// - `.allTime` → 12 weeks back from today (84 cells).
    /// The grid always begins on the configured calendar's "first weekday"
    /// preceding the start date so columns line up with weekday labels.
    var heatmapCells: [HeatmapCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // How many calendar days does the heatmap span?
        let dayCount: Int
        switch selectedPeriod {
        case .week:
            dayCount = 7
        case .month:
            dayCount = 35
        case .allTime:
            dayCount = 84
        }

        // Per-day total, keyed by startOfDay so look-ups are O(1).
        var totalByDay: [Date: Double] = [:]
        for charge in charges {
            let day = calendar.startOfDay(for: charge.createdAt)
            totalByDay[day, default: 0] += charge.amount
        }

        // Pick a sensible bucket cap: highest single-day spend, fallback to 1
        // so a flat-empty period doesn't divide by zero.
        let maxDayTotal = max(totalByDay.values.max() ?? 0, 1)

        return (0..<dayCount).reversed().map { daysAgo -> HeatmapCell in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let amount = totalByDay[date] ?? 0
            return HeatmapCell(
                date: date,
                amount: amount,
                intensity: Self.bucketIntensity(amount: amount, max: maxDayTotal)
            )
        }
    }

    /// Buckets a per-day amount onto a 0..4 scale. 0 is reserved for the
    /// "no penalty today" empty cell so the view can hand back the
    /// `whiteOverlay06` token without a separate branch. The remaining
    /// 1..4 buckets are evenly split across the observed range.
    private static func bucketIntensity(amount: Double, max maxValue: Double) -> Int {
        guard amount > 0 else { return 0 }
        let ratio = amount / maxValue
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    // MARK: - Bar chart by weekday

    /// Single bar in the weekday chart.
    struct WeekdayBar {
        /// Short localised weekday label (e.g. `"Пн"`).
        let label: String
        /// Average penalty across all matching weekdays in the selected period.
        let amount: Double
        /// Calendar weekday (1 = Sunday … 7 = Saturday) so the view can sort
        /// without re-deriving the order from the label.
        let weekday: Int
    }

    /// Returns 7 bars in Mon → Sun order, each carrying the average penalty
    /// for that weekday across the selected period. Empty days surface as 0
    /// so the chart still renders 7 axis ticks.
    var weekdayBars: [WeekdayBar] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEEEE" // "Пн", "Вт", ...

        // Group charges by Calendar weekday (1-based Sun=1 … Sat=7).
        var bucketTotals: [Int: Double] = [:]
        var bucketDays: [Int: Set<Date>] = [:]
        for charge in charges {
            let weekday = calendar.component(.weekday, from: charge.createdAt)
            let day = calendar.startOfDay(for: charge.createdAt)
            bucketTotals[weekday, default: 0] += charge.amount
            bucketDays[weekday, default: []].insert(day)
        }

        // Render Monday-first regardless of the user's locale calendar so the
        // chart matches the heatmap column order in the spec.
        let mondayFirst: [Int] = [2, 3, 4, 5, 6, 7, 1]
        return mondayFirst.map { weekday -> WeekdayBar in
            let total = bucketTotals[weekday] ?? 0
            let dayCount = bucketDays[weekday]?.count ?? 0
            let average = dayCount > 0 ? total / Double(dayCount) : 0
            // Build a label off a known sample date that falls on this weekday.
            // Calendar weekday 1 = Sunday → 2024-01-07, etc.
            let sample = calendar.date(from: DateComponents(year: 2024, month: 1, day: 6 + weekday)) ?? Date()
            return WeekdayBar(label: formatter.string(from: sample), amount: average, weekday: weekday)
        }
    }

    /// `true` when there are no charge transactions in the selected period.
    /// View uses this to swap the chart/heatmap stack for the empty-state
    /// column.
    var hasData: Bool { !charges.isEmpty }

    // MARK: - Helpers

    private func startDate(for period: Period) -> Date {
        let calendar = Calendar.current
        switch period {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .allTime:
            return Date.distantPast
        }
    }

    private func dayWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "дней" }
        if mod10 == 1 { return "день" }
        if mod10 >= 2 && mod10 <= 4 { return "дня" }
        return "дней"
    }
}
