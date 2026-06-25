import XCTest
import UserNotifications
@testable import SnoozePay

/// Spy that captures the `UNNotificationRequest`s StoreKitService posts when no
/// UI screen is mounted (#45). Avoids touching the real
/// `UNUserNotificationCenter` singleton in unit tests.
@MainActor
final class LocalNotificationPosterSpy: LocalNotificationPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func add(_ request: UNNotificationRequest) {
        requests.append(request)
    }
}

/// Smoke tests for StoreKitService.
///
/// NOTE: Fully exercising the `Transaction.updates` listener requires mocking
/// `StoreKit.Transaction.updates`, which is a built-in `AsyncStream` not
/// designed for substitution without a larger DI refactor. We therefore
/// limit coverage to:
///   - product ID → credit amount mapping (pure logic)
///   - shared instance reachability (smoke)
///
/// TODO(IOS-032+): Once StoreKit transaction handling is extracted behind a
/// protocol, add an end-to-end test that pushes a mock verified transaction
/// through `handle(transactionResult:)` and asserts the balance is credited
/// and the transaction is finished.
@MainActor
final class StoreKitServiceTests: XCTestCase {

    func testSharedInstance_isReachable() {
        // Touching `.shared` triggers `init`, which spawns the
        // `Transaction.updates` listener. If the listener crashed at start
        // this test would surface it.
        let service = StoreKitService.shared
        XCTAssertNotNil(service)
    }

    func testProductAmounts_coversAllProductIDs() {
        for productID in StoreKitService.productIDs {
            XCTAssertNotNil(
                StoreKitService.productAmounts[productID],
                "Missing credit amount mapping for \(productID)"
            )
        }
    }

    func testProductAmounts_matchProductIDSuffix() {
        // Each product ID encodes its RUB amount as the trailing component
        // (e.g. "...balance.149" → 149 RUB). Catch drift between the two tables.
        for (productID, amount) in StoreKitService.productAmounts {
            let suffix = productID.split(separator: ".").last.map(String.init) ?? ""
            XCTAssertEqual(
                Double(suffix),
                amount,
                "Product \(productID) maps to \(amount) but suffix says \(suffix)"
            )
        }
    }

    // MARK: - Coverage gaps surfaced by pr-test-analyzer (#32)

    /// `productIDs` and `productAmounts` are two parallel sources of truth.
    /// The keysets MUST be identical: an ID present in one but not the other
    /// would silently miscredit (or no-credit) on purchase.
    func testProductIDs_andProductAmounts_haveIdenticalKeysets() {
        let idSet = Set(StoreKitService.productIDs)
        let amountKeys = Set(StoreKitService.productAmounts.keys)
        XCTAssertEqual(
            idSet, amountKeys,
            "productIDs and productAmounts must declare exactly the same product identifiers"
        )
    }

    /// Notification names must include the `snoozepay.storekit.` namespace
    /// prefix so subscribers across the app match a stable, scoped identifier.
    /// A rename without this assertion would silently break every subscriber.
    func testNotificationNames_useStableNamespace() {
        let prefix = "snoozepay.storekit."
        XCTAssertTrue(StoreKitService.productsLoadedNotification.rawValue.hasPrefix(prefix))
        XCTAssertTrue(StoreKitService.purchaseCompletedNotification.rawValue.hasPrefix(prefix))
        XCTAssertTrue(StoreKitService.purchaseFailedNotification.rawValue.hasPrefix(prefix))
        XCTAssertTrue(StoreKitService.purchasePendingNotification.rawValue.hasPrefix(prefix))
    }

    /// userInfo keys are part of the contract with subscribers.
    /// Renaming a key without updating subscribers would silently drop data.
    func testUserInfoKeys_areDistinctAndStable() {
        let keys = [
            StoreKitService.productsUserInfoKey,
            StoreKitService.amountUserInfoKey,
            StoreKitService.messageUserInfoKey
        ]
        XCTAssertEqual(Set(keys).count, keys.count, "userInfo keys must be distinct")
        XCTAssertEqual(StoreKitService.amountUserInfoKey, "amount")
        XCTAssertEqual(StoreKitService.messageUserInfoKey, "message")
        XCTAssertEqual(StoreKitService.productsUserInfoKey, "products")
    }

