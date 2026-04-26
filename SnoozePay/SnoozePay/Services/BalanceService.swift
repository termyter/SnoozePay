import Foundation

/// Manages the user's local balance stored in UserDefaults.
/// All operations are synchronous and offline-first.
/// Mutations and reads are serialized via a private serial queue
/// to prevent check-then-write races between concurrent callers
/// (e.g. notification action + foreground UI).
final class BalanceService {

    static let shared = BalanceService()

    /// Broadcast on every successful balance mutation (charge / topUp).
    /// Multiple observers may subscribe simultaneously — each is independent
    /// and must remove its own observer in `deinit` (or rely on
    /// `NotificationCenter`'s automatic cleanup of dealloc'd weak observers).
    /// `userInfo[Self.balanceUserInfoKey]` carries the new balance as `Double`.
    static let balanceChangedNotification = Notification.Name("snoozepay.balance.changed")
    static let balanceUserInfoKey = "balance"

    /// Broadcast when a `charge` / `topUp` had to be aborted because the
    /// transaction ledger refused the write (corrupt blob → `_lastLoadFailed`,
    /// or encode failure). Without this signal callers would see a `false`
    /// return in `charge` (which is indistinguishable from "insufficient
    /// funds") and `topUp` would have no signal at all — letting an IAP
    /// success silently fail to credit. Surfacing the error here lets
    /// VC-level observers raise an alert. (#72 follow-up.)
    static let balancePersistFailedNotification = Notification.Name("snoozepay.balance.persistFailed")
    static let errorUserInfoKey = "error"

    /// Three-way outcome of a balance mutation, computed inside `queue.sync`
    /// and consumed outside it to drive notifications without holding the
    /// lock during synchronous observer dispatch (issue #72 follow-up).
    private enum MutationOutcome {
        /// Mutation committed; new persisted balance attached for the
        /// `balanceChangedNotification` payload.
        case applied(newBalance: Double)
        /// Ledger refused the write (decode-locked or encode failed).
        /// Balance untouched. Drives `balancePersistFailedNotification`.
        case persistFailed
        /// `charge` only — current balance < requested amount. Silent on the
        /// notification side because this is the legitimate "out of money"
        /// path the UI already handles via `canSnooze`.
        case insufficient
    }

    private let defaults: UserDefaults
    private let balanceKey = "user_balance"
    private let transactionRepository: TransactionRepository
    private let queue = DispatchQueue(label: "com.snoozepay.balance.serial")
    private let notificationCenter: NotificationCenter

    /// Production code MUST use `BalanceService.shared` to avoid creating
    /// isolated instances with separate serial queues (which reintroduces the
    /// race this class exists to prevent).
    ///
    /// Tests inject a custom `UserDefaults` suite to stay isolated from app
    /// state — that's why this initializer is `internal`. The `transactionRepository`
    /// argument has no default to keep test ledgers explicit; tests that don't
    /// care about the ledger pass `TransactionRepository(defaults: testDefaults)`.
    init(
        defaults: UserDefaults,
        transactionRepository: TransactionRepository,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
        self.notificationCenter = notificationCenter
    }

