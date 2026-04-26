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

    private let defaults: UserDefaults
    private let balanceKey = "user_balance"
    private let transactionRepository: TransactionRepository
    private let queue = DispatchQueue(label: "com.snoozepay.balance.serial")
    private let notificationCenter: NotificationCenter

    /// Production code MUST use `BalanceService.shared`.
    /// Direct construction creates an isolated instance with its own serial queue —
    /// two such instances racing on the same UserDefaults key reintroduce the race
    /// this class exists to prevent.
    #if DEBUG
    init(
        defaults: UserDefaults = .standard,
        transactionRepository: TransactionRepository = TransactionRepository(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
        self.notificationCenter = notificationCenter
    }
    #else
    private init(
        defaults: UserDefaults = .standard,
        transactionRepository: TransactionRepository = TransactionRepository(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
        self.notificationCenter = notificationCenter
    }
    #endif

    // MARK: - Read

    var balance: Double {
        queue.sync { defaults.double(forKey: balanceKey) }
    }

    // MARK: - Deduct (snooze penalty)

    /// Attempts to charge the given amount from balance.
    /// Returns true if successful, false if insufficient funds.
    @discardableResult
    func charge(amount: Double, alarmID: UUID?) -> Bool {
        let result: (charged: Bool, newBalance: Double) = queue.sync {
            let current = defaults.double(forKey: balanceKey)
            guard current >= amount else { return (false, current) }

            let newBalance = current - amount
            defaults.set(newBalance, forKey: balanceKey)

            let transaction = Transaction(
                type: .charge,
                amount: amount,
                alarmID: alarmID?.uuidString
            )
            transactionRepository.record(transaction)

            return (true, newBalance)
        }

        if result.charged {
            notifyBalanceChanged(result.newBalance)
        }
        return result.charged
    }

    // MARK: - Top up (IAP)

    func topUp(amount: Double) {
        let newBalance: Double = queue.sync {
            let current = defaults.double(forKey: balanceKey)
            let updated = current + amount
            defaults.set(updated, forKey: balanceKey)

            let transaction = Transaction(
                type: .topup,
                amount: amount
            )
            transactionRepository.record(transaction)

            return updated
        }

        notifyBalanceChanged(newBalance)
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
    func topUp(_ amount: Money) {
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
}
