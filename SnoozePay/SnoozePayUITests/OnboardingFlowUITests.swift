import Foundation
import XCTest

/// End-to-end walk through the first-launch journey.
///
/// Mounts the REAL `OnboardingViewController` via `-uitour onboarding`, which
/// (in tour mode) wires the production `onFinished` chain onboarding →
/// `PermissionsViewController` → main tab bar — the same order SceneDelegate
/// drives on a real first launch. The path exercised:
///
///   1. Onboarding up — the primary «Дальше» CTA present.
///   2. Advance to the deposit page (page 3), where the CTA becomes «Пополнить».
///   3. Tapping it finishes onboarding and the permissions screen appears
///      with its «Готово» CTA.
///   4. Tapping «Готово» lands on the main tab bar.
///
/// **Why every step retries instead of tapping a fixed number of times (#523).**
/// The original shape was "tap `onboarding.primaryButton` exactly 3 times, then
/// assert «Готово»", with a `waitForExistence` between taps. That guard cannot
/// fail: the id is stable across all three pages by design, so it is satisfied
/// whether or not the previous tap moved the pager. The test therefore could
/// neither notice nor recover from a synthesized touch that the automation
/// session dropped — and on run 33186975424 exactly that happened: XCTest
/// recorded three tap events at the same correct point (201, 740), the screen
/// recording shows only two page advances, and the failure hierarchy shows the
/// app parked on page 3 with «Пополнить, 500 ₽» still up. One tap short. The
/// same commit is green on re-run (33243663469), so this is a lost touch on a
/// loaded runner, not app behaviour.
///
/// The cure is to key each step on a state the app itself changes, and to
/// re-tap while that state has not arrived:
///
/// - Pages 1–2 carry the «Дальше» advance CTA; page 3 swaps it for the
///   «Пополнить» deposit CTA. That label is the pager's own progress signal.
/// - Re-tapping is safe *because* the loop stops the moment the deposit CTA is
///   up: a tap that did land can never push the pager past the last page, and
///   a tap that did not land is simply repeated.
/// - The finish tap retries only while `onboarding.primaryButton` is still on
///   screen. Once the tour swaps the window root to permissions that element is
///   gone, so a landed tap is never double-fired into the next screen.
final class OnboardingFlowUITests: XCTestCase {

    /// The page-3 CTA reads «Пополнить, {amount} ₽» — match on the verb only so
    /// the assertion does not depend on the default deposit selection.
    private let depositCTAFragment = "Пополнить"

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

    func testOnboardingThroughPermissionsToMain() {
        let app = XCUIApplication()
        // `-uitour-alarmkit granted` (#626): this class is the one that walks
        // `PermissionsViewController`, so it is the one that can reach a real
        // authorization request — and a SpringBoard prompt raised here does
        // not stay here, it lands in whichever class launches next.
        app.launchArguments = ["-uitour", "onboarding", "-uitour-alarmkit", "granted"]
        app.launch()

        let primary = app.buttons["onboarding.primaryButton"]
        let done = app.buttons["permissions.doneButton"]

        // 1. Onboarding up.
        XCTAssertTrue(primary.waitForExistence(timeout: 10),
                      "Onboarding primary CTA should appear on launch")

        // 2. Advance until the deposit CTA replaces the «Дальше» advance CTA.
        // Two advances are needed; the extra attempts absorb dropped touches.
        var advanceTaps = 0
        while advanceTaps < 5, !isDepositCTA(primary) {
            primary.tap()
            advanceTaps += 1
            _ = wait(upTo: 3.5) { self.isDepositCTA(primary) }
        }
        XCTAssertTrue(isDepositCTA(primary),
                      "Onboarding should reach the deposit page after \(advanceTaps) advance taps")

        // 3. Finish onboarding — the tour swaps the window root to permissions.
        var finishTaps = 0
        while finishTaps < 3, !done.exists, primary.exists {
            primary.tap()
            finishTaps += 1
            _ = done.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(done.waitForExistence(timeout: 5),
                      "Permissions «Готово» CTA should appear after finishing onboarding")

        // 4. «Готово» → main tab bar.
        let tabBar = app.tabBars.firstMatch
        var doneTaps = 0
        while doneTaps < 3, !tabBar.exists, done.exists {
            done.tap()
            doneTaps += 1
            _ = tabBar.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5),
                      "Main tab bar should appear after completing permissions")
    }

    // MARK: - Helpers

    /// `true` once the primary CTA is the page-3 deposit variant. Reads the
    /// label only when the element exists — querying a label off a
    /// no-match element raises instead of returning empty.
    private func isDepositCTA(_ element: XCUIElement) -> Bool {
        element.exists && element.label.contains(depositCTAFragment)
    }

    /// Poll `condition` until it holds or `timeout` elapses.
    ///
    /// `waitForExistence` cannot express any of the states above: the CTA
    /// exists on every page, so what has to be observed is its label changing,
    /// not its presence. Each probe is a round trip to the app, which is the
    /// unit that gets slow on a loaded runner — hence a coarse 0.25 s interval
    /// rather than a tight spin.
    private func wait(upTo timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }
}
