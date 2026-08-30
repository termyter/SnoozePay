import XCTest

/// End-to-end guard for the DEBUG `-uitour confirm-delete` deep link (#467) —
/// the exact entry point the visual-audit harness screenshots.
///
/// The route used to schedule the alarm-edit form's presentation and the
/// confirmation sheet's presentation on the same 0.8 s deadline, so the sheet
/// asked a still-transitioning navigation controller to present and was
/// silently dropped: captures showed the dimmed backdrop and nothing else.
/// This test fails on exactly that regression, at the same level the audit
/// operates — a real launch, not an in-process mount.
///
/// Selectors are stable `accessibilityIdentifier`s, not the localized copy.
final class ConfirmDeleteRouteUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Terminate explicitly so a leftover modal can't survive into the next
        // E2E class's launch() (#438).
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testConfirmDeleteRouteShowsTitleBodyAndBothActions() {
        let app = XCUIApplication()
        // `-uitour-alarmkit granted` states the backend rather than inheriting
        // the simulator's (#626) — no class may leave an authorization prompt
        // to chance, including the ones that never schedule anything.
        app.launchArguments = ["-uitour", "confirm-delete", "-uitour-alarmkit", "granted"]
        app.launch()

        let title = app.staticTexts["confirmDelete.title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 15),
            "`-uitour confirm-delete` must present the confirmation sheet, not just the scrim"
        )

        let body = app.staticTexts["confirmDelete.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Sheet body copy must be on screen")
        XCTAssertFalse(body.label.isEmpty, "Sheet body copy must not be blank")

        let delete = app.buttons["confirmDelete.deleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Destructive action must be on screen")
        XCTAssertTrue(delete.isHittable, "Destructive action must be tappable, not clipped off-screen")

        let cancel = app.buttons["confirmDelete.cancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Cancel action must be on screen")
        XCTAssertTrue(cancel.isHittable, "Cancel action must be tappable, not clipped off-screen")
    }
}
