import Foundation

/// Type of balance transaction
enum TransactionType: String, Codable {
    case topup = "topup"
    case charge = "charge"
}

/// Domain model for a balance transaction
struct Transaction: Identifiable, Codable {
    let id: UUID
    let type: TransactionType
    let amount: Double
    let alarmID: String?
    let createdAt: Date
    /// When this transaction is a `topup` posted to offset a failed snooze
    /// schedule, points back at the original `charge` so stats consumers can
    /// exclude both rows from snooze counts / streak resets (issue #133).
    /// `nil` for organic top-ups and for legacy ledger entries written before
    /// the field existed — those continue to count as real charges/top-ups.
    let refundsTransactionID: UUID?

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Double,
        alarmID: String? = nil,
        createdAt: Date = Date(),
        refundsTransactionID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.alarmID = alarmID
        self.createdAt = createdAt
        self.refundsTransactionID = refundsTransactionID
    }

    var formattedAmount: String {
        let prefix = type == .charge ? "-" : "+"
        return "\(prefix)\(Int(amount)) ₽"
    }

    // MARK: - Typed views (phase 1 of #31)

    /// Typed view of the transaction amount. `nil` if the legacy `Double`
    /// is negative or non-finite — old data may have leaked such values
    /// since the primitive API never validated.
    var money: Money? {
        Money(amount)
    }
}
