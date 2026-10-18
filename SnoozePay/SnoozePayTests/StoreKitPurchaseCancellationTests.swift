import StoreKit
import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class StoreKitPurchaseCancellationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var balance: BalanceService!
    private var store: StoreKitService!
    private var poster: LocalNotificationPosterSpy!

    override func setUp() {
        super.setUp()
        suite = "StoreKitPurchaseCancellationTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        balance = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        poster = LocalNotificationPosterSpy()
        store = StoreKitService(notificationPoster: poster, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testActualCancellationAndPendingBranchesEmitOnlyTheirOwnEventWithoutWalletWrites() async throws {
        XCTAssertTrue(balance.creditPromotion(amount: 25))
        XCTAssertEqual(store.markProcessed(transactionID: 7), .recorded)
        let before = defaults.persistentDomain(forName: suite) as NSDictionary?
        let names = [StoreKitService.purchaseCancelledNotification, StoreKitService.purchasePendingNotification,
                     StoreKitService.purchaseCompletedNotification, StoreKitService.purchaseFailedNotification]
        var received: [Notification] = []
        let tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { received.append($0) }
        }
        defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }

        // No feedback subscriber: cancellation must still broadcast, never schedule a local alert.
        try await store.handlePurchaseResult(.userCancelled)
        XCTAssertEqual(received.map(\.name), [StoreKitService.purchaseCancelledNotification])
        XCTAssertNil(received.first?.userInfo)
        XCTAssertTrue(received.first?.object as? StoreKitService === store)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, before)
        XCTAssertEqual(balance.balance, 25)
        XCTAssertEqual(TransactionRepository(defaults: defaults).fetchAll().count, 1)
        XCTAssertTrue(poster.requests.isEmpty)

        received.removeAll()
        try await store.handlePurchaseResult(.pending)
        XCTAssertEqual(received.map(\.name), [StoreKitService.purchasePendingNotification])
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, before)
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testBothRealSheetsUnlockCurrentButtonPreserveSelectionAndAllowRetry() async throws {
        for firing in [false, true] {
            var requested: [String] = []
            let sheet = makeSheet(firing: firing) { requested.append($0) }
            sheet.loadViewIfNeeded()
            // An idle cancellation is harmless and does not manufacture success/error UI.
            try await store.handlePurchaseResult(.userCancelled)
            let initialButton = try purchaseButton(in: sheet)
            XCTAssertTrue(initialButton.isEnabled)
            initialButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(requested.count, 1)
            XCTAssertFalse(initialButton.isEnabled)

            // Rebuilding the SKU button while busy must not hide a stuck latch.
            let presets = presetControls(in: sheet, firing: firing)
            let changedPreset = try XCTUnwrap(presets.last)
            changedPreset.sendActions(for: .touchUpInside)
            XCTAssertTrue(changedPreset.isSelected)
            let currentButton = try purchaseButton(in: sheet)
            XCTAssertFalse(currentButton === initialButton)
            XCTAssertFalse(currentButton.isEnabled)
            currentButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(requested.count, 1, "A rebuilt button must not start a concurrent purchase")

            try await store.handlePurchaseResult(.pending)
            XCTAssertFalse(currentButton.isEnabled, "Pending must not take the cancellation path")
            currentButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(requested.count, 1)

            try await store.handlePurchaseResult(.userCancelled)
            try await store.handlePurchaseResult(.userCancelled)
            XCTAssertTrue(currentButton.isEnabled)
            XCTAssertTrue(changedPreset.isSelected, "Cancellation preserves the selected SKU")
            XCTAssertNil(sheet.presentedViewController, "Cancellation must not present an error or dismiss the form")
            XCTAssertEqual(currentButton.alpha, 1)
            XCTAssertEqual(balance.balance, 0)
            XCTAssertTrue(TransactionRepository(defaults: defaults).fetchAll().isEmpty)
            XCTAssertNil(defaults.object(forKey: "storekit.processed_tx_ids"))
            let expectedID = try XCTUnwrap(firing
                ? FiringTopUpBottomSheetViewController.defaultPresets.last?.productID
                : DepositPresets.presets.last?.productID)
            currentButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(requested.count, 2, "The real CTA must pass its in-flight guard on retry")
            XCTAssertEqual(requested.last, expectedID)
            XCTAssertFalse(currentButton.isEnabled)
            try await store.handlePurchaseResult(.userCancelled)
            XCTAssertTrue(currentButton.isEnabled)
        }
    }

    private func makeSheet(firing: Bool, purchase: @escaping (String) -> Void) -> UIViewController {
        if firing {
            return FiringTopUpBottomSheetViewController(currentBalance: 0, balance: balance, purchaseProduct: purchase)
        }
        return DepositBottomSheetViewController(
            balance: balance, purchaseProduct: purchase, offerProvider: { productID in
                TopUpOffer(productID: productID, price: 1, currencyCode: "RUB", displayPrice: "1 ₽")
            }
        )
    }

    private func purchaseButton(in sheet: UIViewController) throws -> SPButton {
        try XCTUnwrap(descendants(in: sheet.view).compactMap { $0 as? SPButton }.first {
            $0.accessibilityIdentifier == "deposit.purchaseButton"
                || $0.accessibilityIdentifier == "firingTopUp.purchaseButton"
        })
    }

    private func presetControls(in sheet: UIViewController, firing: Bool) -> [UIControl] {
        descendants(in: sheet.view).compactMap { view -> UIControl? in
            if firing { return view as? FiringTopUpPresetRow }
            return view as? SPAmountPreset
        }
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
