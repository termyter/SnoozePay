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
/// the edit form, with its title, body and BOTH actions laid out on screen.
final class UITourConfirmDeleteRouteTests: XCTestCase {

    /// Everything the harness must be able to photograph.
    private let contentIdentifiers = [
        "confirmDelete.title",
        "confirmDelete.body",
        "confirmDelete.deleteButton",
        "confirmDelete.cancelButton"
    ]

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

    // MARK: - Routing

    /// Deliberately waits only for "sheet is in the hierarchy", so a routing
    /// regression stays distinguishable from a layout-timing problem.
    func testConfirmDeleteRoutePresentsSheetOverTheEditForm() {
        UITourLauncher.mount("confirm-delete", in: window)

        guard let sheet = waitForPresentedSheet() else {
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

    // MARK: - Content

    func testConfirmDeleteSheetShowsTitleBodyAndBothActions() {
        let expectedBody = AlarmDeletionCopy.body(balance: BalanceService.shared.balance)

        UITourLauncher.mount("confirm-delete", in: window)

        guard let sheet = waitForLaidOutSheet() else {
            return XCTFail("Confirmation content never laid out. \(layoutDiagnostics())")
        }

        let title = contentView("confirmDelete.title", in: sheet) as? UILabel
        XCTAssertEqual(title?.text, "Удалить будильник?", "Sheet headline must be on screen")
        XCTAssertTrue(isVisible(title), "Sheet headline must be visible, not just allocated")

        let body = contentView("confirmDelete.body", in: sheet) as? UILabel
        XCTAssertEqual(body?.text, expectedBody, "Sheet body must carry the balance reassurance copy")
        XCTAssertTrue(isVisible(body), "Sheet body must be visible")

        let delete = contentView("confirmDelete.deleteButton", in: sheet) as? SPButton
        XCTAssertTrue(isVisible(delete), "Destructive action must be visible")
        XCTAssertEqual(delete?.accessibilityLabel, "Удалить")

        let cancel = contentView("confirmDelete.cancelButton", in: sheet) as? SPButton
        XCTAssertTrue(isVisible(cancel), "Cancel action must be visible")
        XCTAssertEqual(cancel?.accessibilityLabel, "Отмена")
    }

    /// The audit only ever saw a dimmed backdrop with a narrow strip at the
    /// bottom. Non-zero frames alone would not have caught that — assert the
    /// content actually lands INSIDE the window, which the wait predicate
    /// (size only) deliberately does not check.
    func testConfirmDeleteSheetContentIsOnScreen() {
        UITourLauncher.mount("confirm-delete", in: window)

        guard let sheet = waitForLaidOutSheet() else {
            return XCTFail("Confirmation content never laid out. \(layoutDiagnostics())")
        }

        for identifier in contentIdentifiers {
            guard let found = contentView(identifier, in: sheet) else {
                XCTFail("\(identifier) missing from the presented sheet")
                continue
            }
            let frame = found.convert(found.bounds, to: window)
            XCTAssertFalse(frame.isEmpty, "\(identifier) must have a non-empty frame")
            XCTAssertTrue(
                window.bounds.insetBy(dx: -1, dy: -1).contains(frame),
                "\(identifier) must lie inside the window, got \(frame) in \(window.bounds)"
            )
        }
    }

    // MARK: - Host window

    /// A key window on the host app's scene — a scene-less window would let
    /// UIKit drop the presentation, which is the very failure under test.
    private func makeHostWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let bounds = previousKeyWindow?.bounds
            ?? scene?.coordinateSpace.bounds
            ?? CGRect(x: 0, y: 0, width: 393, height: 852)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: bounds)
        window.frame = bounds
        window.makeKeyAndVisible()
        return window
    }

    // MARK: - Waiting

    /// Waits until the sheet is merely in the window hierarchy.
    private func waitForPresentedSheet(timeout: TimeInterval = 10) -> ConfirmDeleteAlarmViewController? {
        return waitForSheet(timeout: timeout) { sheet in
            sheet.viewIfLoaded?.window != nil
        }
    }

    /// Waits until the sheet's content has REAL frames.
    ///
    /// Being in the hierarchy is not the same as being laid out: the presented
    /// view's own frame is set by the presentation container, not by the sheet,
    /// so the run-loop turn on which `present` completes can still leave
    /// `sheet.view.bounds` at zero — and then every child collapses with it.
    /// That is what made the first CI run red while the routing test passed.
    private func waitForLaidOutSheet(timeout: TimeInterval = 15) -> ConfirmDeleteAlarmViewController? {
        return waitForSheet(timeout: timeout) { [weak self] sheet in
            guard let self, sheet.viewIfLoaded?.window != nil else { return false }
            self.forceLayout()
            return self.contentIdentifiers.allSatisfy { identifier in
                self.contentView(identifier, in: sheet).map { !$0.bounds.isEmpty } ?? false
            }
        }
    }

    private func waitForSheet(
        timeout: TimeInterval,
        until isReady: @escaping (ConfirmDeleteAlarmViewController) -> Bool
    ) -> ConfirmDeleteAlarmViewController? {
        var found: ConfirmDeleteAlarmViewController?
        let ready = XCTestExpectation(description: "confirm-delete sheet ready")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let sheet = self?.presentedConfirmSheet(), isReady(sheet) else { return }
            found = sheet
            timer.invalidate()
            ready.fulfill()
        }
        defer { poll.invalidate() }
        return XCTWaiter.wait(for: [ready], timeout: timeout) == .completed ? found : nil
    }

    /// Drives layout from the WINDOW down. Laying out `sheet.view` alone is
    /// useless while its own frame is still zero — the parent owns that frame.
    private func forceLayout() {
        window?.setNeedsLayout()
        window?.layoutIfNeeded()
        guard let sheetView = presentedConfirmSheet()?.viewIfLoaded else { return }
        sheetView.setNeedsLayout()
        sheetView.layoutIfNeeded()
    }

    // MARK: - Lookup

    private func presentedConfirmSheet() -> ConfirmDeleteAlarmViewController? {
        var current = window?.rootViewController
        while let presenter = current {
            if let sheet = presenter as? ConfirmDeleteAlarmViewController { return sheet }
            current = presenter.presentedViewController
        }
        return nil
    }

    private func contentView(
        _ identifier: String,
        in sheet: ConfirmDeleteAlarmViewController
    ) -> UIView? {
        return sheet.viewIfLoaded.flatMap { view(withID: identifier, in: $0) }
    }

    private func view(withID identifier: String, in root: UIView) -> UIView? {
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
        return !candidate.bounds.isEmpty
    }

    /// Printed on timeout so a future failure says WHAT was zero-sized instead
    /// of only that something was.
    private func layoutDiagnostics() -> String {
        guard let sheet = presentedConfirmSheet() else {
            return "No ConfirmDeleteAlarmViewController in the presentation chain."
        }
        guard let sheetView = sheet.viewIfLoaded else {
            return "Sheet presented but its view was never loaded."
        }
        let frames = contentIdentifiers.map { identifier in
            let found = view(withID: identifier, in: sheetView)
            return "\(identifier)=\(found.map { "\($0.frame)" } ?? "missing")"
        }
        return "window=\(window?.bounds ?? .zero) sheet=\(sheetView.frame) " + frames.joined(separator: " ")
    }
}
#endif
