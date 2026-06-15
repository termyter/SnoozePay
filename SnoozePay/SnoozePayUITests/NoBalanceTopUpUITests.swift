import XCTest

/// E2e for the no-balance → top-up recovery path on the firing screen.
///
/// `-uitour firing-nobalance` mounts `AlarmFiringViewController` with a forced
/// zero balance, so the disabled snooze card + «Пополнить» CTA are up and the
/// normal snooze CTA is suppressed. Tapping «Пополнить» credits the balance
/// (StoreKit isn't configured in the UI-test host, so the VC's documented
/// `BalanceService.topUp` fallback runs) and the `balanceChanged` observer
/// flips the screen back to the affordable snooze CTA.
///
/// Selectors are stable `accessibilityIdentifier`s, not localized copy.
final class NoBalanceTopUpUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNoBalanceTopUpRestoresSnooze() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "firing-nobalance", "-uitour-seed"]
        app.launch()

        // 1. No-balance state: «Пополнить» CTA present, snooze CTA suppressed.
        let topUp = app.buttons["firing.noBalance.topUp"]
        let snooze = app.buttons["firing.snoozeButton"]
        XCTAssertTrue(topUp.waitForExistence(timeout: 10),
                      "No-balance «Пополнить» CTA should appear when balance is 0")
        XCTAssertFalse(snooze.exists,
                       "The normal snooze CTA must be hidden while balance is 0")

        // 2. Top up → balance crosses the affordability threshold.
        topUp.tap()

        // 3. The balance-changed observer flips back to the snooze CTA.
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Snooze CTA should return once the top-up credits the balance")
        XCTAssertFalse(topUp.exists,
                       "No-balance «Пополнить» CTA should be gone after recovery")
    }
}
