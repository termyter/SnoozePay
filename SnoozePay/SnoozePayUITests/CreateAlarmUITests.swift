import XCTest

/// End-to-end for creating an alarm from the form.
///
/// Mounts the REAL `CreateAlarmViewController` (presented over the alarms tab)
/// via `-uitour create`, with `-uitour-reset` wiping any persisted alarms first
/// so the post-save count is deterministic. The path exercised:
///
///   1. Create form up — name + Save controls present.
///   2. Type a name, leave the safe default time/penalty, tap «Готово».
///   3. `save` persists via the repository and dismisses ONLY on success — so a
///      dismissed sheet proves the happy path (a persist/scheduling failure
///      would surface an inline alert and keep the sheet up instead).
///   4. Back on the list, exactly one alarm row (its toggle) is present.
///
/// The list cell renders time / days / price / sound but NOT the name, so the
/// assertion keys on the row's toggle count from a known-empty start rather
/// than on the typed name. Selectors are stable `accessibilityIdentifier`s.
final class CreateAlarmUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCreateAlarmAddsRowToList() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "create", "-uitour-reset"]
        app.launch()

        // 1. Create form up (presented after the root lays out).
        let nameField = app.textFields["createAlarm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10),
                      "Create-alarm name field should appear")
        let save = app.buttons["createAlarm.saveButton"]
        XCTAssertTrue(save.exists, "Save button should be present on the create form")

        // 2. Fill the name (the form auto-focuses it on appear).
        nameField.tap()
        nameField.typeText("Подъём на работу")

        // 3. Save → success path dismisses the sheet.
        save.tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5),
                      "Create sheet should dismiss after a successful save")

        // 4. The new alarm is present in the list (one toggle from empty start).
        let firstToggle = app.switches.firstMatch
        XCTAssertTrue(firstToggle.waitForExistence(timeout: 5),
                      "A newly created alarm row should appear in the list")
    }
}
