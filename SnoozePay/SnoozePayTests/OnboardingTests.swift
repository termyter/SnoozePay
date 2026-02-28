import XCTest
@testable import SnoozePay

/// Unit tests for OnboardingViewController — completion flag and page count.
final class OnboardingTests: XCTestCase {

    private let completedKey = "onboarding_completed"

    override func setUp() {
        super.setUp()
        // Reset onboarding flag before each test
        UserDefaults.standard.removeObject(forKey: completedKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: completedKey)
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
}