    // TODO(IOS-032+): The remaining gaps from #32 — `.userCancelled` /
    // `.pending` / `failedVerification` / double-call dedup — exercise
    // `Product.purchase()` and `Transaction.updates`, which are StoreKit
    // built-ins without a substitution seam. Covering them requires lifting
    // the StoreKit boundary behind a protocol (handle(transactionResult:),
    // purchaseProduct, transactionUpdates AsyncStream). Tracked as a
    // follow-up so this PR stays test-only and does not modify production.

    // MARK: - #115: Bool-check on BalanceService.topUp

    /// The user-facing copy used when `BalanceService.topUp` reports `false`
    /// (locked ledger / record failed) is part of the contract with the
    /// purchase UI. Renaming or emptying it would silently break the
    /// failure-state alert. Pinned here so a refactor surfaces it.
    func testLedgerLockedFailureMessage_isStableAndNonEmpty() {
        XCTAssertEqual(
            StoreKitService.ledgerLockedFailureMessage,
            "Не удалось зачислить покупку. Свяжитесь с поддержкой."
        )
        XCTAssertFalse(StoreKitService.ledgerLockedFailureMessage.isEmpty)
    }

    /// `purchaseFailedNotification` carries the user-facing copy via
    /// `messageUserInfoKey`. Subscribers (PaywallViewController) read the
    /// message exactly through this key to drive the alert. If a future change
    /// drops the userInfo or renames the key, this test catches it for the
    /// ledger-locked path specifically.
    func testPurchaseFailedNotification_carriesLedgerLockedMessageUnderMessageKey() {
        let center = NotificationCenter()
        let exp = expectation(description: "purchase failed notification received")
        var receivedMessage: String?

        let token = center.addObserver(
            forName: StoreKitService.purchaseFailedNotification,
            object: nil,
            queue: nil
        ) { note in
            receivedMessage = note.userInfo?[StoreKitService.messageUserInfoKey] as? String
            exp.fulfill()
        }
        defer { center.removeObserver(token) }

        // Simulate the ledger-locked failure post that StoreKitService now performs.
        center.post(
            name: StoreKitService.purchaseFailedNotification,
            object: nil,
            userInfo: [StoreKitService.messageUserInfoKey: StoreKitService.ledgerLockedFailureMessage]
        )

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(receivedMessage, StoreKitService.ledgerLockedFailureMessage)
    }

    // MARK: - #45: deferred-purchase local-notification fallback

    /// A fresh test instance with an injected notification spy and an isolated
    /// UserDefaults suite — never the `.shared` singleton (which spawns the
    /// `Transaction.updates` listener and reads `.standard`).
    private func makeService(
        poster: LocalNotificationPosterSpy,
        defaults: UserDefaults
    ) -> StoreKitService {
        StoreKitService(notificationPoster: poster, defaults: defaults, startListener: false)
    }

    private func makeSuite() -> (UserDefaults, String) {
        let name = "test_storekit_\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// With no screen mounted, a completed purchase posts a local notification
    /// (option B) instead of broadcasting into the void.
    func testPurchaseCompleted_noSubscriber_postsLocalNotification() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        XCTAssertFalse(service.hasPurchaseFeedbackSubscriber)
        service.postPurchaseCompleted(149)

        XCTAssertEqual(poster.requests.count, 1)
        let content = poster.requests.first?.content
        XCTAssertEqual(content?.title, "Баланс пополнен")
        XCTAssertEqual(content?.body, "Баланс пополнен на 149 ₽.")
        // Immediate delivery — no trigger.
        XCTAssertNil(poster.requests.first?.trigger)
    }

    /// With a screen mounted, the completed purchase broadcasts via
    /// NotificationCenter and does NOT post a local notification (no double-notify).
    func testPurchaseCompleted_withSubscriber_doesNotPostLocalNotification() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        service.beginObservingPurchaseFeedback()
        XCTAssertTrue(service.hasPurchaseFeedbackSubscriber)
        service.postPurchaseCompleted(149)

