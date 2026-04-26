import Foundation
import os.log

/// Persists transactions in UserDefaults with a serial queue protecting all reads and writes.
/// Transactions are a financial ledger — losing entries due to a read-modify-write race
/// (e.g. concurrent BalanceService.charge from a notification action and a manual top-up)
/// would silently corrupt user data.
final class TransactionRepository {

    static let shared = TransactionRepository()

    /// Errors surfaced to callers so the UI can warn the user instead of
    /// silently dropping transactions (issue #72). See
    /// `AlarmRepository.RepositoryError` for the analogous treatment.
    enum RepositoryError: LocalizedError {
        case decodeFailure(underlying: Error)
        case encodeFailure(underlying: Error)
        case persistBlocked

        var errorDescription: String? {
            switch self {
            case .decodeFailure:
                return "Не удалось загрузить статистику. Свяжитесь с поддержкой."
            case .encodeFailure:
                return "Не удалось записать транзакцию. Попробуйте ещё раз."
            case .persistBlocked:
                return "Запись заблокирована: данные повреждены. "
                     + "Восстановите состояние через настройки или свяжитесь с поддержкой."
            }
        }
    }

    private let key = "stored_transactions"
    /// Where the corrupt blob is copied on first decode failure so a future
    /// recovery flow / support ticket can inspect what went wrong (issue #72).
    static let corruptBackupKey = "stored_transactions_backup_corrupt"

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.snoozepay.transactions.serial")
    private static let log = OSLog(
        subsystem: "Ivan-Emelyanov.SnoozePay",
        category: "TransactionRepository"
    )

    /// Set inside `queue.sync` whenever a decode failure is observed. While
    /// true, `persist()` refuses to write — this prevents a corrupt ledger
    /// from being silently overwritten by a partial in-memory snapshot
    /// (issue #72).
    private var _lastLoadFailed: Bool = false
    var lastLoadFailed: Bool { queue.sync { _lastLoadFailed } }

    /// Production code MUST use `TransactionRepository.shared` to avoid
    /// creating isolated instances with separate serial queues (which
    /// reintroduces the race this class exists to prevent).
    ///
    /// Tests inject a custom `UserDefaults` suite to stay isolated from app
    /// state — that's why this initializer is `internal` rather than `private`.
    /// We deliberately omit the default value so a stray `TransactionRepository()`
    /// call site cannot bypass the singleton.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private convenience init() {
        self.init(defaults: .standard)
    }

    // MARK: - Read

    func fetchAll() -> [Transaction] {
        queue.sync { (try? readAll()) ?? [] }
    }

    /// Read variant that surfaces decode failures instead of swallowing them
    /// (issue #72). `StatisticsViewModel` uses this so a corrupt ledger
    /// renders a banner rather than a misleading "ноль транзакций" view.
    func fetchAllChecked() throws -> [Transaction] {
        try queue.sync { try readAll() }
    }

    func fetchCharges(since date: Date) -> [Transaction] {
        queue.sync {
            let txs = (try? readAll()) ?? []
            return txs.filter { $0.type == .charge && $0.createdAt >= date }
        }
    }

    // MARK: - Mutate

    /// Records a transaction.
    /// - Returns: `true` on successful persistence, `false` if the store is
    ///   locked due to a prior decode failure or if encoding fails.
    ///   `BalanceService` and other callers can surface the failure to the
    ///   user instead of pretending the charge landed (issue #72).
    @discardableResult
    func record(_ transaction: Transaction) -> Bool {
        queue.sync {
            guard !_lastLoadFailed else { return false }
            var txs: [Transaction]
            do {
                txs = try readAll()
            } catch {
                return false
            }
            txs.append(transaction)
            return persist(txs)
        }
    }

    // MARK: - Streak calculation

    /// Returns count of consecutive days ending today with no charge transactions.
    /// Returns 0 if there are no transactions at all (new user) or if the
    /// store can't be decoded — caller should consult `lastLoadFailed`
    /// before trusting a zero result.
    func currentStreak() -> Int {
        let allTransactions = queue.sync { (try? readAll()) ?? [] }
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

    // MARK: - Recovery

    /// Clears the lock and removes the corrupt blob. Used by a future
    /// "стереть и начать заново" flow once the user has acknowledged the
    /// data loss (issue #72). The diagnostic backup at `corruptBackupKey`
    /// is intentionally left in place for support inspection.
    func clearCorruptState() {
        queue.sync {
            _lastLoadFailed = false
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Private (must be called inside queue.sync)

    /// Returns persisted transactions.
    ///
    /// Differentiates three states (issue #23 / #72):
    ///   1. Key absent — new user, returns `[]` (legitimate empty state).
    ///   2. Key present, decode succeeds — returns sorted transactions.
    ///   3. Key present, decode fails — copies the corrupt blob to the
    ///      backup key (once), sets `_lastLoadFailed = true`, and throws
    ///      `RepositoryError.decodeFailure`. The corrupted JSON stays on
    ///      disk untouched so it remains available for diagnosis.
    private func readAll() throws -> [Transaction] {
        guard let data = defaults.data(forKey: key) else {
            // Case 1: brand-new install — no recorded transactions yet.
            _lastLoadFailed = false
            return []
        }
        do {
            let txs = try JSONDecoder().decode([Transaction].self, from: data)
            _lastLoadFailed = false
            return txs.sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Case 3: stored bytes can't be decoded.
            _lastLoadFailed = true
            if defaults.data(forKey: Self.corruptBackupKey) == nil {
                defaults.set(data, forKey: Self.corruptBackupKey)
            }
            os_log(
                "Decode failed (%{public}d bytes preserved on disk + backup): %{public}@",
                log: Self.log, type: .error, data.count, String(describing: error)
            )
            throw RepositoryError.decodeFailure(underlying: error)
        }
    }

    /// Writes the encoded transaction list to disk.
    /// - Returns: `true` on success, `false` if encoding failed. Never writes
    ///   `nil` — that would wipe the financial ledger silently.
    @discardableResult
    private func persist(_ transactions: [Transaction]) -> Bool {
        do {
            let data = try JSONEncoder().encode(transactions)
            defaults.set(data, forKey: key)
            return true
        } catch {
            // Don't write nil — that wipes the financial ledger silently.
            // If encode fails the previous JSON on disk stays intact (issue #23).
            // assertionFailure is a no-op in release (issue #72) so callers
            // get a Bool back and decide whether to surface an alert.
            os_log(
                "Encode failed, previous state preserved on disk: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
            return false
        }
    }
}
