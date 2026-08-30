import XCTest

/// End-to-end PoC for the core firing → snooze → wake loop.
///
/// Drives the REAL `AlarmFiringViewController` through the DEBUG `-uitour`
/// deep link (`UITourLauncher`), which mounts the firing screen directly as
/// the window root with a seeded balance — no onboarding / tab navigation to
/// tap through. The flow exercised here is the single most important path in
/// the product:
///
///   1. Firing screen up (snooze CTA + «Я встал» both present).
///   2. Tap «Поспать ещё» → the screen transitions IN PLACE into the snoozed
///      state with a live countdown (it deliberately does not dismiss, #226).
///   3. Tap «Я встал — выключить» → the WokeMorning summary is presented.
///   4. Tap «Закрыть» → the summary unwinds back to the firing screen.
///
/// This is intentionally ONE test: a stability probe. If it runs reliably and
/// green on CI, the e2e suite is worth expanding; if XCUITest proves flaky on
/// the CI simulator, we keep e2e thin and lean on unit tests. Selectors are
/// stable `accessibilityIdentifier`s, not localized button copy.
final class FiringFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Fail fast: a missing element early means the later steps are
        // meaningless, and the first failure is the diagnostic that matters.
        continueAfterFailure = false
    }

    override func tearDown() {
        // Terminate the app under test so a leftover firing/snooze instance
        // can't survive into the next E2E class's launch() and make its
        // implicit terminate fail (#438).
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testFiringSnoozeWakeFlow() {
        let app = XCUIApplication()
        // `-uitour firing` mounts AlarmFiringViewController as root;
        // `-uitour-balance 1000` guarantees the snooze is affordable so the
        // flow reaches the snoozed state rather than the no-balance layout.
        // `-uitour-alarmkit denied` states the backend this flow runs on
        // instead of inheriting whatever the simulator answers (#626): the
        // in-place snoozed state below exists only on a backend that does NOT
        // arm the next ring itself — on an authorized one the screen closes
        // and the system owns it (#383).
        app.launchArguments = [
            "-uitour", "firing", "-uitour-balance", "1000", "-uitour-alarmkit", "denied"
        ]
        app.launch()

        // 1. Firing screen — snooze CTA + «Я встал» dismiss are both present.
        let snooze = app.buttons["firing.snoozeButton"]
        let dismiss = app.buttons["firing.dismissButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Firing snooze CTA should appear on launch")
        XCTAssertTrue(dismiss.exists,
                      "«Я встал» dismiss button should be present on the firing screen")

        // 2. Snooze → the refusal is stated, then the snoozed state with a live
        // countdown appears in place. On the denied backend the schedule is
        // refused (#472) and the screen says so before anything else can be
        // tapped — clear that alert here, deliberately, rather than leaving it
        // to XCUITest (see `dismissAppAlert`).
        snooze.tap()
        XCTAssertTrue(dismissAppAlert(in: app, timeout: 10),
                      "A snooze refused by an unauthorized backend should explain itself")
        let countdown = app.staticTexts["firing.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 5),
                      "Snoozed-state countdown should appear after «Поспать ещё»")

        // 3. «Я встал — выключить» → the WokeMorning summary is presented.
        dismiss.tap()
        let wokeClose = app.buttons["woke.closeButton"]
        XCTAssertTrue(wokeClose.waitForExistence(timeout: 5),
                      "WokeMorning summary with «Закрыть» should appear after dismiss")

        // 4. «Закрыть» → the summary unwinds back to the firing screen.
        wokeClose.tap()
        XCTAssertTrue(snooze.waitForExistence(timeout: 5),
                      "Closing the summary should return to the firing screen")
        XCTAssertFalse(wokeClose.exists,
                       "WokeMorning summary should be gone after «Закрыть»")
    }
}

// MARK: - Alert handling shared by the E2E classes

/// Why every E2E class dismisses the app's own alerts by hand instead of
/// letting XCUITest do it — the mechanism behind #626.
///
/// When an alert covers the element a test is about to touch, XCUITest calls
/// it an *interrupting element* and runs the default interruption handler.
/// That handler taps a button **once**, waits for the app to go idle, then
/// gives itself a fixed 1.0 s for the alert to disappear. If the alert is
/// still there it does not tap again: it falls through to a last-ditch
/// predicate matching only English labels (`label CONTAINS[d] "Don’t" OR
/// label CONTAINS "Cancel"`), finds nothing in a Russian alert, logs
/// `unable to find any qualified button` and gives up **for the rest of the
/// test**. From that point every tap resolves to `Computed hit point
/// {-1, -1}` and every `waitForExistence` after it times out against a
/// covered screen.
///
/// The single tap is the whole problem. In both #626 failures the app was
/// *idle* when the check ran and the alert was still up — 2.3 s after the tap
/// in run 33295307930, 10 s after it in run 33295938983. That is not the app
/// being slow, that is the synthesized touch being dropped, the same failure
/// this suite already documents in `OnboardingFlowUITests` (#523). Which test
/// dies is decided by which one drew the dropped touch, which is exactly the
/// reported signature: different test each run, always on a
/// `waitForExistence` right after a tap.
///
/// So the cure is the one #523 landed on: re-tap while the state the app
/// controls has not changed, and fail loudly if it never does — instead of
/// one blind tap and a silent surrender that poisons every later step.
///
/// It lives in this file rather than its own because `SnoozePayUITests` is a
/// plain group in `project.pbxproj` — adding a file there is a PM-zone edit.
extension XCTestCase {

    /// Wait for an app-owned alert and dismiss it, re-tapping while it is
    /// still up. Returns `false` when no alert showed up inside `timeout` —
    /// callers decide whether that is a failure or the normal case.
    ///
    /// Always button 0. Every alert a tour launch can raise is either
    /// single-action («Ок») or cancel-first («Отмена» then «Настройки»), and
    /// the second button of the latter leaves the app for Settings — so index
    /// 0 is the only safe choice.
    ///
    /// Re-tapping cannot double-fire into the screen underneath: the loop
    /// re-checks that the alert is still on top before every tap, so a tap
    /// that landed ends it. Stacked alerts are dismissed the same way, one per
    /// pass — the tour can raise two (a launch-time one plus a flow one) and
    /// leaving the second up is indistinguishable from a dropped touch.
    @discardableResult
    func dismissAppAlert(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return false }

        var taps = 0
        while taps < 4, alert.exists {
            let button = alert.buttons.element(boundBy: 0)
            guard button.exists else { break }
            button.tap()
            taps += 1
            _ = alert.waitForNonExistence(timeout: 5)
        }

        XCTAssertFalse(alert.exists,
                       "Alert «\(alert.label)» should be gone after \(taps) tap(s) on its first button")
        return true
    }
}
