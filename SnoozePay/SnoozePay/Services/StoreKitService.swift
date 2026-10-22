import StoreKit
import Foundation
import UserNotifications
import os

/// Manages consumable In-App Purchases using StoreKit 2.
/// Five package SKUs; verified transactions determine the paid amount/currency.
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

    // Legacy RUB nominals: fallback only for an absent price with explicit RUB currency.
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

    /// userInfo[`amountUserInfoKey`]: `Double` — amount credited in the wallet currency.
    static let purchaseCompletedNotification = Notification.Name("snoozepay.storekit.purchaseCompleted")
    static let amountUserInfoKey = "amount"

    /// userInfo[`messageUserInfoKey`]: `String` — user-facing error description.
    static let purchaseFailedNotification = Notification.Name("snoozepay.storekit.purchaseFailed")
    static let messageUserInfoKey = "message"

    /// Fired when a purchase enters Ask-to-Buy / SCA verification.
    /// Resolves later via `Transaction.updates` once parent approves. No userInfo.
    static let purchasePendingNotification = Notification.Name("snoozepay.storekit.purchasePending")

    /// Terminal App Store cancellation. No credit, error, or userInfo.
    static let purchaseCancelledNotification = Notification.Name("snoozepay.storekit.purchaseCancelled")

    /// User-facing copy posted via `purchaseFailedNotification` when StoreKit
    /// reports success but `BalanceService.topUp` returns `false` (ledger locked
    /// / record failed). Surfaced as a constant so tests can assert without
    /// hard-coding the same Russian string in two places. See #115.
    ///
    /// Computed rather than stored, like its two neighbours — for a narrower
    /// reason than it looks. A stored `static let` caches its first lookup for
    /// the lifetime of the process, which is a second cache in front of the one
    /// `Localized` already keeps; dropping it leaves `Localized.bundle` as the
    /// single place #596 has to touch when it collapses that bundle to `.main`,
    /// at which point the computed form is the only correct one.
    ///
    /// It buys nothing at runtime *today*, and must not be read as making this
    /// layer language-switchable. There is no runtime language switch, and it
    /// is blocked a level below regardless: `Localized.bundle` is a lazy
    /// `static let` resolved once per process, and `AppLocale.display` is
    /// hardcoded to `ru_RU`.
    static var ledgerLockedFailureMessage: String { Localized.text("deposit.error.credit_failed") }

    /// User-facing copy when the dedup table is in a degraded (type-drifted)
    /// state and we refuse to process new transactions to avoid a double-credit
    /// (#209). Surfaced as a constant so tests can assert it.
    static var degradedDedupFailureMessage: String { Localized.text("deposit.error.dedup_degraded") }

    /// User-facing copy when a verified purchase arrives in a currency the
    /// wallet does not hold (#563). The top-up screens refuse such a purchase
    /// before it starts (`ForeignCurrencyNotice`), so reaching this means the
    /// transaction came from outside that gate — an Ask-to-Buy approval or a
    /// restore that resolved after the storefront changed.
    static var foreignCurrencyFailureMessage: String { Localized.text("deposit.error.foreign_currency") }

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

    #if DEBUG
    /// `-uitour-storekit-empty` — DEBUG-only launch argument that pins the
    /// catalogue empty for the whole session: `loadProducts()` returns without
    /// ever calling `Product.products(for:)`.
    ///
    /// Exists because an E2E test must not be a function of whether the App
    /// Store answered the runner (#575, and #557 before it). Every top-up call
    /// site — no-balance CTA, firing top-up sheet, deposit sheet — branches on
    /// `products.first(where:)` and falls back to a local `BalanceService.topUp`
    /// under `#if DEBUG` when the SKU is missing. Before the app moved to its
    /// real ASC bundle ID that fallback was reached by accident (no matching
    /// app → nothing resolved); afterwards the catalogue resolved on CI, the
    /// real `purchase(_:)` ran, and the simulator put up a "Sign in to Apple
    /// Account" dialog that no test can satisfy. This flag makes the fallback
    /// branch a stated precondition instead of a lucky one.
    ///
    /// Boolean `-uitour-…` flag in the style of `-uitour-reset` / `-uitour-seed`
    /// (see `UITourLauncher`). DEBUG-only on purpose: a release build has no way
    /// to express it, so the no-transaction credit path stays unreachable there.
    static let emptyCatalogArgument = "-uitour-storekit-empty"

    /// Pure form of the flag check, so a unit test can pin BOTH directions —
    /// that the flag forces the empty catalogue, and that its absence leaves
    /// the normal load path untouched.
    static func isCatalogForcedEmpty(arguments: [String]) -> Bool {
        arguments.contains(emptyCatalogArgument)
    }
    #endif

    func loadProducts() async {
        #if DEBUG
        if Self.isCatalogForcedEmpty(arguments: ProcessInfo.processInfo.arguments) {
            AppLogger.storeKit.notice(
                "catalogue load skipped — \(Self.emptyCatalogArgument, privacy: .public) present (UI test)"
            )
            products = []
            postProductsLoaded(products)
            return
        }
        #endif
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
            postPurchaseFailed(Localized.text("deposit.error.products_load_failed"))
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            try await handlePurchaseResult(result)
        } catch {
            AppLogger.storeKit.error(
                "purchase failed: \(String(describing: error), privacy: .public)"
            )
            postPurchaseFailed(error.localizedDescription)
        }
    }

    /// Separate result dispatch lets tests exercise real terminal/nonterminal branches
    /// without constructing an App Store product. Verification and credit are unchanged.
    func handlePurchaseResult(_ result: Product.PurchaseResult) async throws {
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await applyVerifiedPurchase(RestorableTopUp(transaction: transaction)) {
                await transaction.finish()
            }

        case .userCancelled:
            NotificationCenter.default.post(name: Self.purchaseCancelledNotification, object: self)

        case .pending:
            // Ask-to-Buy or SCA — resolved later via Transaction.updates listener.
            postPurchasePending()

        @unknown default:
            AppLogger.storeKit.error("unknown PurchaseResult case — likely future StoreKit addition")
            postPurchaseFailed(Localized.text("deposit.error.unknown_result"))
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
            // Keep unknown background SKUs pending for a build that supports them.
            guard Self.productAmounts[transaction.productID] != nil else {
                AppLogger.storeKit.error(
                    "unknown productID \(transaction.productID, privacy: .public) tx=\(transaction.id, privacy: .private) — not finishing"
                )
                postPurchaseFailed(Localized.text("deposit.error.unknown_product"))
                return
            }
            await applyVerifiedPurchase(RestorableTopUp(transaction: transaction)) {
                await transaction.finish()
            }

        case .unverified(let transaction, let error):
            // Don't finish — let Apple retry next launch. Verification can fail temporarily
            // (clock drift, cert refresh). Finishing here would discard a potentially valid
            // purchase. WWDC sample code (Fruta, Backyard Birds) follows this pattern too.
            let errDesc = error.localizedDescription
            AppLogger.storeKit.error(
                "unverified tx=\(transaction.id, privacy: .private) productID=\(transaction.productID, privacy: .public) error=\(errDesc, privacy: .public)"
            )
            postPurchaseFailed(Localized.text("deposit.error.verification_failed"))
        }
    }

    // MARK: - Crediting a verified purchase

    /// Shared by foreground purchase and updates. Metadata is validated before
    /// dedup writes; `finish` runs only after credit or an already-processed replay.
    /// Plain transaction data and an injected wallet make this money boundary testable.
    func applyVerifiedPurchase(
        _ transaction: RestorableTopUp,
        balance: BalanceService = .shared,
        finish: () async -> Void
    ) async {
        guard let currency = transaction.currency,
              let amount = Self.creditAmount(
                for: transaction.productID, transactionPrice: transaction.transactionPrice, currency: currency
              ) else {
            AppLogger.storeKit.error(
                "invalid paid metadata tx=\(transaction.transactionID, privacy: .private) — not crediting, not finishing"
            )
            postPurchaseFailed(Self.ledgerLockedFailureMessage)
            return
        }
        switch markProcessed(transactionID: transaction.transactionID) {
        case .alreadyProcessed:
            await finish()
            return
        case .degraded:
            postPurchaseFailed(Self.degradedDedupFailureMessage)
            return
        case .recorded:
            break
        }
        guard creditVerifiedPurchase(amount: amount, currency: currency,
                                     transaction: transaction, balance: balance) else {
            return
        }
        await finish()
        postPurchaseCompleted(amount, currency: currency)
    }

    /// Credits a verified paid transaction and, if this is the wallet's first
    /// one, establishes the wallet currency from `Transaction.currency` (#563).
    ///
    /// Returns `false` when nothing was credited. In that case the dedup mark
    /// has been rolled back and the failure surfaced, and the caller must NOT
    /// `finish()` — money has already been collected by Apple, so the
    /// transaction is left in the queue rather than discarded. Both credit
    /// paths (foreground purchase and the `Transaction.updates` listener) go
    /// through here so they cannot drift apart.
    private func creditVerifiedPurchase(
        amount: Double,
        currency: Currency,
        transaction: RestorableTopUp,
        balance: BalanceService
    ) -> Bool {
        switch balance.topUpFromPurchase(amount: amount, currency: currency) {
        case .credited:
            return true

        case .refusedCurrency(let wallet, let purchase):
            // The top-up screens refuse a foreign-currency purchase before it
            // starts, so this is the residue: a deferred approval or restore
            // that resolved after the storefront changed. Crediting the bare
            // number would book `purchase` money as `wallet` money (#558).
            unmarkProcessed(transactionID: transaction.transactionID)
            AppLogger.storeKit.fault(
                """
                tx=\(transaction.transactionID, privacy: .private) paid in \(purchase.code, privacy: .public) \
                but wallet holds \(wallet.code, privacy: .public) — not crediting, not finishing
                """
            )
            postPurchaseFailed(Self.foreignCurrencyFailureMessage)
            return false

        case .notRecorded:
            // Ledger locked / record() failed — money already collected by
            // Apple. Roll back the dedup mark and don't finish, so StoreKit
            // replays the transaction on next launch (another shot at
            // crediting). Surface to the user immediately.
            unmarkProcessed(transactionID: transaction.transactionID)
            AppLogger.storeKit.error(
                """
                topUp failed tx=\(transaction.transactionID, privacy: .private) \
                pid=\(transaction.productID, privacy: .public) — not finishing
                """
            )
            postPurchaseFailed(Self.ledgerLockedFailureMessage)
            return false
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
    func postPurchaseCompleted(_ amount: Double, currency: Currency) {
        // A mounted screen handles the in-app banner. If none is mounted the
        // broadcast is lost — fall back to a local notification so a deferred
        // approval / restore credited in the background is never silent (#45).
        guard hasPurchaseFeedbackSubscriber else {
            let credited = MoneyFormatter.string(amount, currency: currency)
            postLocalFeedbackNotification(
                title: Localized.text("deposit.notification.credited.title"),
                body: Localized.format("deposit.notification.credited.body", credited)
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
            postLocalFeedbackNotification(title: Localized.text("deposit.notification.failed.title"), body: message)
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
        AppLogger.storeKit.notice(
            "deferred purchase feedback — no screen mounted, posting local notification"
        )
        // The banner's prefix is what lets `AppDelegate.willPresent` show this
        // in the foreground instead of dropping it as a bad alarm payload (#842).
        // A refused add used to vanish without a line (#844). It goes through
        // `emit` so `StoreKitServiceTests` can read it back.
        notificationPoster.postAppBanner(.purchaseFeedback, content: content, trigger: nil) { error in
            AppLogger.emit(
                .storeKit, .fault,
                "deferred purchase feedback banner failed: \(error.localizedDescription)"
            )
        }
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
    ///
    /// `internal` because `TopUpRestoreService` (#364) shares this exact dedup
    /// table — it must be able to roll a mark back for the same reason this
    /// path does, and a restore that owned its own table would not deduplicate
    /// against purchases at all.
    func unmarkProcessed(transactionID: UInt64) {
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

    /// Never infer historical paid money from Product or the current storefront.
    /// A present but invalid price cannot fall back to a SKU nominal (#939).
    static func creditAmount(
        for productID: String,
        transactionPrice: Decimal?,
        currency: Currency?
    ) -> Double? {
        guard let currency else { return nil }
        guard let transactionPrice else {
            return currency == .rub ? productAmounts[productID] : nil
        }
        // Parse exact decimal text once. doubleValue can land one ULP below
        // the nearest Double (2.99), making an equal snooze price unaffordable.
        guard !transactionPrice.isNaN,
              let amount = Double(NSDecimalNumber(decimal: transactionPrice).stringValue),
              amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    /// Static RUB catalogue used by existing presentation callers. It is a
    /// paid-credit fallback only when a verified RUB transaction has no price.
    static func catalogAmount(for productID: String) -> Int? {
        productAmounts[productID].map { Int($0) }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
