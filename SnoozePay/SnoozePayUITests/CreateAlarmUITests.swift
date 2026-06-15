import XCTest

/// E2e for creating an alarm and seeing it land in the list.
///
/// `-uitour create` presents `CreateAlarmViewController` over the alarms tab.
/// The test types a unique name, taps «Готово», and asserts the modal unwinds
/// and the new alarm shows up in the list (the list reloads on
/// `viewWillAppear`). The default time/penalty are left untouched — the wheel
/// picker is deliberately not driven, since this flow only needs to prove the
/// create → persist → list-refresh loop end to end.
///
/// Selectors are stable `accessibilityIdentifier`s; the new row is matched by
/// the (uppercased, case-insensitively compared) name we typed.
final class CreateAlarmUITests: XCTestCase {

    /// A token unlikely to collide with the seeded alarms (Работа / Спортзал /
    /// Рейс в Стамбул). ASCII keeps simulator keyboard entry reliable.
    private let alarmName = "ZZ UITEST"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCreateAlarmAppearsInList() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "create", "-uitour-seed"]
        app.launch()

        // 1. Create form presents — the name field is up.
        let nameField = app.textFields["create.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10),
                      "Create form should present with the name field")

        // 2. Name the alarm.
        nameField.tap()
        nameField.typeText(alarmName)

        // 3. Save.
        let save = app.buttons["create.saveButton"]
        XCTAssertTrue(save.exists, "«Готово» save button should be present")
        save.tap()

        // 4. The form dismisses and the new alarm shows up in the list. The
        //    eyebrow is uppercased, so compare case-insensitively.
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 10),
                      "Create form should dismiss after saving")
        let created = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", alarmName))
            .firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10),
                      "The newly created alarm should appear in the list")
    }
}
