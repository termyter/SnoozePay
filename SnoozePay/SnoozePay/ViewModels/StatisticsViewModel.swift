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

    // MARK: - State

    private(set) var selectedPeriod: Period = .week
    private(set) var charges: [Transaction] = []
    private(set) var streak: Int = 0

    var onDataUpdated: (() -> Void)?

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

        if period == .allTime {
            charges = transactionRepository.fetchAll().filter { $0.type == .charge }
        } else {
            charges = transactionRepository.fetchCharges(since: since)
        }

        streak = transactionRepository.currentStreak()
        // Bump persisted best streak only forward — never reset on streak = 0,
        // so the user's all-time record survives a slip-up.
        if streak > defaults.integer(forKey: "best_streak") {
            defaults.set(streak, forKey: "best_streak")
        }
        onDataUpdated?()
    }

    // MARK: - Computed stats

    var totalSpent: Double { charges.reduce(0) { $0 + $1.amount } }
    var snoozeCount: Int { charges.count }

    var totalSpentFormatted: String {
        totalSpent > 0 ? "₽\(Int(totalSpent))" : "₽0"
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
        defaults.integer(forKey: "best_streak")
    }

    var bestStreakFormatted: String {
        "Лучший результат: \(bestStreak) \(dayWord(bestStreak))"
    }

    var motivationalMessage: String {
        guard totalSpent > 0 else { return "Отлично! Вы не откладывали будильник." }
        let coffees = Int(totalSpent / 150)
        if coffees > 0 {
            return "\(Int(totalSpent))₽ на лень = \(coffees) кофе! ☕"
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
