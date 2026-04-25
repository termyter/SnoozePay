import Foundation

/// Manages the user's local balance stored in UserDefaults.
/// All operations are synchronous and offline-first.
/// Mutations and reads are serialized via a private serial queue
/// to prevent check-then-write races between concurrent callers
/// (e.g. notification action + foreground UI).
final class BalanceService {

    static let shared = BalanceService()

    private let defaults: UserDefaults
    private let balanceKey = "user_balance"
    private let transactionRepository: TransactionRepository
    private let queue = DispatchQueue(label: "com.snoozepay.balance.serial")

    // Observers can subscribe to balance changes
    var onBalanceChanged: ((Double) -> Void)?

    /// Production code MUST use `BalanceService.shared`.
    /// Direct construction creates an isolated instance with its own serial queue —
    /// two such instances racing on the same UserDefaults key reintroduce the race
    /// this class exists to prevent.
    #if DEBUG
    init(
        defaults: UserDefaults = .standard,
        transactionRepository: TransactionRepository = TransactionRepository()
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
    }
    #else
    private init(
        defaults: UserDefaults = .standard,
        transactionRepository: TransactionRepository = TransactionRepository()
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
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

    /// Hop to main since `charge`/`topUp` may be called from a background queue
    /// (notification action handler) and listeners drive UIKit.
    private func notifyBalanceChanged(_ newBalance: Double) {
        if Thread.isMainThread {
            onBalanceChanged?(newBalance)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onBalanceChanged?(newBalance)
            }
        }
    }
}
