import UIKit
import XCTest
import os
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
///
/// #1190: the same dismissal through the presenter also closes whatever is
/// presented ABOVE the sheet. An alarm puts its firing screen over the topmost
/// controller, which can be a deposit sheet left open on Wallet.
@MainActor
final class TopUpSuccessDismissalTests: XCTestCase {
    private var window: UIWindow?
    private var alertEvents: [Notification.Name] {
        [StoreKitService.purchasePendingNotification, StoreKitService.purchaseFailedNotification]
    }
    private let offer: (String) -> TopUpOffer? = {
        TopUpOffer(productID: $0, price: 149, currencyCode: "RUB", displayPrice: "149 ₽")
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

    /// The issue's stack: Wallet's deposit sheet, the firing screen an alarm put
    /// over it, and that screen's top-up sheet. The firing sheet's purchase is
    /// not the deposit sheet's, so the deposit sheet shows no success and closes
    /// nothing; before #1190 its dismissal took the ringing screen down.
    func testFiringSheetPurchaseLeavesTheDepositSheetAndTheFiringScreenAlone() throws {
        let center = NotificationCenter()
        let balance = BalanceService(defaults: makeIsolatedDefaults(), notificationCenter: center)
        var depositDismissal: (@MainActor @Sendable () -> Void)?
        var firingDismissal: (@MainActor @Sendable () -> Void)?
        let deposit = DepositBottomSheetViewController(
            balance: balance, notificationCenter: center,
            scheduleSuccessDismissal: { _, action in depositDismissal = action },
            purchaseProduct: { _ in XCTFail("The deposit sheet starts nothing here") }, offerProvider: offer
        )
        let firing = FiringTopUpBottomSheetViewController(
            balance: balance, notificationCenter: center,
            scheduleSuccessDismissal: { _, action in firingDismissal = action },
            purchaseProduct: { _ in }, pauseLifecycle: { _ in }, offerProvider: offer
        )
        let host = try mount(deposit)
        let firingScreen = coverScreen()
        present(firingScreen, on: deposit)
        present(firing, on: firingScreen)

        try button(in: firing, id: "firingTopUp.purchaseButton").sendActions(for: .touchUpInside)
        center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                    userInfo: [StoreKitService.amountUserInfoKey: 149.0])
        XCTAssertNil(try label(in: deposit, id: "deposit.successAmount").text, "No success state on the deposit sheet")
        XCTAssertTrue(try button(in: deposit, id: "deposit.purchaseButton").isEnabled)
        XCTAssertNil(depositDismissal, "The deposit sheet schedules no dismissal")

        // Run what main scheduled, so a regression shows the firing screen going down.
        depositDismissal?()
        try XCTUnwrap(firingDismissal, "The firing sheet's own purchase succeeded")()
        XCTAssertTrue(spin { firingScreen.presentedViewController == nil }, presentationDiagnostics(rootedAt: host))
        XCTAssertNil(firing.presentingViewController, "The firing sheet closed itself")
        XCTAssertTrue(deposit.presentedViewController === firingScreen, presentationDiagnostics(rootedAt: host))
        XCTAssertTrue(host.presentedViewController === deposit, presentationDiagnostics(rootedAt: host))
    }

