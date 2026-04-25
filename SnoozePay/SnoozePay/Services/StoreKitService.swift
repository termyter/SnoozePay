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

    /// Persisted set of transaction IDs that have already been credited. Prevents
    /// double-credit when StoreKit replays an unfinished transaction on next launch.
    private static let processedTxKey = "storekit.processed_tx_ids"

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
            products = loaded.sorted { $0.price < $1.price }
            onProductsLoaded?(products)
        } catch {
            print("[StoreKit] product load failed: \(error)")
            onPurchaseFailed?("Не удалось загрузить пакеты пополнения. Проверь интернет-соединение.")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                guard markProcessed(transactionID: transaction.id) else {
                    print("[StoreKit] tx \(transaction.id) already processed — skipping double credit")
                    await transaction.finish()
                    return
                }
                let amount = creditBalance(for: transaction.productID, fallbackPrice: product.price)
                await transaction.finish()
                onPurchaseCompleted?(amount)

            case .userCancelled:
                break

            case .pending:
                // Ask-to-Buy or SCA — resolved later via Transaction.updates listener.
                onPurchasePending?()

            @unknown default:
                print("[StoreKit] unknown PurchaseResult case — likely future StoreKit addition")
                onPurchaseFailed?("Покупка не выполнена. Обнови приложение и попробуй ещё раз.")
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
            // Revoked (refund / family-share removal): log audit trail, don't re-credit,
            // do finish so it stops being delivered. For consumables we cannot reverse
            // a spent balance — track this as a known limitation (see #22-style follow-up).
            guard transaction.revocationDate == nil else {
                print("[StoreKit] revoked tx \(transaction.id) productID=\(transaction.productID)")
                await transaction.finish()
                return
            }
            // Idempotency — guard against StoreKit replaying a transaction we already
            // credited (e.g. if the previous run crashed between topUp and finish()).
            guard markProcessed(transactionID: transaction.id) else {
                print("[StoreKit] tx \(transaction.id) already processed — finishing without re-credit")
                await transaction.finish()
                return
            }
            // Unknown productID in background listener: do NOT finish — leave for retry.
            // Finishing would silently lose the user's money since fallbackPrice is nil here.
            let amount = Self.creditAmount(for: transaction.productID, fallbackPrice: nil)
            guard amount > 0 else {
                print("[StoreKit] unknown productID \(transaction.productID) tx=\(transaction.id) — not finishing")
                onPurchaseFailed?("Неизвестный пакет пополнения. Обнови приложение.")
                return
            }
            BalanceService.shared.topUp(amount: amount)
            await transaction.finish()
            onPurchaseCompleted?(amount)

        case .unverified(let transaction, let error):
            // Don't finish — let Apple retry next launch. Verification can fail temporarily
            // (clock drift, cert refresh). Finishing here would discard a potentially valid
            // purchase. WWDC sample code (Fruta, Backyard Birds) follows this pattern too.
            print("[StoreKit] unverified tx=\(transaction.id) productID=\(transaction.productID) error=\(error)")
            onPurchaseFailed?("Не удалось проверить чек покупки. Если деньги списаны — напиши в поддержку.")
        }
    }

    // MARK: - Idempotency

    /// Returns true if this transaction is new (recorded for the first time);
    /// false if it was already processed in a previous app session.
    private func markProcessed(transactionID: UInt64) -> Bool {
        let defaults = UserDefaults.standard
        var processed = Set(defaults.array(forKey: Self.processedTxKey) as? [UInt64] ?? [])
        guard !processed.contains(transactionID) else { return false }
        processed.insert(transactionID)
        defaults.set(Array(processed), forKey: Self.processedTxKey)
        return true
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
