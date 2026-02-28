import StoreKit
import Foundation

/// Manages consumable In-App Purchases using StoreKit 2.
/// Five fixed packages: 49, 149, 299, 499, 999 RUB.
@MainActor
final class StoreKitService {

    static let shared = StoreKitService()

    // Product IDs — must match App Store Connect configuration
    static let productIDs = [
        "com.snooze_pay.balance.49",
        "com.snooze_pay.balance.149",
        "com.snooze_pay.balance.299",
        "com.snooze_pay.balance.499",
        "com.snooze_pay.balance.999"
    ]

    // Corresponding RUB amounts to credit
    static let productAmounts: [String: Double] = [
        "com.snooze_pay.balance.49": 49,
        "com.snooze_pay.balance.149": 149,
        "com.snooze_pay.balance.299": 299,
        "com.snooze_pay.balance.499": 499,
        "com.snooze_pay.balance.999": 999
    ]

    private(set) var products: [Product] = []
    var onProductsLoaded: (([Product]) -> Void)?
    var onPurchaseCompleted: ((Double) -> Void)?
    var onPurchaseFailed: ((String) -> Void)?

    private init() {}

    // MARK: - Load products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Set(StoreKitService.productIDs))
            // Sort by price ascending
            products = loaded.sorted { $0.price < $1.price }
            onProductsLoaded?(products)
        } catch {
            print("StoreKit product load error: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // Credit balance
                let amount = StoreKitService.productAmounts[product.id] ?? product.price.doubleValue
                BalanceService.shared.topUp(amount: amount)
                await transaction.finish()
                onPurchaseCompleted?(amount)

            case .userCancelled:
                break

            case .pending:
                // Transaction is pending (e.g., Ask to Buy). Handle later.
                break

            @unknown default:
                break
            }
        } catch {
            onPurchaseFailed?(error.localizedDescription)
        }
    }

    // MARK: - Verify transaction

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}

// MARK: - Decimal to Double helper

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
