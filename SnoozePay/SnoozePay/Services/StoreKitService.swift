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

    // MARK: - Notification names
    //
    // Multi-observer broadcast replaces the old single-slot closure properties.
    // Each observer registers via `NotificationCenter.default.addObserver(...)`,
    // stores its token, and removes it in `deinit`.

    /// userInfo[`productsUserInfoKey`]: `[Product]`
    static let productsLoadedNotification = Notification.Name("snoozepay.storekit.productsLoaded")
    static let productsUserInfoKey = "products"

    /// userInfo[`amountUserInfoKey`]: `Double` — RUB credited to the balance.
    static let purchaseCompletedNotification = Notification.Name("snoozepay.storekit.purchaseCompleted")
    static let amountUserInfoKey = "amount"

    /// userInfo[`messageUserInfoKey`]: `String` — user-facing error description.
    static let purchaseFailedNotification = Notification.Name("snoozepay.storekit.purchaseFailed")
    static let messageUserInfoKey = "message"

    /// Fired when a purchase enters Ask-to-Buy / SCA verification.
    /// Resolves later via `Transaction.updates` once parent approves. No userInfo.
    static let purchasePendingNotification = Notification.Name("snoozepay.storekit.purchasePending")

    private(set) var products: [Product] = []

    /// Background listener for `Transaction.updates`. Required by StoreKit 2 to
    /// receive deferred transactions: Ask-to-Buy approvals, refunds, restores
    /// and purchases that completed while the app was not running.
    private var transactionListener: Task<Void, Never>?

    /// Persisted set of transaction IDs that have already been credited. Prevents
    /// double-credit when StoreKit replays an unfinished transaction on next launch.
    /// Stored as `[String]` because UserDefaults does not round-trip `UInt64` cleanly
    /// (plist normalises numerics; `as? [UInt64]` can fail silently and re-enable
    /// double-crediting). Bounded — keeps the most recent N IDs to prevent unbounded
    /// growth in UserDefaults across the lifetime of the install.
    private static let processedTxKey = "storekit.processed_tx_ids"
    private static let processedTxCap = 200

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
            postProductsLoaded(products)
        } catch {
            AppLogger.storeKit.error("product load failed: \(error.localizedDescription, privacy: .public)")
            postPurchaseFailed("Не удалось загрузить пакеты пополнения. Проверь интернет-соединение.")
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
                    AppLogger.storeKit.notice(
                        "tx \(transaction.id, privacy: .private) already processed — skipping double credit"
                    )
                    await transaction.finish()
                    return
                }
                let amount = creditBalance(for: transaction.productID, fallbackPrice: product.price)
                await transaction.finish()
                postPurchaseCompleted(amount)

            case .userCancelled:
                break

            case .pending:
                // Ask-to-Buy or SCA — resolved later via Transaction.updates listener.
                postPurchasePending()

            @unknown default:
                AppLogger.storeKit.error("unknown PurchaseResult case — likely future StoreKit addition")
                postPurchaseFailed("Покупка не выполнена. Обнови приложение и попробуй ещё раз.")
            }
        } catch {
            postPurchaseFailed(error.localizedDescription)
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
                AppLogger.storeKit.notice(
                    "revoked tx \(transaction.id, privacy: .private) productID=\(transaction.productID, privacy: .public)"
                )
                await transaction.finish()
                return
            }
            // Unknown productID in background listener: do NOT finish AND do NOT mark
            // as processed — leave for retry after app update. Finishing would silently
            // lose the user's money since fallbackPrice is nil here. Marking processed
            // would poison the dedup table: on next launch the replay would be matched
            // by the idempotency guard and finish() called below, also losing the money.
            // Order matters — check amount before markProcessed.
            let amount = Self.creditAmount(for: transaction.productID, fallbackPrice: nil)
            guard amount > 0 else {
                AppLogger.storeKit.error(
                    "unknown productID \(transaction.productID, privacy: .public) tx=\(transaction.id, privacy: .private) — not finishing"
                )
                postPurchaseFailed("Неизвестный пакет пополнения. Обнови приложение.")
                return
            }
            // Idempotency — guard against StoreKit replaying a transaction we already
            // credited (e.g. if the previous run crashed between topUp and finish()).
            guard markProcessed(transactionID: transaction.id) else {
                AppLogger.storeKit.notice(
                    "tx \(transaction.id, privacy: .private) already processed — finishing without re-credit"
                )
                await transaction.finish()
                return
            }
            BalanceService.shared.topUp(amount: amount)
            await transaction.finish()
            postPurchaseCompleted(amount)

        case .unverified(let transaction, let error):
            // Don't finish — let Apple retry next launch. Verification can fail temporarily
            // (clock drift, cert refresh). Finishing here would discard a potentially valid
            // purchase. WWDC sample code (Fruta, Backyard Birds) follows this pattern too.
            let errDesc = error.localizedDescription
            AppLogger.storeKit.error(
                "unverified tx=\(transaction.id, privacy: .private) productID=\(transaction.productID, privacy: .public) error=\(errDesc, privacy: .public)"
            )
            postPurchaseFailed("Не удалось проверить чек покупки. Если деньги списаны — напиши в поддержку.")
        }
    }

    // MARK: - Notification posting helpers

    private func postProductsLoaded(_ products: [Product]) {
        NotificationCenter.default.post(
            name: Self.productsLoadedNotification,
            object: self,
            userInfo: [Self.productsUserInfoKey: products]
        )
    }

    private func postPurchaseCompleted(_ amount: Double) {
        NotificationCenter.default.post(
            name: Self.purchaseCompletedNotification,
            object: self,
            userInfo: [Self.amountUserInfoKey: amount]
        )
    }

    private func postPurchaseFailed(_ message: String) {
        NotificationCenter.default.post(
            name: Self.purchaseFailedNotification,
            object: self,
            userInfo: [Self.messageUserInfoKey: message]
        )
    }

    private func postPurchasePending() {
        NotificationCenter.default.post(
            name: Self.purchasePendingNotification,
            object: self
        )
    }

    // MARK: - Idempotency

    /// Returns true if this transaction is new (recorded for the first time);
    /// false if it was already processed in a previous app session.
    ///
    /// Storage is `[String]` (not `[UInt64]`) because UserDefaults plist storage
    /// silently fails the `as? [UInt64]` cast in some cases — a nil cast result
    /// would reset the set and re-enable double-crediting. Strings round-trip safely.
    /// We keep insertion order (Array, not Set) so we can trim the oldest IDs once
    /// the cap is exceeded, keeping UserDefaults bounded.
    private func markProcessed(transactionID: UInt64) -> Bool {
        let defaults = UserDefaults.standard
        let key = Self.processedTxKey
        let idString = String(transactionID)
        var processed = (defaults.array(forKey: key) as? [String]) ?? []
        guard !processed.contains(idString) else { return false }
        processed.append(idString)
        if processed.count > Self.processedTxCap {
            processed = Array(processed.suffix(Self.processedTxCap))
        }
        defaults.set(processed, forKey: key)
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
