import Foundation

/// Manages the user's local balance stored in UserDefaults.
/// All operations are synchronous and offline-first.
final class BalanceService {

    static let shared = BalanceService()

    private let defaults: UserDefaults
    private let balanceKey = "user_balance"
    private let transactionRepository: TransactionRepository

    // Observers can subscribe to balance changes
    var onBalanceChanged: ((Double) -> Void)?

    private init(
        defaults: UserDefaults = .standard,
        transactionRepository: TransactionRepository = TransactionRepository()
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
    }

    // MARK: - Read

    var balance: Double {
        defaults.double(forKey: balanceKey)
    }

    // MARK: - Deduct (snooze penalty)

    /// Attempts to charge the given amount from balance.
    /// Returns true if successful, false if insufficient funds.
    @discardableResult
    func charge(amount: Double, alarmID: UUID?) -> Bool {
        guard balance >= amount else { return false }

        let newBalance = balance - amount
        defaults.set(newBalance, forKey: balanceKey)

        let transaction = Transaction(
            type: .charge,
            amount: amount,
            alarmID: alarmID?.uuidString
        )
        transactionRepository.record(transaction)

        onBalanceChanged?(newBalance)
        return true
    }

    // MARK: - Top up (IAP)

    func topUp(amount: Double) {
        let newBalance = balance + amount
        defaults.set(newBalance, forKey: balanceKey)

        let transaction = Transaction(
            type: .topup,
            amount: amount
        )
        transactionRepository.record(transaction)

        onBalanceChanged?(newBalance)
    }

    // MARK: - Validation

    func canAfford(_ amount: Double) -> Bool {
        balance >= amount
    }
}
