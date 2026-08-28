#if DEBUG
import XCTest
@testable import SnoozePay

/// Smoke test for the DEBUG `-uitour confirm-delete` route (#467).
///
/// The visual-audit harness screenshots this route to validate the destructive
/// confirmation, but the router used to schedule the edit form's presentation
/// AND the sheet's presentation on the same 0.8 s deadline. The sheet therefore
/// asked a navigation controller that was still mid-transition to present —
/// a silent no-op — and every capture showed the scrim plus an empty strip.
///
/// The route now chains off the edit form's presentation completion, so this
/// test asserts exactly what the harness needs to see: the sheet mounted over
/// the edit form, with its title, body and BOTH actions on screen.
final class UITourConfirmDeleteRouteTests: XCTestCase {

    private var window: UIWindow!
    private var previousKeyWindow: UIWindow?

    override func setUp() {
        super.setUp()
        previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window = makeHostWindow()
    }

    override func tearDown() {
        window?.rootViewController?.dismiss(animated: false)
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
        super.tearDown()
    }

    // MARK: - Route

    func testConfirmDeleteRoutePresentsSheetOverTheEditForm() {
        UITourLauncher.mount("confirm-delete", in: window)

        guard let sheet = waitForConfirmSheet() else {
            return XCTFail("`-uitour confirm-delete` never presented the confirmation sheet")
        }

        // The presenter must be the alarm-edit form, already on screen — this
        // is the ordering the two racing timers used to break.
        let nav = sheet.presentingViewController as? UINavigationController
        XCTAssertNotNil(nav, "The sheet must be presented by the edit form's navigation controller")
        XCTAssertTrue(
            nav?.topViewController is CreateAlarmViewController,
            "The edit form must be mounted underneath the confirmation sheet"
        )
        XCTAssertNotNil(nav?.viewIfLoaded?.window, "The presenter must be in the window hierarchy")
    }

    func testConfirmDeleteSheetShowsTitleBodyAndBothActions() {
        let expectedBody = AlarmDeletionCopy.body(balance: BalanceService.shared.balance)

        UITourLauncher.mount("confirm-delete", in: window)

        guard let sheet = waitForConfirmSheet() else {
            return XCTFail("`-uitour confirm-delete` never presented the confirmation sheet")
        }
        sheet.view.layoutIfNeeded()

        let title = view(withID: "confirmDelete.title", in: sheet.view) as? UILabel
        XCTAssertEqual(title?.text, "Удалить будильник?", "Sheet headline must be on screen")
        XCTAssertTrue(isVisible(title), "Sheet headline must be visible, not just allocated")

        let body = view(withID: "confirmDelete.body", in: sheet.view) as? UILabel
        XCTAssertEqual(body?.text, expectedBody, "Sheet body must carry the balance reassurance copy")
        XCTAssertTrue(isVisible(body), "Sheet body must be visible")

        let delete = view(withID: "confirmDelete.deleteButton") as? SPButton
        XCTAssertTrue(isVisible(delete), "Destructive action must be visible")
        XCTAssertEqual(delete?.accessibilityLabel, "Удалить")

        let cancel = view(withID: "confirmDelete.cancelButton") as? SPButton
        XCTAssertTrue(isVisible(cancel), "Cancel action must be visible")
        XCTAssertEqual(cancel?.accessibilityLabel, "Отмена")
    }

    /// The audit only ever saw a narrow strip at the bottom: the card was never
    /// laid out because the sheet was never presented. Assert the content sits
    /// inside the window instead of trusting mere existence.
    func testConfirmDeleteSheetContentIsOnScreen() {
        UITourLauncher.mount("confirm-delete", in: window)

        guard let sheet = waitForConfirmSheet() else {
            return XCTFail("`-uitour confirm-delete` never presented the confirmation sheet")
        }
        sheet.view.layoutIfNeeded()

        for identifier in ["confirmDelete.title", "confirmDelete.deleteButton", "confirmDelete.cancelButton"] {
            guard let found = view(withID: identifier, in: sheet.view) else {
                XCTFail("\(identifier) missing from the presented sheet")
                continue
            }
            let frame = found.convert(found.bounds, to: window)
            XCTAssertFalse(frame.isEmpty, "\(identifier) must have a non-empty frame")
            XCTAssertTrue(
                window.bounds.intersects(frame),
                "\(identifier) must lie inside the window, got \(frame) in \(window.bounds)"
            )
        }
    }

    // MARK: - Helpers

    /// A key window on the host app's scene — a scene-less window would let
    /// UIKit drop the presentation, which is the very failure under test.
    private func makeHostWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let fallbackFrame = previousKeyWindow?.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: fallbackFrame)
        if window.frame.isEmpty {
            window.frame = scene?.coordinateSpace.bounds ?? fallbackFrame
        }
        window.makeKeyAndVisible()
        return window
    }

    /// Polls the presentation chain while pumping the main run loop, so the
    /// launcher's own `asyncAfter` mount actually gets a chance to run. The
    /// condition is "sheet is IN the window hierarchy", not merely "sheet
    /// exists": `presentedViewController` is set the instant `present` is
    /// called, one run-loop turn before the view is actually mounted.
    private func waitForConfirmSheet(timeout: TimeInterval = 10) -> ConfirmDeleteAlarmViewController? {
        var found: ConfirmDeleteAlarmViewController?
        let presented = XCTestExpectation(description: "confirm-delete sheet presented")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let sheet = self?.presentedConfirmSheet(),
                  sheet.viewIfLoaded?.window != nil else { return }
            found = sheet
            timer.invalidate()
            presented.fulfill()
        }
        defer { poll.invalidate() }
        return XCTWaiter.wait(for: [presented], timeout: timeout) == .completed ? found : nil
    }

    private func presentedConfirmSheet() -> ConfirmDeleteAlarmViewController? {
        var current = window?.rootViewController
        while let presenter = current {
            if let sheet = presenter as? ConfirmDeleteAlarmViewController { return sheet }
            current = presenter.presentedViewController
        }
        return nil
    }

    private func view(withID identifier: String, in root: UIView? = nil) -> UIView? {
        guard let root = root ?? presentedConfirmSheet()?.viewIfLoaded else { return nil }
        if root.accessibilityIdentifier == identifier { return root }
        for subview in root.subviews {
            if let match = view(withID: identifier, in: subview) { return match }
        }
        return nil
    }

    private func isVisible(_ candidate: UIView?) -> Bool {
        guard let candidate, candidate.window != nil else { return false }
        var node: UIView? = candidate
        while let current = node {
            if current.isHidden || current.alpha < 0.01 { return false }
            node = current.superview
        }
        return candidate.bounds.width > 0 && candidate.bounds.height > 0
    }
}
#endif
