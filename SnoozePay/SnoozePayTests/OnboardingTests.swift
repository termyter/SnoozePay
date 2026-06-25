import XCTest
@testable import SnoozePay

/// Unit tests for OnboardingViewController — completion flag and page count.
final class OnboardingTests: XCTestCase {

    private let completedKey = "onboarding_completed"
    private let firstTopUpDoneKey = "first_top_up_done"

    override func setUp() {
        super.setUp()
        // Reset onboarding flags before each test
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: firstTopUpDoneKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: firstTopUpDoneKey)
        super.tearDown()
    }

    // MARK: - Completion flag

    func testIsCompleted_defaultFalse() {
        // Fresh state: onboarding should not be marked as completed
        XCTAssertFalse(OnboardingViewController.isCompleted)
    }

    func testIsCompleted_trueAfterSet() {
        UserDefaults.standard.set(true, forKey: completedKey)

        XCTAssertTrue(OnboardingViewController.isCompleted)
    }

    // MARK: - Page count

    func testOnboardingPages_count() {
        let vc = OnboardingViewController()
        vc.loadViewIfNeeded()

        // The page control should reflect 3 onboarding pages
        let pageControl = vc.view.subviews.compactMap { $0 as? UIPageControl }.first
        XCTAssertNotNil(pageControl, "OnboardingViewController should contain a UIPageControl")
        XCTAssertEqual(pageControl?.numberOfPages, 3, "Onboarding should have exactly 3 pages")
    }

    // MARK: - Deposit presets (V3, #238)

    func testDepositOptions_firstPresetIs250() {
        let vc = OnboardingViewController()

        let first = vc.depositOptions[0]
        XCTAssertEqual(first.amount, 250, "V3 entry preset is 250 ₽ (was 200 ₽)")
        XCTAssertTrue(
            first.description.contains("5 откладываний"),
            "250 ₽ preset describes ≈ 5 snoozes at 50 ₽"
        )
        XCTAssertTrue(
            first.description.contains("50\(MoneyFormatter.narrowSpace)₽"),
            "Preset copy renders money via MoneyFormatter (narrow space before ₽)"
        )
    }

    func testDepositOptions_amounts() {
        let vc = OnboardingViewController()

        XCTAssertEqual(vc.depositOptions.map(\.amount), [250, 500, 1000])
        XCTAssertEqual(vc.defaultDepositIndex, 1, "500 ₽ stays the default selection")
    }

    // MARK: - Skip pill (V3, #238)

    func testSkip_marksOnboardingCompleted_andNotifies() {
        let vc = OnboardingViewController()
        vc.loadViewIfNeeded()
        var finished = false
        vc.onFinished = { finished = true }

        vc.skipTapped()

        XCTAssertTrue(OnboardingViewController.isCompleted, "Skip completes onboarding")
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: firstTopUpDoneKey),
            "Skip records that the first top-up did not happen"
        )
        XCTAssertTrue(finished, "Skip invokes onFinished so SceneDelegate can swap the root")
    }

    func testSkipButton_isInstalled() {
        let vc = OnboardingViewController()
        vc.loadViewIfNeeded()

        XCTAssertNotNil(vc.skipButton.superview, "Skip pill is mounted on the onboarding canvas")
        let title = vc.skipButton.configuration?.attributedTitle.map { String($0.characters) }
        XCTAssertEqual(title, "Пропустить")
    }

    // MARK: - Pager page resolution (#408)

    func testResolvePage_settlesToNearestPage() {
        let width: CGFloat = 390

        XCTAssertEqual(OnboardingViewController.resolvePage(offsetX: 0, width: width), 0)
        // Slow drag releasing just past the midpoint of page 3 rounds to page 2,
        // the case scrollViewDidEndDragging(decelerate: false) must now cover.
        XCTAssertEqual(OnboardingViewController.resolvePage(offsetX: width * 2 - 10, width: width), 2)
        XCTAssertEqual(OnboardingViewController.resolvePage(offsetX: width * 2, width: width), 2)
    }

    func testResolvePage_zeroWidthIsSafe() {
        // Before layout the scroll view has zero width — must not divide by zero.
        XCTAssertEqual(OnboardingViewController.resolvePage(offsetX: 100, width: 0), 0)
    }
}
