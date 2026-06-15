import XCTest

/// End-to-end walk through the first-launch journey.
///
/// Mounts the REAL `OnboardingViewController` via `-uitour onboarding`, which
/// (in tour mode) wires the production `onFinished` chain onboarding →
/// `PermissionsViewController` → main tab bar — the same order SceneDelegate
/// drives on a real first launch. The path exercised:
///
///   1. Onboarding up — the primary «Дальше» CTA present.
///   2. Tap it across the 3 pages; on the last page it becomes «Пополнить» and
///      tapping it finishes onboarding.
///   3. The permissions screen appears with its «Готово» CTA.
///   4. Tapping «Готово» lands on the main tab bar.
///
/// The primary CTA instance is swapped per page, so the test re-queries the
/// stable `onboarding.primaryButton` id each tap rather than holding a handle.
final class OnboardingFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOnboardingThroughPermissionsToMain() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "onboarding"]
        app.launch()

        // 1. Onboarding up.
        XCTAssertTrue(app.buttons["onboarding.primaryButton"].waitForExistence(timeout: 10),
                      "Onboarding primary CTA should appear on launch")

        // 2. Advance through all 3 pages (page 1→2, 2→3, then finish on page 3).
        // The button instance is replaced on each page change, so re-resolve the
        // id every tap.
        for step in 1...3 {
            let primary = app.buttons["onboarding.primaryButton"]
            XCTAssertTrue(primary.waitForExistence(timeout: 5),
                          "Primary CTA should be present before onboarding step \(step)")
            primary.tap()
        }

        // 3. Permissions screen reached via the onFinished chain.
        let done = app.buttons["permissions.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5),
                      "Permissions «Готово» CTA should appear after finishing onboarding")

        // 4. «Готово» → main tab bar.
        done.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5),
                      "Main tab bar should appear after completing permissions")
    }
}
