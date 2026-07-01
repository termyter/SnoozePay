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
        app.launchArguments = ["-uitour", "firing", "-uitour-balance", "1000"]
        app.launch()

        // 1. Firing screen — snooze CTA + «Я встал» dismiss are both present.
        let snooze = app.buttons["firing.snoozeButton"]
        let dismiss = app.buttons["firing.dismissButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Firing snooze CTA should appear on launch")
        XCTAssertTrue(dismiss.exists,
                      "«Я встал» dismiss button should be present on the firing screen")

        // 2. Snooze → snoozed state with a live countdown appears in place.
        snooze.tap()
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
