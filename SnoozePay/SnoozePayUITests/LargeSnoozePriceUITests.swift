import XCTest

/// #928: native text input -> keyboard Done -> save -> reopen -> price-cell reuse.
final class LargeSnoozePriceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testIntMaxCustomPriceSurvivesSaveReopenAndScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "create", "-uitour-reset", "-uitour-alarmkit", "granted"]
        app.launch()
        XCTAssertTrue(app.textFields["createAlarm.nameField"].waitForExistence(timeout: 10))
        let price = revealPrice(in: app)
        let focusedPrice = app.textFields.matching(identifier: "createAlarm.penaltyField")
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        var taps = 0
        while taps < 3, !focusedPrice.exists {
            price.tap()
            taps += 1
            _ = focusedPrice.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(focusedPrice.exists, "The price field must receive native keyboard input")
        let oldText = price.value as? String ?? ""
        price.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldText.count)
                       + "9223372036854775807")
        XCTAssertEqual(price.value as? String, "9223372036854775807")
        let done = app.buttons["createAlarm.penaltyDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertEqual(price.value as? String, "9223372036854775808")
        app.buttons["createAlarm.saveButton"].tap()
        XCTAssertTrue(app.textFields["createAlarm.nameField"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        app.tables.cells.firstMatch.tap()
        XCTAssertTrue(app.textFields["createAlarm.nameField"].waitForExistence(timeout: 5))
        XCTAssertEqual(revealPrice(in: app).value as? String, "9223372036854775808")

        let name = app.textFields["createAlarm.nameField"]
        var scrolls = 0
        while scrolls < 8, !name.isHittable {
            app.tables.firstMatch.swipeDown()
            scrolls += 1
        }
        XCTAssertTrue(name.isHittable, "Scroll away from the price card before returning to it")
        XCTAssertEqual(revealPrice(in: app).value as? String, "9223372036854775808")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func revealPrice(in app: XCUIApplication) -> XCUIElement {
        let price = app.textFields["createAlarm.penaltyField"]
        var scrolls = 0
        while scrolls < 8, !price.isHittable {
            app.tables.firstMatch.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(price.exists && price.isHittable, "The snooze-price card must be reachable")
        return price
    }
}
