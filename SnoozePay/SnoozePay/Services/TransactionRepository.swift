import Foundation

/// Persists transactions in UserDefaults with a serial queue protecting all reads and writes.
/// Transactions are a financial ledger — losing entries due to a read-modify-write race
/// (e.g. concurrent BalanceService.charge from a notification action and a manual top-up)
/// would silently corrupt user data.
final class TransactionRepository {

    static let shared = TransactionRepository()

    private let key = "stored_transactions"
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.snoozepay.transactions.serial")

    /// Production code MUST use `TransactionRepository.shared`.
    /// Direct construction creates an isolated instance with its own serial queue —
    /// two such instances racing on the same UserDefaults key reintroduce the race
    /// this class exists to prevent.
    #if DEBUG
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #else
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #endif

    // MARK: - Read

    func fetchAll() -> [Transaction] {
        queue.sync { readAll() }
    }

    func fetchCharges(since date: Date) -> [Transaction] {
        queue.sync {
            readAll().filter { $0.type == .charge && $0.createdAt >= date }
        }
    }

    // MARK: - Mutate

    @discardableResult
    func record(_ transaction: Transaction) -> Bool {
        queue.sync {
            var txs = readAll()
            txs.append(transaction)
            do {
                let data = try JSONEncoder().encode(txs)
                defaults.set(data, forKey: key)
            } catch {
                // Don't write nil — that wipes the financial ledger silently.
                // Issue #23 tracks proper logging+UI surfacing.
                assertionFailure("TransactionRepository encode failed: \(error)")
                print("[TransactionRepository] encode failed, preserving previous state: \(error)")
            }
        }
        return true
    }

    // MARK: - Streak calculation

    /// Returns count of consecutive days ending today with no charge transactions.
    /// Returns 0 if there are no transactions at all (new user).
    func currentStreak() -> Int {
        let allTransactions = queue.sync { readAll() }
        guard !allTransactions.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        let allCharges = allTransactions.filter { $0.type == .charge }
        let chargeDates = Set(allCharges.map { calendar.startOfDay(for: $0.createdAt) })

        let firstTransactionDate = calendar.startOfDay(
            for: allTransactions.map { $0.createdAt }.min() ?? Date()
        )

        while !chargeDates.contains(checkDate) && checkDate >= firstTransactionDate {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
        }

        return streak
    }

    // MARK: - Private (must be called inside queue.sync)

    private func readAll() -> [Transaction] {
        guard let data = defaults.data(forKey: key),
              let txs = try? JSONDecoder().decode([Transaction].self, from: data)
        else { return [] }
        return txs.sorted { $0.createdAt > $1.createdAt }
    }
}
