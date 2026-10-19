import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class FiringDirectPurchaseTerminalTests: XCTestCase {
    func testActualButtonKeepsPendingBusyAcrossBalanceChangeThenCancellationAllowsRetry() throws {
        let fixture = Fixture()
        let controller = try XCTUnwrap(fixture.controller)
        let button = try XCTUnwrap(controller.applePayNoBalanceButton)
        let chooseAmount = try XCTUnwrap(controller.chooseAmountLink)
        XCTAssertTrue(chooseAmount.isEnabled)
        let initialUpdates = controller.updates
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertEqual(fixture.calls.ends, 0)
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested, [AlarmFiringViewController.noBalanceProductID])
        XCTAssertEqual(fixture.calls.begins, 1)
        fixture.post(StoreKitService.purchasePendingNotification)
        XCTAssertTrue(fixture.wallet.topUp(amount: 1))
        XCTAssertEqual(controller.updates, initialUpdates + 1)
        XCTAssertTrue(controller.noBalancePurchaseInFlight)
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(chooseAmount.isEnabled)
        chooseAmount.sendActions(for: .touchUpInside)
        controller.noBalanceChooseAmountTapped()
        controller.presentTopUpSheet()
        XCTAssertEqual(controller.sheetPresentations, 0)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested.count, 1)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(chooseAmount.isEnabled)
        chooseAmount.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.sheetPresentations, 1)
        XCTAssertFalse(controller.noBalancePurchaseInFlight)
        XCTAssertTrue(controller.alerts.isEmpty)
        XCTAssertEqual(controller.dismissals, 0)
        XCTAssertEqual(fixture.wallet.balance, 1)
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.center.removals, 3)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertEqual(fixture.calls.ends, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested.count, 2)
        XCTAssertEqual(fixture.calls.begins, 2)
        XCTAssertFalse(button.isEnabled)
    }

    func testFailureAndCompletionOnlyFinishActivePurchaseAndAllowMoreCreditWhenInsufficient() throws {
        let fixture = Fixture()
        let controller = try XCTUnwrap(fixture.controller)
        let button = try XCTUnwrap(controller.applePayNoBalanceButton)
        fixture.post(StoreKitService.purchaseFailedNotification)
        XCTAssertTrue(controller.alerts.isEmpty)
        button.sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchaseFailedNotification, message: "Failure fixture")
        XCTAssertEqual(controller.alerts.map(\.message), ["Failure fixture"])
        XCTAssertEqual(controller.alerts.first?.title, Localized.text("firing.alert.purchase_failed.title"))
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(controller.chooseAmountLink?.isEnabled == true)
        fixture.post(StoreKitService.purchaseFailedNotification)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        XCTAssertEqual(controller.alerts.count, 1)
        XCTAssertEqual(fixture.calls.ends, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(fixture.wallet.topUp(amount: 1))
        let updates = controller.updates
        fixture.post(StoreKitService.purchaseCompletedNotification)
        XCTAssertEqual(controller.updates, updates + 1)
        XCTAssertTrue(controller.noBalanceContainer?.isHidden == false)
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(controller.noBalancePurchaseInFlight)
        XCTAssertTrue(controller.chooseAmountLink?.isEnabled == true)
        XCTAssertEqual(fixture.wallet.balance, 1, "Feedback must not credit the wallet")
        XCTAssertEqual(controller.dismissals, 0)
        XCTAssertEqual(fixture.calls.ends, 2)
        XCTAssertEqual(fixture.center.removals, 6)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        XCTAssertEqual(controller.updates, updates + 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested.count, 3)
        XCTAssertEqual(fixture.calls.begins, 3)
        XCTAssertFalse(button.isEnabled)
    }

    func testOwnerTeardownBalancesActiveFeedbackAndRemovesAllTokens() throws {
        let fixture = Fixture()
        weak var controller = fixture.controller
        weak var owner = fixture.controller?.noBalancePurchase
        try XCTUnwrap(controller?.applePayNoBalanceButton).sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.begins, 1)
        autoreleasepool { fixture.controller = nil }
        XCTAssertNil(controller)
        XCTAssertNil(owner)
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.center.removals, 4)
        fixture.post(StoreKitService.purchaseFailedNotification)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertTrue(fixture.wallet.topUp(amount: 1))
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.calls.requested.count, 1)
        XCTAssertTrue(fixture.backend.scheduledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.snoozedIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
    }

    private final class Calls {
        var requested: [String] = []
        var begins = 0
        var ends = 0
    }

    private final class Fixture {
        let suite = "firing-direct-purchase-\(UUID().uuidString)"
        let center = TrackingCenter()
        let calls = Calls()
        let backend = TestAlarmKitBackend()
        let defaults: UserDefaults
        let wallet: BalanceService
        var controller: PurchaseController?

        init() {
            defaults = UserDefaults(suiteName: suite)!
            wallet = BalanceService(defaults: defaults, notificationCenter: center)
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
            let model = AlarmFiringViewModel(
                alarm: Alarm(penaltyAmount: 50), balanceService: wallet,
                alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler), scheduler: scheduler,
                wakeStore: WakeEventStore(defaults: defaults), ledger: TransactionRepository(defaults: defaults)
            )
            let controller = PurchaseController(viewModel: model)
            controller.noBalancePurchase = AlarmFiringNoBalancePurchase(
                controller: controller, center: center, dispatch: { [calls] in calls.requested.append($0) },
                beginFeedback: { [calls] in calls.begins += 1 }, endFeedback: { [calls] in calls.ends += 1 }
            )
            self.controller = controller
            controller.loadViewIfNeeded()
            controller.observeBalanceForNoBalanceState()
            controller.observeBalanceForNoBalanceState()
        }

        deinit { defaults.removePersistentDomain(forName: suite) }

        func post(_ name: Notification.Name, message: String? = nil) {
            center.post(name: name, object: nil, userInfo: message.map { [StoreKitService.messageUserInfoKey: $0] })
        }
    }
}

@MainActor
private final class PurchaseController: AlarmFiringViewController {
    var updates = 0
    var alerts: [UIAlertController] = []
    var dismissals = 0
    var sheetPresentations = 0
    override func viewDidLoad() { buildFiringLayout() }
    override func updateUI() { updates += 1; super.updateUI() }
    override func present(
        _ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil
    ) {
        if let alert = viewControllerToPresent as? UIAlertController { alerts.append(alert) }
        if viewControllerToPresent is FiringTopUpBottomSheetViewController { sheetPresentations += 1 }
    }
    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) { dismissals += 1 }
}

private final class TrackingCenter: NotificationCenter, @unchecked Sendable {
    nonisolated(unsafe) private(set) var removals = 0
    override func removeObserver(_ observer: Any) {
        removals += 1
        super.removeObserver(observer)
    }
}
