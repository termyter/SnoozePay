import UIKit
import XCTest
@testable import SnoozePay

/// #1189: the 2 s success dismissal has to close the sheet even while the sheet
/// still presents an alert, either the pending notice (#1183) or a failure alert.
/// Calling `dismiss` on a presenter closes its presented child, so the old
/// `self.dismiss` closed only the alert. On the firing sheet the pause had
/// already ended, so the alarm stayed paused behind the success state.
///
/// Mounted for real: a host presents the sheet and the sheet presents the
/// alert. `TopUpSuccessCurrencyTests` stubs the dismissal and does not mount,
/// which is why it stayed green.
@MainActor
final class TopUpSuccessDismissalTests: XCTestCase {
    private var window: UIWindow?
    private var alertEvents: [Notification.Name] {
        [StoreKitService.purchasePendingNotification, StoreKitService.purchaseFailedNotification]
    }

    override func tearDown() {
        unmount()
        super.tearDown()
    }

    func testFiringSheetSuccessClosesTheSheetOverAnAlert() throws {
        for event in alertEvents {
            let center = NotificationCenter()
            let balance = BalanceService(defaults: makeIsolatedDefaults(), notificationCenter: center)
            var dismissal: (@MainActor @Sendable () -> Void)?
            var lifecycle: [Bool] = []
            var dismissals = 0
            let sheet = FiringTopUpBottomSheetViewController(
                balance: balance, notificationCenter: center,
                scheduleSuccessDismissal: { _, action in dismissal = action },
                purchaseProduct: { _ in }, pauseLifecycle: { lifecycle.append($0) },
                offerProvider: { TopUpOffer(productID: $0, price: 149, currencyCode: "RUB", displayPrice: "149 ₽") }
            )
            sheet.onDismiss = { dismissals += 1 }
            let host = try mount(sheet)
            try button(in: sheet, id: "firingTopUp.purchaseButton").sendActions(for: .touchUpInside)
            center.post(name: event, object: nil)
            let alert = try presentedAlert(on: sheet, after: event)
            center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                        userInfo: [StoreKitService.amountUserInfoKey: 149.0])
            try XCTUnwrap(dismissal, "\(event.rawValue)")()
            XCTAssertTrue(spin { host.presentedViewController == nil }, presentationDiagnostics(rootedAt: host))
            XCTAssertNil(alert.presentingViewController, "\(event.rawValue)")
            XCTAssertEqual(dismissals, 1, "The sheet itself closed, not only its alert: \(event.rawValue)")
            XCTAssertEqual(lifecycle, [true, false], "\(event.rawValue)")
        }
    }

    /// Also pins the deposit sheet's `purchaseInFlight` guard: pending reaching
    /// an idle sheet is another screen's purchase and shows nothing.
    func testDepositSheetIgnoresIdlePendingAndSuccessClosesTheSheetOverAnAlert() throws {
        for event in alertEvents {
            let center = NotificationCenter()
            let balance = BalanceService(defaults: makeIsolatedDefaults(), notificationCenter: center)
            var dismissal: (@MainActor @Sendable () -> Void)?
            var requested: [String] = []
            let sheet = DepositBottomSheetViewController(
                balance: balance, notificationCenter: center,
                scheduleSuccessDismissal: { _, action in dismissal = action },
                purchaseProduct: { requested.append($0) },
                offerProvider: { TopUpOffer(productID: $0, price: 149, currencyCode: "RUB", displayPrice: "149 ₽") }
            )
            let host = try mount(sheet)
            center.post(name: StoreKitService.purchasePendingNotification, object: nil)
            XCTAssertNil(sheet.presentedViewController, "An idle sheet has no tap to end")
            XCTAssertTrue(try button(in: sheet, id: "deposit.purchaseButton").isEnabled)
            try button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside)
            XCTAssertEqual(requested.count, 1)
            center.post(name: event, object: nil)
            let alert = try presentedAlert(on: sheet, after: event)
            XCTAssertTrue(try button(in: sheet, id: "deposit.purchaseButton").isEnabled, "The tap has ended")
            center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                        userInfo: [StoreKitService.amountUserInfoKey: 149.0])
            try XCTUnwrap(dismissal, "\(event.rawValue)")()
            XCTAssertTrue(spin { host.presentedViewController == nil }, presentationDiagnostics(rootedAt: host))
            XCTAssertNil(alert.presentingViewController, "\(event.rawValue)")
            XCTAssertNil(sheet.presentingViewController, "The sheet itself closed: \(event.rawValue)")
        }
    }

    // MARK: - Helpers

    /// A host in a key window presents `sheet` without animation, as the app does with animation.
    private func mount(_ sheet: UIViewController) throws -> UIViewController {
        unmount()
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        var presented = false
        host.present(sheet, animated: false) { presented = true }
        XCTAssertTrue(spin { presented }, "The sheet must be up before the test drives it")
        return host
    }

    /// Closes whatever a failed run left up, so the sheet's appearance (and the
    /// deposit sheet's StoreKit feedback subscription) is balanced.
    private func unmount() {
        if let host = window?.rootViewController, host.presentedViewController != nil {
            host.dismiss(animated: false)
            _ = spin { host.presentedViewController == nil }
        }
        window?.isHidden = true
        window = nil
    }

    /// The alert the sheet really presents for `event`, once its presentation has finished.
    private func presentedAlert(
        on sheet: UIViewController, after event: Notification.Name
    ) throws -> UIAlertController {
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController,
                                  presentationDiagnostics(rootedAt: sheet))
        if event == StoreKitService.purchasePendingNotification {
            XCTAssertNil(alert.title)
            XCTAssertEqual(alert.message, StoreKitService.purchasePendingMessage)
            XCTAssertEqual(alert.view.accessibilityIdentifier, "purchase.pendingNotice")
        } else {
            XCTAssertNotNil(alert.title)
        }
        XCTAssertTrue(spin { !alert.isBeingPresented && alert.viewIfLoaded?.window != nil },
                      "The alert must finish presenting: \(event.rawValue)")
        return alert
    }

    /// Turns the main run loop until `condition` holds, for at most `timeout`.
    private func spin(timeout: TimeInterval = 2, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func button(in sheet: UIViewController, id: String) throws -> SPButton {
        try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? SPButton }.first {
            $0.accessibilityIdentifier == id
        })
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