    /// Convenience for tests that supply only `defaults`: builds a matching
    /// ledger pinned to the same suite so charges land in the test store.
    convenience init(
        defaults: UserDefaults,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            defaults: defaults,
            transactionRepository: TransactionRepository(defaults: defaults),
            notificationCenter: notificationCenter
        )
    }

    private convenience init() {
        self.init(
            defaults: .standard,
            transactionRepository: .shared,
            notificationCenter: .default
        )
    }

    // MARK: - Read

    var balance: Double {
        queue.sync { defaults.double(forKey: balanceKey) }
    }

    // MARK: - Deduct (snooze penalty)

    /// Attempts to charge the given amount from balance.
    /// Returns true if successful, false if insufficient funds **or if the
    /// transaction ledger refused the write** (issue #72 follow-up — gauntlet
    /// CRITICAL #1: previously the balance was decremented before `record()`
    /// and its `Bool` return was discarded, so a corrupt ledger produced
    /// "money gone, no receipt" desync). Order is now:
    ///   1. Pre-validate funds.
    ///   2. Attempt `record(...)`. If it fails, surface a notification and
    ///      bail out **without** mutating the persisted balance.
    ///   3. Only on a successful record do we write the new balance to disk.
    /// Callers (FiringVC / FiringCoordinator) treat `false` here as either
    /// insufficient funds **or** persistence failure — they already block on
    /// it via `guard charged else { return }`, so user-perceived behaviour
    /// (no UI snooze) matches actual on-disk state.
    @discardableResult
    func charge(amount: Double, alarmID: UUID?) -> Bool {
        let outcome = queue.sync { () -> MutationOutcome in
            let current = defaults.double(forKey: balanceKey)
            guard current >= amount else { return .insufficient }

            let transaction = Transaction(
                type: .charge,
                amount: amount,
                alarmID: alarmID?.uuidString
            )
            // Record FIRST. If the ledger is locked (decode failure) or encode
            // fails, refuse the charge — silently keeping the old balance is
            // safer than debiting without a receipt.
            guard transactionRepository.record(transaction) else {
                return .persistFailed
            }

            let newBalance = current - amount
            defaults.set(newBalance, forKey: balanceKey)
            return .applied(newBalance: newBalance)
        }

        switch outcome {
        case .applied(let newBalance):
            notifyBalanceChanged(newBalance)
            return true
        case .persistFailed:
            notifyBalancePersistFailed(TransactionRepository.RepositoryError.persistBlocked)
            return false
        case .insufficient:
            return false
        }
    }

    // MARK: - Top up (IAP)

    /// Adds to the balance and records a topup transaction.
    /// - Returns: `true` on success; `false` if the ledger refused the write
    ///   (corrupt blob / encode failure). Callers — notably the IAP flow in
    ///   `StoreKitService` — must surface that to the user, otherwise the
    ///   purchase silently fails to credit (gauntlet CRITICAL #1, #72).
    @discardableResult
    func topUp(amount: Double) -> Bool {
        let outcome = queue.sync { () -> MutationOutcome in
            let current = defaults.double(forKey: balanceKey)
            let updated = current + amount

            let transaction = Transaction(
                type: .topup,
                amount: amount
            )
            // Record FIRST so a corrupt ledger doesn't silently wipe out an
            // IAP that the user actually paid for at Apple's end. Failing
            // closed (no balance change, raise notification) lets the UI
            // tell the user to contact support before they lose money.
            guard transactionRepository.record(transaction) else {
                return .persistFailed
            }

            defaults.set(updated, forKey: balanceKey)
            return .applied(newBalance: updated)
        }

        switch outcome {
        case .applied(let newBalance):
            notifyBalanceChanged(newBalance)
            return true
        case .persistFailed:
            notifyBalancePersistFailed(TransactionRepository.RepositoryError.persistBlocked)
            return false
        case .insufficient:
            return false // unreachable for topUp; kept for exhaustive switch
        }
    }

    // MARK: - Validation

    func canAfford(_ amount: Double) -> Bool {
        queue.sync { defaults.double(forKey: balanceKey) >= amount }
    }

    // MARK: - Typed API (phase 1 of #31)
    //
    // Money-based wrappers around the existing Double API. Storage stays
    // Double for backward compatibility with persisted UserDefaults until
    // phase 2 migrates it. These wrappers reject invalid amounts (negative,
    // NaN, infinite) at the type-system level rather than allowing them
    // through and corrupting the ledger.

    /// Current balance as a `Money` value. Always non-nil — `Double` from
    /// `UserDefaults.double(forKey:)` defaults to `0` (which is valid).
    /// If a corrupt negative value somehow exists, falls back to `.zero`.
    var balanceMoney: Money {
        Money(balance) ?? .zero
    }

    /// Money-typed charge. Returns `false` when funds are insufficient,
    /// matching the legacy `charge(amount:alarmID:)` contract.
    @discardableResult
    func charge(_ amount: Money, alarmID: UUID?) -> Bool {
        charge(amount: amount.toDouble(), alarmID: alarmID)
    }

    /// Money-typed top-up. The `Money` invariant guarantees non-negative,
    /// finite — replacing the loose `Double` precondition.
    @discardableResult
    func topUp(_ amount: Money) -> Bool {
        topUp(amount: amount.toDouble())
    }

    func canAfford(_ amount: Money) -> Bool {
        canAfford(amount.toDouble())
    }

    /// Hop to main since `charge`/`topUp` may be called from a background queue
    /// (notification action handler) and observers drive UIKit. NotificationCenter
    /// delivers synchronously on the posting thread, so we explicitly hop here
    /// rather than push that responsibility onto every observer.
    private func notifyBalanceChanged(_ newBalance: Double) {
        if Thread.isMainThread {
            postBalanceChanged(newBalance)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.postBalanceChanged(newBalance)
            }
        }
    }

    private func postBalanceChanged(_ newBalance: Double) {
        notificationCenter.post(
            name: Self.balanceChangedNotification,
            object: self,
            userInfo: [Self.balanceUserInfoKey: newBalance]
        )
    }

    /// Mirror of `notifyBalanceChanged` for the persist-failed signal — same
    /// thread-hop discipline so VC observers can safely drive UIKit alerts.
    private func notifyBalancePersistFailed(_ error: Error) {
        if Thread.isMainThread {
            postBalancePersistFailed(error)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.postBalancePersistFailed(error)
            }
        }
    }

    private func postBalancePersistFailed(_ error: Error) {
        notificationCenter.post(
            name: Self.balancePersistFailedNotification,
            object: self,
            userInfo: [Self.errorUserInfoKey: error]
        )
    }
}
