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
    /// Fired when a purchase enters Ask-to-Buy / SCA verification.
    /// Resolves later via `Transaction.updates` once parent approves.
    var onPurchasePending: (() -> Void)?

    /// Background listener for `Transaction.updates`. Required by StoreKit 2 to
    /// receive deferred transactions: Ask-to-Buy approvals, refunds, restores
    /// and purchases that completed while the app was not running.
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = Self.makeTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    private static func makeTransactionListener() -> Task<Void, Never> {
        Task.detached {
            for await result in StoreKit.Transaction.updates {
                await StoreKitService.shared.handle(transactionResult: result)
            }
        }
    }

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
                let amount = creditBalance(for: transaction.productID, fallbackPrice: product.price)
                await transaction.finish()
                onPurchaseCompleted?(amount)

            case .userCancelled:
                break

            case .pending:
                // Ask-to-Buy or SCA — resolved later via Transaction.updates listener.
                onPurchasePending?()

            @unknown default:
                break
            }
        } catch {
            onPurchaseFailed?(error.localizedDescription)
        }
    }

    // MARK: - Transaction.updates handling

    /// Called for every transaction update delivered out-of-band:
    /// deferred Ask-to-Buy approvals, refunds, restores, and purchases
    /// that completed while the app was suspended.
    private func handle(transactionResult: VerificationResult<StoreKit.Transaction>) async {
        switch transactionResult {
        case .verified(let transaction):
            // Skip revoked transactions (refunds / family-share removal):
            // Apple delivers them so we can revoke entitlements, but for
            // consumables we simply finish them — the balance was already spent.
            if transaction.revocationDate == nil {
                let amount = creditBalance(for: transaction.productID, fallbackPrice: nil)
                if amount > 0 {
                    onPurchaseCompleted?(amount)
                }
            }
            await transaction.finish()

        case .unverified(let transaction, let error):
            // Per Apple docs: still finish unverified transactions to drain the queue,
            // but do not credit balance.
            print("StoreKit unverified transaction \(transaction.id): \(error)")
            await transaction.finish()
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

    // MARK: - Helpers

    /// Credits the user's balance for the given product. Returns the credited amount
    /// (0 if the product is unknown and no fallback was provided).
    @discardableResult
    private func creditBalance(for productID: String, fallbackPrice: Decimal?) -> Double {
        let amount = Self.creditAmount(for: productID, fallbackPrice: fallbackPrice)
        guard amount > 0 else { return 0 }
        BalanceService.shared.topUp(amount: amount)
        return amount
    }

    private static func creditAmount(for productID: String, fallbackPrice: Decimal?) -> Double {
        if let mapped = productAmounts[productID] {
            return mapped
        }
        return fallbackPrice?.doubleValue ?? 0
    }

    enum StoreError: Error {
        case failedVerification
    }
}

// MARK: - Decimal to Double helper

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
