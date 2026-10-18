import CoreFoundation
import Foundation

/// Presentation snapshot of an already credited amount, never a selected SKU
/// or the wallet total. Currency is captured from the wallet after credit.
struct TopUpSuccessReceipt {
    let amount: Double
    let currency: Currency

    init?(amount: Double, currency: Currency) {
        guard amount.isFinite, amount > 0 else { return nil }
        self.amount = amount
        self.currency = currency
    }

    init?(eventAmount: Any?, currency: Currency) {
        guard let number = eventAmount as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let amount = eventAmount as? Double else { return nil }
        self.init(amount: amount, currency: currency)
    }
}

/// One scheduling seam for the existing two-second success dismissal.
typealias TopUpSuccessDismissal = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
