import Foundation

final class TransactionRepository {
    static let shared = TransactionRepository()
    private let key = "stored_transactions"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func fetchAll() -> [Transaction] {
        guard let data = defaults.data(forKey: key),
              let txs = try? JSONDecoder().decode([Transaction].self, from: data)
        else { return [] }
        return txs.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchCharges(since date: Date) -> [Transaction] {
        fetchAll().filter { $0.type == .charge && $0.createdAt >= date }
    }

    @discardableResult
    func record(_ transaction: Transaction) -> Bool {
        var txs = fetchAll()
        txs.append(transaction)
        let data = try? JSONEncoder().encode(txs)
        defaults.set(data, forKey: key)
        return true
    }

    // MARK: - Streak calculation

    /// Returns count of consecutive days ending today with no charge transactions.
    func currentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        let allCharges = fetchAll().filter { $0.type == .charge }
        let chargeDates = Set(allCharges.map { calendar.startOfDay(for: $0.createdAt) })

        while !chargeDates.contains(checkDate) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
            if streak > 365 { break }
        }

        return streak
    }
}
