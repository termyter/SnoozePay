import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class FiringTopUpAutoResumeTests: XCTestCase {
    func testOverdueCancellationResumesOnceAndPendingCannotResume() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        let sheet = fixture.makeSheet()
        let button = try purchaseButton(in: sheet)
        button.sendActions(for: .touchUpInside)
        sheet.handleAutoResume()
        sheet.handleAutoResume()
        fixture.post(StoreKitService.purchasePendingNotification)
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(fixture.resumes, 0)
        XCTAssertTrue(try countdown(in: sheet).contains("00:00"))

        fixture.post(StoreKitService.purchaseCancelledNotification)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        sheet.handleAutoResume()
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.resumes, 1)
        XCTAssertEqual(fixture.requested.count, 1, "An ended sheet cannot start another purchase")
        XCTAssertTrue(try countdown(in: sheet).contains("00:00"), "No fresh 60-second period")
        try fixture.assertWalletUnchanged()
    }

    func testFailureAcknowledgementHonorsDeadlineInEitherEventOrder() throws {
        for deadlineFirst in [true, false] {
            let fixture = try Fixture()
            defer { fixture.clear() }
            let sheet = fixture.makeSheet()
            try purchaseButton(in: sheet).sendActions(for: .touchUpInside)
            if deadlineFirst { sheet.handleAutoResume() }
            fixture.post(StoreKitService.purchaseFailedNotification)
            fixture.post(StoreKitService.purchaseFailedNotification)
            let alert = try XCTUnwrap(fixture.alerts.first)
            XCTAssertEqual(fixture.alerts.count, 1, "Duplicate failure must not stack alerts")
            XCTAssertEqual(alert.title, Localized.text("firing.alert.purchase_failed.title"))
            XCTAssertEqual(alert.message, Localized.text("firing.alert.purchase_failed.message"))
            XCTAssertEqual(alert.actions.map(\.title), [Localized.text("common.button.ok")])
            sheet.handleAutoResume()
            sheet.handleAutoResume()
            XCTAssertEqual(fixture.resumes, 0, "The original error must remain until OK")
            XCTAssertTrue(try countdown(in: sheet).contains("00:00"))

            // The real UIAlertAction calls this same acknowledgement after alert dismissal.
            sheet.acknowledgePurchaseFailure()
            sheet.acknowledgePurchaseFailure()
            sheet.handleAutoResume()
            fixture.post(StoreKitService.purchaseCancelledNotification)
            XCTAssertEqual(fixture.resumes, 1)
            XCTAssertTrue(fixture.successDelays.isEmpty)
            try fixture.assertWalletUnchanged()
        }
    }

    func testEarlyCancellationKeepsOriginalDeadlineAndRetry() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        let sheet = fixture.makeSheet()
        let button = try purchaseButton(in: sheet)
        button.sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertEqual(fixture.resumes, 0)
        XCTAssertTrue(button.isEnabled)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.requested.count, 2)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        sheet.handleAutoResume()
        XCTAssertEqual(fixture.resumes, 1, "Cancellation must not replace the original deadline")
        try fixture.assertWalletUnchanged()
    }

    func testSuccessKeepsTwoSecondCompletionAndSuppressesLateResume() throws {
        for overdue in [false, true] {
            let fixture = try Fixture()
            defer { fixture.clear() }
            let sheet = fixture.makeSheet()
            try purchaseButton(in: sheet).sendActions(for: .touchUpInside)
            if overdue { sheet.handleAutoResume() }
            fixture.post(StoreKitService.purchaseCompletedNotification,
                         info: [StoreKitService.amountUserInfoKey: 1.25])
            fixture.post(StoreKitService.purchaseCompletedNotification,
                         info: [StoreKitService.amountUserInfoKey: 999.0])
            fixture.post(StoreKitService.purchaseCancelledNotification)
            fixture.post(StoreKitService.purchaseFailedNotification)
            sheet.handleAutoResume()
            sheet.acknowledgePurchaseFailure()
            XCTAssertEqual(fixture.successDelays, [2])
            XCTAssertEqual(fixture.resumes, 0)
            XCTAssertTrue(fixture.alerts.isEmpty)
            try fixture.assertWalletUnchanged()
        }
    }

    func testManualTeardownDiscardsOverdueAndLateEventsWithoutRetainingSheet() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        weak var released: FiringTopUpBottomSheetViewController?
        try autoreleasepool {
            let sheet = fixture.makeSheet()
            try purchaseButton(in: sheet).sendActions(for: .touchUpInside)
            sheet.handleAutoResume()
            sheet.endPauseTimers()
            sheet.endPauseTimers()
            fixture.post(StoreKitService.purchaseCancelledNotification)
            fixture.post(StoreKitService.purchaseFailedNotification)
            fixture.post(StoreKitService.purchaseCompletedNotification,
                         info: [StoreKitService.amountUserInfoKey: 1.25])
            sheet.handleAutoResume()
            released = sheet
        }
        XCTAssertNil(released)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertEqual(fixture.resumes, 0)
        XCTAssertTrue(fixture.successDelays.isEmpty)
        XCTAssertTrue(fixture.alerts.isEmpty)
        try fixture.assertWalletUnchanged()
    }

    private func purchaseButton(in sheet: FiringTopUpBottomSheetViewController) throws -> SPButton {
        sheet.loadViewIfNeeded()
        return try XCTUnwrap(descendants(in: sheet.view).compactMap { $0 as? SPButton }.first {
            $0.accessibilityIdentifier == "firingTopUp.purchaseButton"
        })
    }

    private func countdown(in sheet: UIViewController) throws -> String {
        let label = try XCTUnwrap(descendants(in: sheet.view).compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == "firingTopUp.pauseCountdown"
        })
        return label.attributedText?.string ?? label.text ?? ""
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }

    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let center: NotificationCenter
        let balance: BalanceService
        var requested: [String] = []
        var resumes = 0
        var alerts: [UIAlertController] = []
        var successDelays: [TimeInterval] = []

        init() throws {
            let suite = "FiringTopUpAutoResumeTests.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let center = NotificationCenter()
            self.suite = suite
            self.defaults = defaults
            self.center = center
            self.balance = BalanceService(defaults: defaults, notificationCenter: center)
        }

        func clear() { defaults.removePersistentDomain(forName: suite) }

        func makeSheet() -> FiringTopUpBottomSheetViewController {
            FiringTopUpBottomSheetViewController(
                currentBalance: 0, balance: balance, notificationCenter: center,
                scheduleSuccessDismissal: { [weak self] delay, _ in self?.successDelays.append(delay) },
                purchaseProduct: { [weak self] in self?.requested.append($0) },
                presentPurchaseFailure: { [weak self] in self?.alerts.append($0) },
                dismissForAutoResume: { [weak self] in self?.resumes += 1 }
            )
        }

        func post(_ name: Notification.Name, info: [String: Any]? = nil) {
            center.post(name: name, object: nil, userInfo: info)
        }

        func assertWalletUnchanged() throws {
            XCTAssertEqual(balance.balance, 0)
            let repository = TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
            XCTAssertTrue(try repository.fetchAllChecked().isEmpty)
            XCTAssertNil(defaults.object(forKey: "storekit.processed_tx_ids"))
        }
    }
}
