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

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Double,
        alarmID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.alarmID = alarmID
        self.createdAt = createdAt
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
