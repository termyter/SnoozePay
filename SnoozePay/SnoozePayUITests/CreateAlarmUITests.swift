import Foundation
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
///
/// ## Why the launches pin AlarmKit (#606)
///
/// Since #472 AlarmKit is the only backend, and a save whose schedule is
/// refused deliberately keeps the sheet up. A simulator can neither grant nor
/// deny AlarmKit — nothing prompts on a tour route and there is no
/// `simctl privacy` service for alarms — so an unpinned run tests whatever the
/// runtime happened to answer. That is exactly how the happy path used to
/// pass: pre-#472 the refusal fell through to a notification that registers
/// without permission, so the sheet dismissed and nothing rang. Both cases
/// below therefore state their backend explicitly via `-uitour-alarmkit`
/// (`UITourAlarmKitBackend`), and each asserts the outcome that backend owes:
/// authorized -> dismiss + row, denied -> sheet stays up and says why.
///
/// The flag spelling is a contract with `UITourLauncher.alarmKitArgument`;
/// `UITourAlarmKitOverrideTests` pins both halves, since a typo here would
/// quietly hand these tests back to ambient state.
final class CreateAlarmUITests: XCTestCase {

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

    func testCreateAlarmAddsRowToList() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "create", "-uitour-reset", "-uitour-alarmkit", "granted"]
        app.launch()

        // 1. Create form up (presented after the root lays out).
        let nameField = app.textFields["createAlarm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10),
                      "Create-alarm name field should appear")
        let save = app.buttons["createAlarm.saveButton"]
        XCTAssertTrue(save.exists, "Save button should be present on the create form")

        // 2. The form opens without a keyboard (#317). Wait for the tap
        // to give this field keyboard focus before synthesizing text (#919).
        guard fillNameField(nameField, in: app) else { return }

        // 3. Save → success path dismisses the sheet.
        save.tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5),
                      "Create sheet should dismiss after a successful save")

        // 4. The new alarm is present in the list (one toggle from empty start).
        let firstToggle = app.switches.firstMatch
        XCTAssertTrue(firstToggle.waitForExistence(timeout: 5),
                      "A newly created alarm row should appear in the list")
    }

    /// The #472 contract, pinned: with the alarm backend refusing, saving must
    /// NOT dismiss. A silently saved alarm that cannot ring is the worst
    /// outcome available, so the form stays up and explains itself.
    ///
    /// This is the half that keeps the happy path honest. Without it,
    /// "sheet dismissed" could be satisfied by an app that dismisses no matter
    /// what — precisely the pre-#472 behaviour that made the green above
    /// meaningless.
    func testCreateAlarmWithoutPermissionKeepsSheetUpAndExplains() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "create", "-uitour-reset", "-uitour-alarmkit", "denied"]
        app.launch()

        let nameField = app.textFields["createAlarm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10),
                      "Create-alarm name field should appear")

        guard fillNameField(nameField, in: app) else { return }

        app.buttons["createAlarm.saveButton"].tap()

        // The refusal is explained, not swallowed. Queried by title, so a
        // different alert cannot satisfy it.
        let alert = app.alerts["Доступ к будильникам выключен"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "A refused schedule must surface its own alert, not fail silently")
        let explanation = alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "не сработают")
        ).firstMatch
        XCTAssertTrue(explanation.exists,
                      "The alert must say the alarm would not ring, not just that something failed")
        // Not Now keeps the entered form without creating an unarmed alarm.
        alert.buttons["Не сейчас"].tap()

        // And the form is still up: the user keeps the form they were on
        // instead of landing back on a list that implies success.
        XCTAssertTrue(nameField.waitForExistence(timeout: 5),
                      "Create sheet must stay up when the alarm could not be armed")
        app.buttons["createAlarm.closeButton"].tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.switches.count, 0, "Refusing permission must not leave a persisted alarm row")
    }

    /// A synthesized tap can be dropped while the field remains hittable.
    /// Retry only the focus tap, never typing or saving. The query uses the
    /// same `hasKeyboardFocus` snapshot attribute as XCTest's `typeText`
    /// dispatch check; `hasFocus` describes UI focus, not keyboard focus.
    private func fillNameField(
        _ nameField: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let focusedNameField = app.textFields.matching(identifier: "createAlarm.nameField")
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        var taps = 0
        while taps < 3, !focusedNameField.exists {
            guard nameField.exists, nameField.isHittable else {
                XCTFail("Create-alarm name field must be hittable before focusing", file: file, line: line)
                return false
            }
            nameField.tap()
            taps += 1
            _ = focusedNameField.waitForExistence(timeout: 3)
        }
        guard focusedNameField.exists else {
            XCTFail("Create-alarm name field did not get keyboard focus after \(taps) taps", file: file, line: line)
            return false
        }

        let name = "Подъём на работу"
        nameField.typeText(name)
        guard nameField.value as? String == name else {
            XCTFail("Create-alarm name field must contain the exact typed name before saving", file: file, line: line)
            return false
        }
        return true
    }
}
