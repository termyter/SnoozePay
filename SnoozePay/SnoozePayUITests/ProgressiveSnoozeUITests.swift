import XCTest

/// End-to-end for the progressive-scale snooze chrome.
///
/// Drives the REAL `AlarmFiringViewController` for a `progressiveScale: true`
/// alarm via `-uitour firing-progressive` (`UITourLauncher`), with a seeded
/// balance so the snooze is affordable. The path exercised:
///
///   1. Firing screen up with the progressive sample alarm.
///   2. Tap «Поспать ещё» → the screen enters the snoozed state in place.
///   3. The progressive pill («Прогрессив · 1-й поспать ещё») and the growing
///      charge ladder render — the chrome that only appears for progressive
///      alarms, proving the escalation UI is wired through the firing flow.
///
/// Selectors are stable `accessibilityIdentifier`s.
final class ProgressiveSnoozeUITests: XCTestCase {

    /// Title of `firing.alert.snooze_not_scheduled` as the user sees it.
    /// Spelled here because XCUITest is out of process and cannot read the
    /// app's string catalogue; see `dismissAppAlert` for why the title must be
    /// named at all.
    private static let refusalAlertTitle = "Откладывание не запланировано"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Terminate the app under test so a leftover firing/snooze instance
        // can't survive into the next E2E class's launch() and make its
        // implicit terminate fail (#438).
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testProgressiveSnoozeShowsPillAndLadder() {
        let app = XCUIApplication()
        // `-uitour-alarmkit denied` for the same reason as in
        // `FiringFlowUITests`: the snoozed state this test is about only
        // exists on a backend that does not arm the next ring itself, so the
        // test states that backend instead of inheriting the simulator's.
        app.launchArguments = [
            "-uitour", "firing-progressive", "-uitour-balance", "1000",
            "-uitour-alarmkit", "denied"
        ]
        app.launch()

        // 1. Firing screen — affordable snooze present.
        let snooze = app.buttons["firing.snoozeButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Progressive firing screen should show the snooze CTA")

        // 2. Snooze → the refusal is stated, then the snoozed state in place.
        snooze.tap()
        XCTAssertTrue(
            dismissAppAlert(in: app, titled: Self.refusalAlertTitle, timeout: 10),
            "A snooze refused by an unauthorized backend should explain itself"
        )

        // ⚠️ This assertion pins behaviour that is KNOWN TO BE WRONG — see #641.
        // On a denied backend `scheduleSnooze` calls its completion
        // synchronously, so `exitSnoozedState()` runs before the state is
        // active (a no-op) and `enterSnoozedState()` then builds a countdown to
        // a ring that will never happen, behind an alert that just said it will
        // never happen. The countdown below IS that bug.
        //
        // It is asserted rather than inverted because it is what the app does
        // today, and a test that fails on unchanged code is worse than one that
        // documents the defect. When #641 is fixed, THIS TEST GOING RED IS
        // EXPECTED — it is not a sign the fix is wrong. Replace the assertion
        // with one on the active firing UI (or delete the snoozed-state tests
        // outright, if PM decides foreground snooze goes away with it).
        let countdown = app.staticTexts["firing.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 5),
                      "Snoozed-state countdown should appear after «Поспать ещё» (see #641)")

        // 3. Progressive chrome — the pill names the next snooze ordinal.
        let pill = app.staticTexts["firing.snoozed.progressivePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5),
                      "Progressive pill should appear in the snoozed state for a progressive alarm")
        XCTAssertTrue(pill.label.contains("поспать ещё"),
                      "Progressive pill should read the «N-й поспать ещё» escalation copy, got: \(pill.label)")

        // The growing charge ladder is a sibling container in the same state.
        XCTAssertTrue(app.otherElements["firing.snoozed.ladder"].exists,
                      "Charge ladder should render alongside the progressive pill")
    }
}