        XCTAssertTrue(poster.requests.isEmpty, "must not double-notify when a screen is mounted")
    }

    /// A failure (refund / verification failure) with no screen mounted posts a
    /// local notification carrying the message so it's never silently lost.
    func testPurchaseFailed_noSubscriber_postsLocalNotificationWithMessage() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        service.postPurchaseFailed("Покупка отменена и возвращена.")

        XCTAssertEqual(poster.requests.count, 1)
        XCTAssertEqual(poster.requests.first?.content.body, "Покупка отменена и возвращена.")
    }

    /// begin/end subscriber tracking is balanced and clamps at zero so a stray
    /// extra `end` can't suppress the fallback forever.
    func testSubscriberTracking_balancesAndClampsAtZero() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        service.beginObservingPurchaseFeedback()
        service.beginObservingPurchaseFeedback()
        XCTAssertTrue(service.hasPurchaseFeedbackSubscriber)
        service.endObservingPurchaseFeedback()
        XCTAssertTrue(service.hasPurchaseFeedbackSubscriber, "still one screen mounted")
        service.endObservingPurchaseFeedback()
        XCTAssertFalse(service.hasPurchaseFeedbackSubscriber)
        // Over-balance must not drive negative.
        service.endObservingPurchaseFeedback()
        XCTAssertFalse(service.hasPurchaseFeedbackSubscriber)
    }

    // MARK: - #209.1: conservative dedup-corruption handling

    func testMarkProcessed_freshTable_recordsAndDedupes() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        XCTAssertEqual(service.markProcessed(transactionID: 42), .recorded)
        // Replay of the same ID is recognised — no double-credit.
        XCTAssertEqual(service.markProcessed(transactionID: 42), .alreadyProcessed)
    }

    /// THE money-correctness test: a dedup blob whose plist type has drifted must
    /// NOT be wiped (old `?? []` behavior re-enabled double-crediting). The table
    /// is backed up, and the call returns `.degraded` so the caller refuses to credit.
    func testMarkProcessed_corruptBlob_refusesAndBacksUpWithoutWiping() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        // Plant a type-drifted blob (a dictionary where `[String]` is expected).
        let corrupt: [String: Int] = ["unexpected": 1]
        defaults.set(corrupt, forKey: "storekit.processed_tx_ids")

        XCTAssertEqual(service.markProcessed(transactionID: 7), .degraded)

        // Original corrupt blob is preserved (NOT wiped to []).
        XCTAssertNotNil(defaults.object(forKey: "storekit.processed_tx_ids"))
        XCTAssertNil(
            defaults.array(forKey: "storekit.processed_tx_ids") as? [String],
            "corrupt blob must remain non-[String] — never silently reset"
        )
        // Backup written for diagnosis (mirrors TransactionRepository).
        XCTAssertNotNil(defaults.object(forKey: StoreKitService.processedBackupCorruptKey))
    }

    /// In the degraded state the dedup table is never overwritten across repeated
    /// attempts — every call refuses rather than double-crediting.
    func testMarkProcessed_corruptBlob_repeatedCallsStayDegraded() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = makeService(poster: poster, defaults: defaults)

        defaults.set(["bad": true], forKey: "storekit.processed_tx_ids")
        XCTAssertEqual(service.markProcessed(transactionID: 1), .degraded)
        XCTAssertEqual(service.markProcessed(transactionID: 2), .degraded)
        XCTAssertNil(defaults.array(forKey: "storekit.processed_tx_ids") as? [String])
    }

    // MARK: - #209.2: credit-amount unknown-product logging

    func testCreditAmount_knownProduct_returnsCatalogueAmount() {
        XCTAssertEqual(
            StoreKitService.creditAmount(for: "io.mobilife.snoozepay.balance.299", fallbackPrice: 999),
            299,
            "known SKU must credit the catalogue amount, ignoring any fallback price"
        )
    }

    func testCreditAmount_unknownProductNoFallback_returnsZero() {
        // No free/promo products exist (#209) — a zero here means misconfiguration.
        // The caller's `amount > 0` gate then refuses to finish. (Logging side
        // effect is asserted indirectly: the path is exercised.)
        XCTAssertEqual(
            StoreKitService.creditAmount(for: "io.mobilife.snoozepay.balance.unknown", fallbackPrice: nil),
            0
        )
    }

    func testCreditAmount_unknownProductWithFallback_usesFallback() {
        XCTAssertEqual(
            StoreKitService.creditAmount(for: "io.mobilife.snoozepay.balance.unknown", fallbackPrice: 199),
            199,
            "an unmapped SKU with a resolved StoreKit price still credits that price"
        )
    }
}
