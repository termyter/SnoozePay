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
        assertAlarmClock(in: app, alarmNoun: "Alarm", expectedTime: "7:00")
        app.terminate()

        launch(app, language: "ru", region: "en_US", screen: "alarms")
        XCTAssertTrue(app.tabBars.buttons["Будильники"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Кошелёк"].exists)
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches.count, 1)
        // This catches a return to hardcoded ru_RU display formatting even
        // though the unit-test fixture itself runs with a Russian region.
        assertAlarmClock(in: app, alarmNoun: "Будильник", expectedTime: "7:00 AM")
    }

    /// AlarmCell exposes the card as one VoiceOver summary, hiding its child
    /// clock label. Read that real row's opening segment instead of querying a
    /// standalone static text that is deliberately absent from accessibility.
    private func assertAlarmClock(
        in app: XCUIApplication, alarmNoun: String, expectedTime: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let summary = app.tables.cells.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", alarmNoun + " ")).firstMatch
        guard summary.exists else {
            XCTFail("The saved alarm must expose its localized card summary", file: file, line: line)
            return
        }
        let opening = summary.label.split(separator: ",", maxSplits: 1).first ?? ""
        // ICU uses a narrow no-break space before AM; retain an exact time
        // comparison while accepting the platform's whitespace spelling.
        let normalized = opening.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        XCTAssertEqual(normalized, "\(alarmNoun) \(expectedTime)", file: file, line: line)
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
