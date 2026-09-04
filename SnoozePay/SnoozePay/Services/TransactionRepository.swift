import Foundation
import os

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
                return Localized.text("wallet.error.load_failed")
            case .encodeFailure:
                return Localized.text("wallet.error.write_failed")
            case .persistBlocked:
                return Localized.text("wallet.error.write_blocked")
            }
        }
    }

    private let key = "stored_transactions"
    /// Where the corrupt blob is copied on first decode failure so a future
    /// recovery flow / support ticket can inspect what went wrong (issue #72).
    static let corruptBackupKey = "stored_transactions_backup_corrupt"

    private let defaults: UserDefaults
    /// Supplies the wake-day signal the streak now requires (#276). Injected
    /// so tests can pin both inputs; production uses the shared store.
    private let wakeStore: WakeEventStore
    private let queue = DispatchQueue(label: "com.snoozepay.transactions.serial")
    private static let log = OSLog(
        subsystem: AppLogger.subsystem,
        category: "TransactionRepository"
    )

    /// Set inside `queue.sync` whenever a decode failure is observed. While
    /// true, `persist()` refuses to write — this prevents a corrupt ledger
    /// from being silently overwritten by a partial in-memory snapshot
    /// (issue #72).
    private var _lastLoadFailed: Bool = false
    var lastLoadFailed: Bool { queue.sync { _lastLoadFailed } }

    /// Tokens in the `type` field that the last successful load could not
    /// classify (they decoded into `TransactionType.unknown`, see #358).
    ///
    /// A decode that *throws* is loud — it latches `_lastLoadFailed`, backs the
    /// blob up and logs. An unrecognised `type` string does neither on its own,
    /// yet it is just as much an incident: every aggregate skips such a row, so
    /// `Списано` / `weeklyDelta` / streak quietly disagree with `user_balance`.
    /// Byte-level damage to a `type` string used to throw (strict enum) and now
    /// doesn't, so this is the replacement signal — without it #358 would have
    /// turned ledger damage into a silent failure.
    ///
    /// Unlike `_lastLoadFailed` this does NOT block writes: the rows are
    /// individually intact and refusing to record new transactions would be a
    /// harsher penalty than the damage warrants. Like `_lastLoadFailed`, it
    /// describes the most recent load — it stays empty until something reads.
    private var _lastLoadUnrecognizedTypes: Set<String> = []
    var lastLoadUnrecognizedTypes: Set<String> { queue.sync { _lastLoadUnrecognizedTypes } }
    /// Convenience for UI that only needs "should I warn the user".
    var lastLoadHadUnrecognizedTypes: Bool { !lastLoadUnrecognizedTypes.isEmpty }

    /// Production code MUST use `TransactionRepository.shared` to avoid
    /// creating isolated instances with separate serial queues (which
    /// reintroduces the race this class exists to prevent).
    ///
    /// Tests inject a custom `UserDefaults` suite to stay isolated from app
    /// state — that's why this initializer is `internal` rather than `private`.
    /// We deliberately omit the default value so a stray `TransactionRepository()`
    /// call site cannot bypass the singleton.
    init(defaults: UserDefaults, wakeStore: WakeEventStore = .shared) {
        self.defaults = defaults
        self.wakeStore = wakeStore
    }

    private convenience init() {
        self.init(defaults: .standard, wakeStore: .shared)
    }

    // MARK: - Read

    /// Lossy read: a decode failure is indistinguishable from "no
    /// transactions" (#210). Every production call site now uses
    /// `fetchAllChecked()` (#271); kept for the tests that pin the lossy
    /// contract, which is why it is deprecated rather than deleted.
    @available(*, deprecated, message: "Lossy: a decode failure reads as []. Use fetchAllChecked() (#271).")
    func fetchAll() -> [Transaction] {
        queue.sync { (try? readAll()) ?? [] }
    }

    /// Read variant that surfaces decode failures instead of swallowing them
    /// (issue #72). `StatisticsViewModel` uses this so a corrupt ledger
    /// renders a banner rather than a misleading "ноль транзакций" view.
    func fetchAllChecked() throws -> [Transaction] {
        try queue.sync { try readAll() }
    }

    /// Lossy read: a decode failure yields `[]` silently (#210). Display-only
    /// callers (weekly chart) tolerate this; anything that drives money or
    /// scheduling decisions must use `fetchAllChecked()` and filter.
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

    /// Current «серия» — consecutive habit-positive days ending today/yesterday.
    /// Now consults `WakeEventStore` so the count reflects days the user
    /// actually woke without a charge, not merely charge-free calendar days
    /// (#276). See `StreakCalculator` for the full semantics (charge breaks,
    /// neutral alarm-less days skip, today counts only after its wake, empty
    /// wake-store legacy fallback). Returns 0 for a brand-new user or a
    /// corrupt ledger — callers should consult `lastLoadFailed` before
    /// trusting a zero.
    ///
    /// Production callers that have already paid the cost of a checked read
    /// (StatisticsViewModel) should use `currentStreak(from:)` to avoid a
    /// redundant decode on the hot path AND to share the surfaced error
    /// (issue #117).
    func currentStreak() -> Int {
        let allTransactions = queue.sync { (try? readAll()) ?? [] }
        return StreakCalculator.currentStreak(
            transactions: allTransactions,
            wakeDays: wakeStore.wakeDays()
        )
    }

    /// Streak computation against a caller-supplied transaction list. Used
    /// by callers that already loaded transactions via `fetchAllChecked`,
    /// so a single decode failure surfaces once instead of twice and a
    /// transient zero from a hidden re-read can't contradict the surfaced
    /// banner (issue #117). Wake days are still read fresh from the store —
    /// they live in a separate ledger that the transaction snapshot doesn't
    /// cover.
    func currentStreak(from transactions: [Transaction]) -> Int {
        StreakCalculator.currentStreak(
            transactions: transactions,
            wakeDays: wakeStore.wakeDays()
        )
    }

    /// Returns the subset of `transactions` that represent real (non-refunded)
    /// charges. Used by streak computation and by `StatisticsViewModel` so the
    /// two sites can never drift on what counts as "the user actually snoozed".
    static func realCharges(from transactions: [Transaction]) -> [Transaction] {
        let refundedIDs = Set(transactions.compactMap { $0.refundsTransactionID })
        return transactions.filter { $0.type == .charge && !refundedIDs.contains($0.id) }
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
            _lastLoadUnrecognizedTypes = []
            return []
        }
        do {
            let txs = try JSONDecoder().decode([Transaction].self, from: data)
            _lastLoadFailed = false
            noteUnrecognizedTypes(in: txs)
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

    /// Latches + logs the `type` tokens this build couldn't classify.
    ///
    /// Logged only when the token set *changes*, because `readAll` runs on
    /// every UI reload and a per-read `os_log` would bury the incident in its
    /// own noise. MUST be called inside `queue.sync`.
    private func noteUnrecognizedTypes(in transactions: [Transaction]) {
        let tokens = Set(
            transactions.map(\.type).filter(\.isUnrecognized).map(\.rawValue)
        )
        guard tokens != _lastLoadUnrecognizedTypes else { return }
        _lastLoadUnrecognizedTypes = tokens
        guard !tokens.isEmpty else { return }
        // `.error`, not `.info`: in production an unrecognised token means
        // either ledger damage or a build/version skew, and both make the
        // wallet's on-screen totals diverge from `user_balance` (#358).
        os_log(
            "Unrecognised transaction type(s) %{public}@ — %{public}d of %{public}d rows excluded from all aggregates",
            log: Self.log, type: .error,
            tokens.sorted().joined(separator: ", "),
            transactions.filter { $0.type.isUnrecognized }.count,
            transactions.count
        )
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
