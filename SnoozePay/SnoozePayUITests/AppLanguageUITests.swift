import Foundation
import XCTest

/// Real app-process language overrides, including English text with a Russian
/// region. No language-specific production DEBUG switch is involved.
final class AppLanguageUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testLanguageChangesOnRestartWithoutLosingTheSavedAlarm() {
        let app = XCUIApplication()
        launch(app, language: "ru", screen: "create", reset: true)
        let name = app.textFields["createAlarm.nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["ПОДЪЁМ"].exists)
        app.buttons["createAlarm.saveButton"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches.count, 1)
        app.terminate()

        // No reset, seed or reinstall: this launch must read the saved alarm.
        launch(app, language: "en", screen: "alarms")
        XCTAssertTrue(app.tabBars.buttons["Alarms"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Wallet"].exists)
        XCTAssertTrue(app.tabBars.buttons["Statistics"].exists)
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches.count, 1)
        // A Russian region keeps 24-hour formatting even for English copy.
        XCTAssertTrue(app.staticTexts["7:00"].exists)
        app.terminate()

        launch(app, language: "ru", region: "en_US", screen: "alarms")
        XCTAssertTrue(app.tabBars.buttons["Будильники"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Кошелёк"].exists)
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches.count, 1)
        // This catches a return to hardcoded ru_RU display formatting even
        // though the unit-test fixture itself runs with a Russian region.
        let twelveHourClock = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label ENDSWITH %@", "7:00", "AM"
        )).firstMatch
        XCTAssertTrue(twelveHourClock.exists)
    }

    private func launch(
        _ app: XCUIApplication, language: String, region: String = "ru_RU",
        screen: String, reset: Bool = false
    ) {
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", region,
            "-uitour", screen, "-uitour-alarmkit", "granted"
        ] + (reset ? ["-uitour-reset"] : [])
        app.launch()
    }
}
