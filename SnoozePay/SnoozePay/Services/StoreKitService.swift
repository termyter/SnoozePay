import StoreKit
import Foundation
import UserNotifications
import os

/// Minimal seam for posting an immediate local notification. Extracted so the
/// deferred-purchase fallback (#45) can be unit-tested without bringing up the
/// process-wide `UNUserNotificationCenter` singleton. Production uses
/// `UNUserNotificationCenter.current()`; tests inject a spy.
@MainActor
protocol LocalNotificationPosting {
    func add(_ request: UNNotificationRequest)
}

extension UNUserNotificationCenter: LocalNotificationPosting {
    nonisolated func add(_ request: UNNotificationRequest) {
        add(request, withCompletionHandler: nil)
    }
}

/// Manages consumable In-App Purchases using StoreKit 2.
/// Five fixed packages: 49, 149, 299, 499, 999 RUB.
@MainActor
final class StoreKitService {

    static let shared = StoreKitService()

    // Product IDs — must match App Store Connect configuration
    static let productIDs = [
        "io.mobilife.snoozepay.balance.49",
        "io.mobilife.snoozepay.balance.149",
        "io.mobilife.snoozepay.balance.299",
        "io.mobilife.snoozepay.balance.499",
        "io.mobilife.snoozepay.balance.999"
    ]

