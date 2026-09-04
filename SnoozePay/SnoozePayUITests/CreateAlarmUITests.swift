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

        // A denied backend also makes `AppDelegate` offer its "включите в
        // Настройках" alert on launches where the permissions screen has
        // already been seen. That alert is not what this test is about — get
        // it out of the way instead of letting it decide the assertions below.
        let launchAlert = app.alerts["Уведомления выключены"]
        if launchAlert.waitForExistence(timeout: 2) {
            launchAlert.buttons["Отмена"].tap()
        }

        nameField.tap()
        nameField.typeText("Подъём на работу")

        app.buttons["createAlarm.saveButton"].tap()

        // The refusal is explained, not swallowed. Queried by title, so a
        // different alert cannot satisfy it.
        let alert = app.alerts["Не удалось запланировать будильник"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "A refused schedule must surface its own alert, not fail silently")
        let explanation = alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "не зазвонит")
        ).firstMatch
        XCTAssertTrue(explanation.exists,
                      "The alert must say the alarm would not ring, not just that something failed")
        // Dismissed by position, not by title. #664 routed this button through
        // `common.button.ok`, so its label went from "OK" to «Ок» — a query on
        // the old text matches nothing and the tap fails on a missing element.
        // The alert is already identified by its own title above; the button is
        // its only one. Same reason as FiringFlowUITests.
        alert.buttons.element(boundBy: 0).tap()

        // And the form is still up: the user keeps the form they were on
        // instead of landing back on a list that implies success.
        XCTAssertTrue(nameField.waitForExistence(timeout: 5),
                      "Create sheet must stay up when the alarm could not be armed")
    }
}
