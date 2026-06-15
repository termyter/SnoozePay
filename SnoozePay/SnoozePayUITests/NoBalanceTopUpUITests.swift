import XCTest

/// End-to-end for the no-balance recovery loop on the firing screen.
///
/// Drives the REAL `AlarmFiringViewController` in its no-balance layout via the
/// DEBUG `-uitour firing-nobalance` deep link (`UITourLauncher`), which forces
/// the balance to 0 before mounting. The path exercised:
///
///   1. No-balance layout up — the «Пополнить» top-up CTA is present and the
///      normal snooze CTA is NOT (it lives behind the no-balance swap).
///   2. Tap «Пополнить» → with StoreKit products not loaded in the test
///      environment, `noBalanceApplePayTapped` falls back to a direct
///      `BalanceService.topUp`, crediting the balance deterministically.
///   3. The balance observer re-runs `updateUI`, the no-balance swap flips back,
///      and the normal `firing.snoozeButton` becomes available again.
///
/// Selectors are stable `accessibilityIdentifier`s, not localized button copy
/// (the top-up CTA reads «Пополнить», so id-targeting is mandatory here).
final class NoBalanceTopUpUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNoBalanceTopUpReenablesSnooze() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "firing-nobalance"]
        app.launch()

        // 1. No-balance layout — top-up CTA present, normal snooze absent.
        let topUp = app.buttons["firing.noBalance.topUpButton"]
        XCTAssertTrue(topUp.waitForExistence(timeout: 10),
                      "No-balance top-up CTA should appear when balance is 0")
        XCTAssertFalse(app.buttons["firing.snoozeButton"].exists,
                       "Normal snooze CTA should be hidden in the no-balance layout")

        // 2 + 3. Top up → snooze becomes available again.
        topUp.tap()
        let snooze = app.buttons["firing.snoozeButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Snooze CTA should re-appear after the balance is topped up")
        XCTAssertTrue(snooze.isEnabled,
                      "Re-appeared snooze CTA should be enabled with a positive balance")
    }
}