    // Corresponding RUB amounts to credit
    static let productAmounts: [String: Double] = [
        "io.mobilife.snoozepay.balance.49": 49,
        "io.mobilife.snoozepay.balance.149": 149,
        "io.mobilife.snoozepay.balance.299": 299,
        "io.mobilife.snoozepay.balance.499": 499,
        "io.mobilife.snoozepay.balance.999": 999
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

    /// User-facing copy posted via `purchaseFailedNotification` when StoreKit
    /// reports success but `BalanceService.topUp` returns `false` (ledger locked
    /// / record failed). Surfaced as a constant so tests can assert without
    /// hard-coding the same Russian string in two places. See #115.
    static let ledgerLockedFailureMessage = "Не удалось зачислить покупку. Свяжитесь с поддержкой."

    /// User-facing copy when the dedup table is in a degraded (type-drifted)
    /// state and we refuse to process new transactions to avoid a double-credit
    /// (#209). Surfaced as a constant so tests can assert it.
    static let degradedDedupFailureMessage =
        "Не удалось обработать покупку. Перезапустите приложение или свяжитесь с поддержкой."

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

    /// Backup key for a dedup blob whose plist type has drifted (#209). When the
    /// stored value exists but is no longer `[String]`, we copy it here (once)
    /// for diagnosis instead of silently overwriting it — mirrors
    /// `TransactionRepository.corruptBackupKey`.
    static let processedBackupCorruptKey = "stored_processed_backup_corrupt"

    /// Number of UI screens currently subscribed to purchase-feedback
    /// notifications (Deposit / Firing top-up sheets). When zero, a deferred
    /// purchase result (Ask-to-Buy approval, refund, restore, verification
    /// failure) would broadcast into the void — so we post a local notification
    /// instead so the feedback is never silently lost (#45). Screens bump this
    /// via `beginObservingPurchaseFeedback()` / `endObservingPurchaseFeedback()`.
    private var purchaseFeedbackSubscribers = 0

    /// Whether any UI screen is currently mounted to receive purchase feedback.
    var hasPurchaseFeedbackSubscriber: Bool { purchaseFeedbackSubscribers > 0 }

    /// Seam for posting the deferred-purchase fallback notification (#45).
    private let notificationPoster: LocalNotificationPosting

    /// Backing store for the dedup table. Injected so tests can drive the
    /// conservative corruption path (#209) against an isolated suite instead of
    /// `.standard`; production uses `.standard`.
    private let defaults: UserDefaults

    /// Identifier prefix for the deferred-purchase fallback notifications so
    /// they can be inspected / cleared as a group if needed.
    private static let feedbackNotificationIDPrefix = "snoozepay.storekit.feedback."

    private init() {
        self.notificationPoster = UNUserNotificationCenter.current()
        self.defaults = .standard
        transactionListener = Self.makeTransactionListener()
        // Fetch the StoreKit catalogue at startup. Without this the `products`
        // array stays empty for the whole session and every top-up path falls
        // back to the (DEBUG-only intended) local credit — the purchase sheet
        // never reaches real StoreKit. `_ = StoreKitService.shared` in
        // AppDelegate triggers this init, so the load kicks off at launch.
        Task { await loadProducts() }
    }

    /// Test-only initializer. Injects the notification + storage seams and skips
    /// spawning the `Transaction.updates` listener (which can't be driven in a
    /// unit test without a StoreKit substitution refactor). Never used in
    /// production — production MUST go through `.shared`.
    init(
        notificationPoster: LocalNotificationPosting,
        defaults: UserDefaults = .standard,
        startListener: Bool = false
    ) {
        self.notificationPoster = notificationPoster
        self.defaults = defaults
        if startListener {
            transactionListener = Self.makeTransactionListener()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Purchase-feedback subscriber tracking (#45)

    /// Register that a UI screen is now observing purchase-feedback
    /// notifications. While at least one screen is registered, purchase results
    /// are delivered only via the NotificationCenter broadcast (no local
    /// notification — avoids double-notifying).
    func beginObservingPurchaseFeedback() {
        purchaseFeedbackSubscribers += 1
    }

    /// Balance a prior `beginObservingPurchaseFeedback()`. Clamped at zero so a
    /// stray extra `end` can't drive the counter negative and suppress the
    /// fallback notification forever.
    func endObservingPurchaseFeedback() {
        purchaseFeedbackSubscribers = max(0, purchaseFeedbackSubscribers - 1)
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
            // `Product.products(for:)` returns the *available* subset and does
            // NOT throw when an ID is simply unavailable (e.g. the Paid Apps
            // agreement isn't active, or the SKU hasn't propagated yet) — it
            // just omits it. Log found/missing so a silent empty result is
            // diagnosable instead of looking like the call never ran.
            let missing = Set(StoreKitService.productIDs)
                .subtracting(loaded.map(\.id))
                .sorted()
            AppLogger.storeKit.notice(
                "loaded \(loaded.count)/\(StoreKitService.productIDs.count) products; missing: \(missing.joined(separator: ", "), privacy: .public)"
            )
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
                // Determine the credit amount BEFORE marking processed. If we
                // can't credit (unknown productID), we must not poison the dedup
                // table — otherwise StoreKit's retry on next launch would silently
                // finish() without crediting (re-enabling the #115 money-loss class).
                let amount = Self.creditAmount(for: transaction.productID, fallbackPrice: product.price)
                guard amount > 0 else {
                    AppLogger.storeKit.error(
                        "unknown productID \(transaction.productID, privacy: .public) tx=\(transaction.id, privacy: .private) — not finishing"
                    )
                    postPurchaseFailed("Неизвестный пакет пополнения. Обнови приложение.")
                    return
                }
                switch markProcessed(transactionID: transaction.id) {
                case .alreadyProcessed:
                    AppLogger.storeKit.notice(
                        "tx \(transaction.id, privacy: .private) already processed — skipping double credit"
                    )
                    await transaction.finish()
                    return
                case .degraded:
                    // Dedup table corrupt — refuse to credit AND don't finish, so
                    // StoreKit replays once the degraded state is recovered (#209).
                    postPurchaseFailed(Self.degradedDedupFailureMessage)
                    return
                case .recorded:
                    break
                }
                guard BalanceService.shared.topUp(amount: amount) else {
                    // Ledger locked / record() failed — money already collected by
                    // Apple. Roll back the dedup mark and DO NOT finish() so StoreKit
                    // replays the transaction on next launch (giving us another shot
                    // at crediting). Surface to the user immediately.
                    unmarkProcessed(transactionID: transaction.id)
                    AppLogger.storeKit.error(
                        "topUp failed tx=\(transaction.id, privacy: .private) pid=\(transaction.productID, privacy: .public)"
                    )
                    postPurchaseFailed(Self.ledgerLockedFailureMessage)
                    return
                }
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
            AppLogger.storeKit.error(
                "purchase failed: \(String(describing: error), privacy: .public)"
            )
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
            switch markProcessed(transactionID: transaction.id) {
            case .alreadyProcessed:
                AppLogger.storeKit.notice(
                    "tx \(transaction.id, privacy: .private) already processed — finishing without re-credit"
                )
                await transaction.finish()
                return
            case .degraded:
                // Dedup table corrupt — refuse to credit AND don't finish, so the
                // deferred transaction replays after recovery (#209). Surface so a
                // background approval/restore failure isn't silent.
                postPurchaseFailed(Self.degradedDedupFailureMessage)
                return
            case .recorded:
                break
            }
            guard BalanceService.shared.topUp(amount: amount) else {
                // Ledger locked / record() failed — money already collected by Apple.
                // Roll back the dedup mark and DO NOT finish() so StoreKit replays
                // the transaction on next launch. Surface to the user immediately.
                unmarkProcessed(transactionID: transaction.id)
                let pid = transaction.productID
                AppLogger.storeKit.error(
                    "topUp failed tx=\(transaction.id, privacy: .private) pid=\(pid, privacy: .public) — not finishing"
                )
                postPurchaseFailed(Self.ledgerLockedFailureMessage)
                return
            }
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

    /// `internal` so #45 fallback tests can drive the no-subscriber path and
    /// assert a local notification is posted. Not public.
    func postPurchaseCompleted(_ amount: Double) {
        // A mounted screen handles the in-app banner. If none is mounted the
        // broadcast is lost — fall back to a local notification so a deferred
        // approval / restore credited in the background is never silent (#45).
        guard hasPurchaseFeedbackSubscriber else {
            let rubles = Int(amount.rounded())
            postLocalFeedbackNotification(
                title: "Баланс пополнен",
                body: "Баланс пополнен на \(rubles) ₽."
            )
            return
        }
        NotificationCenter.default.post(
            name: Self.purchaseCompletedNotification,
            object: self,
            userInfo: [Self.amountUserInfoKey: amount]
        )
    }

    /// `internal` for the same reason as `postPurchaseCompleted` — testable
    /// no-subscriber fallback (#45). Not public.
    func postPurchaseFailed(_ message: String) {
        // Same rationale as `postPurchaseCompleted` — a refund / verification
        // failure arriving with no screen mounted must not vanish silently (#45).
        guard hasPurchaseFeedbackSubscriber else {
            postLocalFeedbackNotification(title: "Покупка пополнения", body: message)
            return
        }
        NotificationCenter.default.post(
            name: Self.purchaseFailedNotification,
            object: self,
            userInfo: [Self.messageUserInfoKey: message]
        )
    }

    /// Schedule an immediate local notification carrying purchase feedback.
    /// Reuses the notification authorization the alarm flow already holds
    /// (`.alert` / `.sound`) — does NOT request a new permission. A `nil`
    /// trigger fires as soon as the system delivers it (#45).
    private func postLocalFeedbackNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.feedbackNotificationIDPrefix + UUID().uuidString,
            content: content,
            trigger: nil
        )
        AppLogger.storeKit.notice(
            "deferred purchase feedback — no screen mounted, posting local notification"
        )
        notificationPoster.add(request)
    }

    private func postPurchasePending() {
        NotificationCenter.default.post(
            name: Self.purchasePendingNotification,
            object: self
        )
    }

    // MARK: - Idempotency

    /// Outcome of attempting to record a transaction in the dedup table (#209).
    enum MarkResult: Equatable {
        /// New transaction — recorded for the first time; proceed to credit.
        case recorded
        /// Already processed in a previous session — skip credit, finish() it.
        case alreadyProcessed
        /// The dedup blob exists but its plist type has drifted (tampering /
        /// schema migration by another build). We refuse to operate: crediting
        /// would risk a double-credit, and overwriting would wipe the table.
        /// Caller must NOT credit and must NOT finish() — leave for retry after
        /// the degraded state is recovered.
        case degraded
    }

    /// Records a transaction in the dedup table.
    ///
    /// Storage is `[String]` (not `[UInt64]`) because UserDefaults plist storage
    /// silently fails the `as? [UInt64]` cast in some cases — a nil cast result
    /// would reset the set and re-enable double-crediting. Strings round-trip safely.
    /// We keep insertion order (Array, not Set) so we can trim the oldest IDs once
    /// the cap is exceeded, keeping UserDefaults bounded.
    ///
    /// CONSERVATIVE corruption handling (#209): if the stored value exists but is
    /// no longer `[String]`, we DO NOT blank the table (the old `?? []` did, which
    /// re-enabled double-crediting). Instead we back the corrupt blob up to
    /// `processedBackupCorruptKey` (once, mirroring `TransactionRepository`), log
    /// it, and return `.degraded` so the caller refuses to credit.
    ///
    /// `internal` (not `private`) so money-correctness unit tests can drive the
    /// recorded / already-processed / degraded outcomes against an injected
    /// `UserDefaults` suite. Not part of the public surface.
    func markProcessed(transactionID: UInt64) -> MarkResult {
        let key = Self.processedTxKey
        let idString = String(transactionID)

        let stored = defaults.object(forKey: key)
        var processed: [String]
        if stored == nil {
            // Brand-new install / table not yet written — legitimate empty state.
            processed = []
        } else if let casted = stored as? [String] {
            processed = casted
        } else {
            // Blob present but its plist type drifted. Refuse — never wipe, never
            // double-credit. Back it up once for diagnosis.
            if defaults.object(forKey: Self.processedBackupCorruptKey) == nil {
                defaults.set(stored, forKey: Self.processedBackupCorruptKey)
            }
            AppLogger.storeKit.error(
                "markProcessed: dedup table corrupt (type drift) — refusing to credit, backed up tx=\(transactionID, privacy: .private)"
            )
            return .degraded
        }

        guard !processed.contains(idString) else { return .alreadyProcessed }
        processed.append(idString)
        if processed.count > Self.processedTxCap {
            processed = Array(processed.suffix(Self.processedTxCap))
        }
        defaults.set(processed, forKey: key)
        return .recorded
    }

    /// Roll back a `markProcessed(transactionID:)` recorded earlier in the same
    /// flow. Used when a downstream step (e.g. `BalanceService.topUp`) fails
    /// AFTER the dedup mark was set — without this rollback the transaction
    /// would look "already processed" on StoreKit's retry replay and finish
    /// silently without crediting (the very money-loss bug #115 is fixing).
    private func unmarkProcessed(transactionID: UInt64) {
        let key = Self.processedTxKey
        let idString = String(transactionID)
        guard var processed = defaults.array(forKey: key) as? [String] else {
            // Dedup table missing or its plist type was reset. Without the mark,
            // a replay of this transaction WILL re-enter `markProcessed` (no-op
            // path) and credit normally — but we lose the audit trail. Logging
            // so future divergence between StoreKit replays and our ledger is
            // diagnosable in Console.
            AppLogger.storeKit.error(
                "unmarkProcessed: dedup table missing/corrupt — replay will silently finish tx=\(transactionID, privacy: .private)"
            )
            return
        }
        processed.removeAll { $0 == idString }
        defaults.set(processed, forKey: key)
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

    static func creditAmount(for productID: String, fallbackPrice: Decimal?) -> Double {
        if let mapped = productAmounts[productID] {
            return mapped
        }
        // Unknown product. We do NOT support free/promo products (#209), so a
        // zero here means a misconfiguration (a SKU added to App Store Connect
        // but not to `productAmounts`). The caller treats 0 as "unknown package"
        // and refuses to finish — log loudly so a future misconfig isn't silent
        // rather than being mistaken for an intentional zero-priced product.
        let resolved = fallbackPrice?.doubleValue ?? 0
        if resolved <= 0 {
            AppLogger.storeKit.error(
                "creditAmount: unknown product \(productID, privacy: .public) resolved to \(resolved, privacy: .public) — no free/promo products exist; likely a missing productAmounts entry"
            )
        }
        return resolved
    }

    // MARK: - Display / catalogue amounts (#275)
    //
    // The amount rendered on a top-up tile or CTA MUST equal the amount the
    // App Store charges AND the amount credited to the ledger. Historically the
    // firing-screen tiles hard-coded rounded literals (200 / 500 / 1000 ₽) that
    // mapped to the 149 / 499 / 999 SKUs — so the user saw 200 ₽ but was charged
    // and credited 149. These helpers make the displayed number derive from the
    // catalogue (and, once loaded, the resolved StoreKit product price) so
    // display == charge == credit for the current catalogue.

    /// The catalogue RUB amount for a SKU (49 / 149 / 299 / 499 / 999), or nil
    /// for an unknown product ID. This is the same value credited on purchase,
    /// so it is the honest number to render when the product list hasn't loaded.
    static func catalogAmount(for productID: String) -> Int? {
        productAmounts[productID].map { Int($0) }
    }

    /// The integer RUB amount to DISPLAY for a SKU. Prefers the resolved
    /// StoreKit product's numeric price (the real charged amount) when the
    /// catalogue has loaded; otherwise falls back to the catalogue amount.
    /// Never returns an invented rounded literal.
    func displayAmount(for productID: String) -> Int? {
        if let product = products.first(where: { $0.id == productID }) {
            return NSDecimalNumber(decimal: product.price).intValue
        }
        return Self.catalogAmount(for: productID)
    }

    enum StoreError: Error {
        case failedVerification
    }
}

// MARK: - Decimal to Double helper

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
