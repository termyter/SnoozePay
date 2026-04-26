import Foundation
import os

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
    /// Returns true if successful, false if insufficient funds.
    @discardableResult
    func charge(amount: Double, alarmID: UUID?) -> Bool {
        let result: (charged: Bool, newBalance: Double) = queue.sync {
            let current = defaults.double(forKey: balanceKey)
            guard current >= amount else { return (false, current) }

            let transaction = Transaction(
                type: .charge,
                amount: amount,
                alarmID: alarmID?.uuidString
            )
            // Record the ledger entry FIRST. If the transaction repository is
            // locked (corrupt blob waiting on user ack) or encoding fails, we
            // refuse to mutate the balance — otherwise money would silently
            // disappear from the wallet with no record in stats (see #72 hunter
            // review of PR #101).
            guard transactionRepository.record(transaction) else {
                return (false, current)
            }

            let newBalance = current - amount
            defaults.set(newBalance, forKey: balanceKey)
            return (true, newBalance)
        }

        if result.charged {
            notifyBalanceChanged(result.newBalance)
        }
        return result.charged
    }

    // MARK: - Top up (IAP)

    /// Returns `true` if the credit landed (balance moved AND ledger updated).
    /// Returns `false` when the transaction repository is locked or encoding
    /// failed — caller should surface this to the user instead of pretending
    /// the IAP credited (silent ledger desync was the regression behind the #72
    /// PR #101 hunter feedback).
    @discardableResult
    func topUp(amount: Double) -> Bool {
        let result: (recorded: Bool, newBalance: Double) = queue.sync {
            let current = defaults.double(forKey: balanceKey)
            let transaction = Transaction(
                type: .topup,
                amount: amount
            )
            guard transactionRepository.record(transaction) else {
                return (false, current)
            }
            let updated = current + amount
            defaults.set(updated, forKey: balanceKey)
            return (true, updated)
        }

        if result.recorded {
            notifyBalanceChanged(result.newBalance)
        }
        return result.recorded
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
    /// finite — replacing the loose `Double` precondition. Returns whether
    /// the credit actually landed (see legacy `topUp(amount:)`).
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
}
