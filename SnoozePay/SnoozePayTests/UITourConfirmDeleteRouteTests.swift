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
///
/// Fixing the router only got the sheet on screen — it stayed empty, because a
/// second, independent defect kept the card collapsed: neither action button
/// had `translatesAutoresizingMaskIntoConstraints` cleared, so UIKit pinned
/// both to a required 0×0 frame and Auto Layout paid for it by breaking the
/// badge's height and both labels' intrinsic heights. The content assertions
/// below are what caught that, so keep them measuring real geometry after a
/// single layout pass.
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

    /// How the three phases of a test went, stamped as they happen and printed
    /// only if a wait times out (#728).
    ///
    /// The red attempt of run 33698289556 is why these exist. It reported one
    /// fact — "never presented" — and 23.4 s of wall clock around a 10 s wait,
    /// which left every question open: whether the drain in `setUp` spent that
    /// time, whether the wait overran its own budget, whether the run loop was
    /// turning at all inside it. Three different mechanisms fit that log
    /// equally well, and a flake this rare does not offer a second reading
    /// unless the first one is instrumented.
    private var setUpEvidence = "setUp: not stamped."
    private var mountEvidence = "mount: not stamped."
    private var waitEvidence = "wait: not stamped."

    /// The poll interval of `waitForSheet`, shared with the census so the
    /// summary compares surviving ticks against the rate they were due at
    /// rather than a number written down twice.
    private let pollInterval: TimeInterval = 0.05

    override func setUp() {
        super.setUp()
        // #618. The evidence for this class specifically: inside its own wait
        // the log flooded with "Unbalanced calls to begin/end appearance
        // transitions" for OnboardingViewController / StreakModalViewController
        // / UITabBarController — objects belonging to *other* suites — and the
        // route's own presentation was delivered ~9 s behind its 0.8 s beat.
        // See `drainMainQueue` for why the fix is a drain and not a timeout.
        //
        // Taken through `drainMainQueueOutcome` rather than `drainMainQueue` so
        // the turns and the round trip survive into a later failure message:
        // "the drain went quiet" and "the drain went quiet after 13 s of
        // spending" are the same Bool and completely different diagnoses. The
        // report on a non-quiet outcome is kept identical to the one
        // `drainMainQueue` would have made — this is extra evidence, not a
        // relaxed check.
        let drainStarted = Date()
        let drain = drainMainQueueOutcome()
        let drainElapsed = Date().timeIntervalSince(drainStarted)
        setUpEvidence = "setUp drain took \(seconds(drainElapsed)) and ended \(drain)."
        if !drain.isQuiet {
            XCTFail(drain.diagnosis)
        }
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
        mountRoute()

        guard let sheet = waitForPresentedSheet() else {
            return XCTFail(
                timeoutMessage("`-uitour confirm-delete` never presented the confirmation sheet.")
            )
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

    /// The route must not fire its presentation blind.
    ///
    /// It used to present on a flat 0.8 s timer and never check, so whenever
    /// the main queue was busy enough to deliver that block late the tour
    /// presented onto a view controller that had already left the window —
    /// which UIKit silently drops, with no retry and no sheet (#618). Taking
    /// the presenter out of the hierarchy before the beat is the cheap way to
    /// assert the check exists: without it, `root` ends up owning a
    /// presentation that nobody can ever see.
    func testConfirmDeleteRouteDoesNotPresentIntoADetachedPresenter() {
        mountRoute()
        guard let root = window.rootViewController else {
            return XCTFail("the route must mount a root before it presents anything")
        }

        window.rootViewController = nil
        // Comfortably past the route's own 0.8 s beat, so "nothing presented"
        // means "declined to present", not "hasn't tried yet".
        let beatPassed = XCTestExpectation(description: "route had its chance to fire")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { beatPassed.fulfill() }
        _ = XCTWaiter.wait(for: [beatPassed], timeout: 10)

        XCTAssertNil(
            root.presentedViewController,
            "The route presented onto a detached presenter — UIKit drops that on the floor and never retries"
        )
    }

    // MARK: - Content

    func testConfirmDeleteSheetShowsTitleBodyAndBothActions() {
        let expectedBody = AlarmDeletionCopy.body(balance: BalanceService.shared.balance)

        mountRoute()

        guard let sheet = waitForSizedSheet() else {
            return XCTFail(
                timeoutMessage("`-uitour confirm-delete` never presented a sized confirmation sheet.")
            )
        }
        let diagnostics = layoutDiagnostics()

        let title = contentView("confirmDelete.title", in: sheet) as? UILabel
        XCTAssertEqual(title?.text, "Удалить будильник?", "Sheet headline must be on screen")
        XCTAssertTrue(isVisible(title), "Sheet headline must be visible, not just allocated. \(diagnostics)")

        let body = contentView("confirmDelete.body", in: sheet) as? UILabel
        XCTAssertEqual(body?.text, expectedBody, "Sheet body must carry the balance reassurance copy")
        XCTAssertTrue(isVisible(body), "Sheet body must be visible. \(diagnostics)")

        let delete = contentView("confirmDelete.deleteButton", in: sheet) as? SPButton
        XCTAssertTrue(isVisible(delete), "Destructive action must be visible. \(diagnostics)")
        XCTAssertEqual(delete?.accessibilityLabel, "Удалить")

        let cancel = contentView("confirmDelete.cancelButton", in: sheet) as? SPButton
        XCTAssertTrue(isVisible(cancel), "Cancel action must be visible. \(diagnostics)")
        XCTAssertEqual(cancel?.accessibilityLabel, "Отмена")
    }

    /// The audit only ever saw a dimmed backdrop with a narrow strip at the
    /// bottom. Non-zero frames alone would not have caught that — assert the
    /// content actually lands INSIDE the window, which the wait predicate
    /// (size only) deliberately does not check.
    func testConfirmDeleteSheetContentIsOnScreen() {
        mountRoute()

        guard let sheet = waitForSizedSheet() else {
            return XCTFail(
                timeoutMessage("`-uitour confirm-delete` never presented a sized confirmation sheet.")
            )
        }
        let diagnostics = layoutDiagnostics()

        for identifier in contentIdentifiers {
            guard let found = contentView(identifier, in: sheet) else {
                XCTFail("\(identifier) missing from the presented sheet")
                continue
            }
            let frame = found.convert(found.bounds, to: window)
            XCTAssertFalse(frame.isEmpty, "\(identifier) must have a non-empty frame. \(diagnostics)")
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

    /// Waits until UIKit's presentation container has finished: the sheet is
    /// in the hierarchy AND its own view has been sized. Sizing the presented
    /// view is the container's job, not the sheet's, so it is legitimately
    /// asynchronous and worth waiting for.
    ///
    /// The content's geometry is deliberately NOT part of this predicate.
    /// Polling until the labels and buttons report non-empty bounds would mean
    /// waiting for the defect under test to fix itself — and #485 showed it
    /// never does: the sheet view was already the full 402×874 while its
    /// children stayed collapsed. A wait that can only ever time out is a
    /// worse failure message than an assertion, not a better one.
    private func waitForSizedSheet(timeout: TimeInterval = 10) -> ConfirmDeleteAlarmViewController? {
        let settled = waitForSheet(timeout: timeout) { candidate in
            guard let view = candidate.viewIfLoaded, view.window != nil else { return false }
            return !view.bounds.isEmpty
        }
        guard let sheet = settled else { return nil }
        // Exactly one layout flush, so the assertions read settled frames
        // instead of whatever the run loop happened to leave behind. One pass
        // is the entire budget on purpose: content that needs a second pass
        // here does not get one on a user's device either.
        window?.layoutIfNeeded()
        return sheet
    }

    /// The poll census and the elapsed stamp are the whole point of #728.
    ///
    /// A wait that ends empty says nothing about WHY, and the two candidates
    /// need opposite fixes: a run loop that was not turning (the route's own
    /// `asyncAfter` beat could not have been delivered either, so the drain in
    /// `setUp` simply did not reach the backlog) versus a loop that turned all
    /// the way through while the route declined to present. The census
    /// separates them, and the elapsed-versus-budget figure catches the third
    /// shape: an `XCTWaiter` cannot return while the loop is stuck, so a 10 s
    /// wait that took 20 s IS the stall, measured from the outside.
    private func waitForSheet(
        timeout: TimeInterval,
        until isReady: @escaping (ConfirmDeleteAlarmViewController) -> Bool
    ) -> ConfirmDeleteAlarmViewController? {
        var found: ConfirmDeleteAlarmViewController?
        let ready = XCTestExpectation(description: "confirm-delete sheet ready")
        let started = Date()
        var census = RunLoopCensus(interval: pollInterval, started: started)
        let poll = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] timer in
            census.record()
            guard let sheet = self?.presentedConfirmSheet(), isReady(sheet) else { return }
            found = sheet
            timer.invalidate()
            ready.fulfill()
        }
        defer { poll.invalidate() }
        let result = XCTWaiter.wait(for: [ready], timeout: timeout)
        let elapsed = Date().timeIntervalSince(started)
        waitEvidence = """
            Wait: \(result) after \(seconds(elapsed)) against a \(seconds(timeout)) budget \
            — \(census.summary())
            """
        return result == .completed ? found : nil
    }

    // MARK: - Evidence

    /// Mounts the route and stamps when the call returned, so a later timeout
    /// can say whether the wall clock went on `setUp`, on the mount, or inside
    /// the wait. In the red attempt those three were indistinguishable.
    private func mountRoute() {
        let started = Date()
        UITourLauncher.mount("confirm-delete", in: window)
        mountEvidence = "Mount returned after \(seconds(Date().timeIntervalSince(started)))."
    }

    /// The one message every timed-out wait prints.
    ///
    /// Order matters. The presentation chain is read FIRST, at the moment the
    /// wait gave up, so it describes that moment and not the aftermath. Only
    /// then does the queue get probed — and whether the sheet turns up *during*
    /// that probe is itself the discriminator this failure has been missing:
    /// a sheet that appears once the queue is spun again was late, so the beat
    /// was delivered and starved; a sheet still absent after it was never
    /// presented at all, and the queue is not the story.
    ///
    /// Bounded at 5 s, and only ever reached on a failing test, so it cannot
    /// grow a green run. It is emphatically not a wider timeout: by the time it
    /// runs, the failure is already going to be recorded.
    private func timeoutMessage(_ headline: String) -> String {
        let chainAtTimeout = presentationDiagnostics(rootedAt: window?.rootViewController)
        let probeStarted = Date()
        let probe = drainMainQueueOutcome(cap: 5)
        let probeElapsed = Date().timeIntervalSince(probeStarted)
        let queue = probe.isQuiet
            ? "a fresh probe came back in \(seconds(probeElapsed)) (\(probe))"
            : probe.diagnosis
        let afterwards = presentedConfirmSheet() == nil
            ? "the sheet was STILL absent afterwards — nothing was merely running late"
            : "the sheet APPEARED during that probe — the presentation was late, not declined"
        return """
            \(headline) \(chainAtTimeout) \(setUpEvidence) \(mountEvidence) \(waitEvidence) \
            After the timeout: \(queue), and \(afterwards).
            """
    }

    private func seconds(_ value: TimeInterval) -> String {
        return String(format: "%.2f s", value)
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
