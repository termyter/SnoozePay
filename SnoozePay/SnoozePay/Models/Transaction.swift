import Foundation

/// Type of balance transaction.
///
/// `topup` is reserved for IAP / paid-money credits that flow through Apple's
/// StoreKit pipeline — Statistics revenue accounting and any future receipt-
/// reconciliation logic keys off this case. `promotion` covers free credits
/// granted by in-app marketing flows (referrals, daily bonuses, etc.) so they
/// stay segregated from purchases the user actually paid for. `charge` is a
/// debit (snooze penalty).
enum TransactionType: String, Codable {
    case topup
    case charge
    case promotion
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
