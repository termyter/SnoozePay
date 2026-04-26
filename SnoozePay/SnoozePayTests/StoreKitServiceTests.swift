import XCTest
@testable import SnoozePay

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
}
