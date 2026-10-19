import XCTest

/// Explicit DEBUG visual fixture for the retained progressive snoozed chrome.
/// It seeds count/anchor directly without charging or pretending that a denied
/// production snooze succeeded. Real scheduling outcomes live in FiringFlowUITests.
final class ProgressiveSnoozeUITests: XCTestCase {

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

    func testLargeProgressiveAlarmOpensInitialRingWithZeroWalletBeforePayment() {
        for price in ["4611686018427387904", "9223372036854775808"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-uitour", "firing-progressive", "-uitour-penalty", price,
                "-uitour-balance", "0", "-uitour-alarmkit", "granted"
            ]
            app.launch()
            XCTAssertTrue(app.buttons["firing.noBalance.topUpButton"].waitForExistence(timeout: 10),
                          "Initial ringing layout must finish for a large progressive price")
            let priceCard = app.buttons["firing.noBalance.snoozePrice"]
            XCTAssertTrue(priceCard.waitForExistence(timeout: 5))
            XCTAssertFalse(priceCard.isEnabled)
            let renderedPrice = priceCard.value as? String ?? ""
            let digits = renderedPrice.filter { $0 >= "0" && $0 <= "9" }
            XCTAssertEqual(digits, price,
                           "The rendered price must match the large fixture, not the default 50")
            let zeroBalance = app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS[c] %@ AND label ENDSWITH %@", "баланс", "0\u{202F}₽"
            )).firstMatch
            XCTAssertTrue(zeroBalance.exists, "The initial ring must have a zero wallet")
            XCTAssertFalse(app.staticTexts["firing.countdown"].exists, "No snooze payment was attempted")
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

    func testProgressiveSnoozeShowsPillAndLadder() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitour", "firing-progressive-snoozed", "-uitour-balance", "1000",
            "-uitour-alarmkit", "granted"
        ]
        app.launch()

        let countdown = app.staticTexts["firing.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 10),
                      "The explicit visual fixture should mount the countdown directly")
        XCTAssertFalse(app.alerts.firstMatch.exists, "A visual fixture must not attempt a refused snooze")

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
