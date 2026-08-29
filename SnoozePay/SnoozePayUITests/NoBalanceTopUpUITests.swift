import XCTest

/// End-to-end for the no-balance recovery loop on the firing screen.
///
/// Drives the REAL `AlarmFiringViewController` in its no-balance layout via the
/// DEBUG `-uitour firing-nobalance` deep link (`UITourLauncher`), which forces
/// the balance to 0 before mounting. The path exercised:
///
///   1. No-balance layout up — the «Пополнить» top-up CTA is present and the
///      normal snooze CTA is NOT (it lives behind the no-balance swap).
///   2. Tap «Пополнить» → `noBalanceApplePayTapped` falls back to a direct
///      `BalanceService.topUp`, crediting the balance deterministically.
///      The empty catalogue is FORCED by `-uitour-storekit-empty`, not assumed:
///      see the launch arguments below.
///   3. The balance observer re-runs `updateUI`, the no-balance swap flips back,
///      and the normal `firing.snoozeButton` becomes available again.
///
/// Selectors are stable `accessibilityIdentifier`s, not localized button copy
/// (the top-up CTA reads «Пополнить», so id-targeting is mandatory here).
///
/// #575 — this test used to leave step 2 to chance. It relied on the catalogue
/// being empty without saying so, which held only while the app was built under
/// a bundle ID that matched no app in App Store Connect. The moment the real
/// `io.mobilife.SnoozePay` landed, all five SKUs resolved on the CI simulator,
/// the tap reached the real `StoreKitService.purchase(_:)`, and iOS put up a
/// "Sign in to Apple Account" dialog — balance stayed 0 ₽ and the snooze CTA
/// never came back. `-uitour-storekit-empty` states the precondition instead,
/// so the result no longer depends on whether the App Store answered.
final class NoBalanceTopUpUITests: XCTestCase {

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

    func testNoBalanceTopUpReenablesSnooze() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "firing-nobalance", "-uitour-storekit-empty"]
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
