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
}
