import Foundation

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
    }

    // MARK: - Dependencies

    private let transactionRepository: TransactionRepository

    // MARK: - State

    private(set) var selectedPeriod: Period = .week
    private(set) var charges: [Transaction] = []
    private(set) var streak: Int = 0

    var onDataUpdated: (() -> Void)?

    // MARK: - Init

    init(repository: TransactionRepository = TransactionRepository()) {
        self.transactionRepository = repository
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
        onDataUpdated?()
    }

    // MARK: - Computed stats

    var totalSpent: Double { charges.reduce(0) { $0 + $1.amount } }
    var snoozeCount: Int { charges.count }

    var totalSpentFormatted: String { "\(Int(totalSpent)) ₽" }
    var snoozeCountFormatted: String { "\(snoozeCount) раз" }

    var motivationalMessage: String {
        guard totalSpent > 0 else { return "Отлично! Вы не откладывали будильник." }
        let coffees = Int(totalSpent / 150)
        if coffees > 0 {
            return "Это стоимость \(coffees) чашек кофе! ☕"
        }
        return "Продолжайте в том же духе!"
    }

    var streakMessage: String {
        guard streak > 0 else { return "" }
        return "\(streak) \(dayWord(streak)) без откладывания"
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
