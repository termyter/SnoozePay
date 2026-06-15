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

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testProgressiveSnoozeShowsPillAndLadder() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "firing-progressive", "-uitour-balance", "1000"]
        app.launch()

        // 1. Firing screen — affordable snooze present.
        let snooze = app.buttons["firing.snoozeButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Progressive firing screen should show the snooze CTA")

        // 2. Snooze → snoozed state in place (live countdown).
        snooze.tap()
        let countdown = app.staticTexts["firing.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 5),
                      "Snoozed-state countdown should appear after «Поспать ещё»")

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