    /// The deposit sheet's rule (#1190): a completion lands only while one of its
    /// own purchases is outstanding. A cancel ends one; the pending notice does
    /// not, so Ask to Buy's late approval is still this sheet's, even after a
    /// later tap was cancelled.
    func testDepositSheetTakesOnlyCompletionsOfItsOwnUncancelledPurchases() throws {
        let center = NotificationCenter()
        let balance = BalanceService(defaults: makeIsolatedDefaults(), notificationCenter: center)
        var dismissal: (@MainActor @Sendable () -> Void)?
        let sheet = DepositBottomSheetViewController(
            balance: balance, notificationCenter: center,
            scheduleSuccessDismissal: { _, action in dismissal = action },
            purchaseProduct: { _ in }, offerProvider: offer
        )
        let host = try mount(sheet)
        let tap = { try self.button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside) }
        let complete = {
            center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                        userInfo: [StoreKitService.amountUserInfoKey: 149.0])
        }
        complete()
        XCTAssertNil(dismissal, "Idle: another screen's purchase")
        try tap()
        center.post(name: StoreKitService.purchaseCancelledNotification, object: nil)
        complete()
        XCTAssertNil(dismissal, "Cancelled: nothing of this sheet's is left to complete")
        XCTAssertNil(try label(in: sheet, id: "deposit.successAmount").text)

        try tap()
        center.post(name: StoreKitService.purchasePendingNotification, object: nil)
        _ = try presentedAlert(on: sheet, after: StoreKitService.purchasePendingNotification)
        try tap()
        center.post(name: StoreKitService.purchaseCancelledNotification, object: nil)
        complete()
        try XCTUnwrap(dismissal, "The approval of the pending purchase is this sheet's")()
        XCTAssertNotNil(try label(in: sheet, id: "deposit.successAmount").text)
        XCTAssertTrue(spin { host.presentedViewController == nil }, presentationDiagnostics(rootedAt: host))
    }

    /// The sheet's own success, then an alarm fires over it within the 2 s: the
    /// dismissal skips, says so, and the screen above stays up.
    func testScreenPresentedOverEitherSheetInItsSuccessWindowSurvivesTheDismissal() throws {
        for firing in [false, true] {
            let center = NotificationCenter()
            let balance = BalanceService(defaults: makeIsolatedDefaults(), notificationCenter: center)
            var dismissal: (@MainActor @Sendable () -> Void)?
            let schedule: TopUpSuccessDismissal = { _, action in dismissal = action }
            let sheet: UIViewController = firing
                ? FiringTopUpBottomSheetViewController(
                    balance: balance, notificationCenter: center, scheduleSuccessDismissal: schedule,
                    purchaseProduct: { _ in }, pauseLifecycle: { _ in }, offerProvider: offer)
                : DepositBottomSheetViewController(
                    balance: balance, notificationCenter: center, scheduleSuccessDismissal: schedule,
                    purchaseProduct: { _ in }, offerProvider: offer)
            let host = try mount(sheet)
            let name = "\(type(of: sheet))"
            try button(in: sheet, id: firing ? "firingTopUp.purchaseButton" : "deposit.purchaseButton")
                .sendActions(for: .touchUpInside)
            center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                        userInfo: [StoreKitService.amountUserInfoKey: 149.0])
            let dismiss = try XCTUnwrap(dismissal, name)
            let alarmScreen = coverScreen()
            present(alarmScreen, on: sheet)

            var lines: [String] = []
            AppLogger.withTestSink({ category, level, message in
                if category == .ui, level == .error { lines.append(message) }
            }, perform: { dismiss() })
            XCTAssertEqual(lines, ["\(name): success dismissal skipped, UIViewController is presented above it"])
            // A dismissal sent marks both at once (main fails here); nothing queued sends one later.
            XCTAssertFalse(alarmScreen.isBeingDismissed, name)
            XCTAssertFalse(sheet.isBeingDismissed, name)
            drainMainQueue()
            XCTAssertTrue(alarmScreen.presentingViewController === sheet, presentationDiagnostics(rootedAt: host))
            XCTAssertTrue(host.presentedViewController === sheet, presentationDiagnostics(rootedAt: host))
        }
    }

    /// The rule's residue: the deposit sheet's own purchase is pending, its
    /// notice is up, and the alarm's screen goes over the notice, the topmost
    /// controller. A completion then counts as the sheet's, and its dismissal
    /// through the presenter would still take that screen down.
    func testScreenPresentedOverTheDepositSheetsOwnNoticeSurvivesTheDismissal() throws {
        let center = NotificationCenter()
        let balance = BalanceService(defaults: makeIsolatedDefaults(), notificationCenter: center)
        var dismissal: (@MainActor @Sendable () -> Void)?
        let sheet = DepositBottomSheetViewController(
            balance: balance, notificationCenter: center,
            scheduleSuccessDismissal: { _, action in dismissal = action },
            purchaseProduct: { _ in }, offerProvider: offer
        )
        let host = try mount(sheet)
        try button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside)
        center.post(name: StoreKitService.purchasePendingNotification, object: nil)
        let notice = try presentedAlert(on: sheet, after: StoreKitService.purchasePendingNotification)
        let alarmScreen = coverScreen()
        present(alarmScreen, on: notice)
        center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                    userInfo: [StoreKitService.amountUserInfoKey: 149.0])
        let dismiss = try XCTUnwrap(dismissal)

        var lines: [String] = []
        AppLogger.withTestSink({ category, level, message in
            if category == .ui, level == .error { lines.append(message) }
        }, perform: { dismiss() })
        XCTAssertEqual(lines, ["DepositBottomSheetViewController: success dismissal skipped, "
                               + "UIViewController is presented above it"])
        XCTAssertFalse(alarmScreen.isBeingDismissed)
        XCTAssertFalse(notice.isBeingDismissed)
        XCTAssertFalse(sheet.isBeingDismissed)
        drainMainQueue()
        XCTAssertTrue(alarmScreen.presentingViewController === notice, presentationDiagnostics(rootedAt: host))
    }

    // MARK: - Helpers

    /// A host in a key window presents `sheet` without animation, as the app does with animation.
    /// `unmount` is registered here, after the test's `makeIsolatedDefaults`, so
    /// it runs before that lease returns: teardown blocks run last-in, first-out.
    private func mount(_ sheet: UIViewController) throws -> UIViewController {
        unmount()
        // The backlog earlier suites left on the main queue is spent here, not
        // inside the first wait below (#618).
        drainMainQueue()
        addTeardownBlock { [weak self] in self?.unmount() }
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        present(sheet, on: host)
        return host
    }

    private func present(_ child: UIViewController, on parent: UIViewController) {
        var presented = false
        parent.present(child, animated: false) { presented = true }
        XCTAssertTrue(spin { presented }, "\(type(of: child)) must be up before the test drives it")
    }

    /// Stands in for the firing screen: `AlarmFiringPresenter` presents it full screen.
    private func coverScreen() -> UIViewController {
        let screen = UIViewController()
        screen.modalPresentationStyle = .fullScreen
        return screen
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
    private func spin(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
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

    private func label(in sheet: UIViewController, id: String) throws -> UILabel {
        try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == id
        })
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
