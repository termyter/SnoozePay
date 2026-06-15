import XCTest

/// E2e for the onboarding walk-through (concept → mechanics → deposit → main).
///
/// SKIPPED for now. The `-uitour onboarding` mount builds
/// `OnboardingViewController()` without wiring its `onFinished` callback, so
/// finishing the flow (Пропустить / Позже / Пополнить) does not navigate
/// anywhere — there is no observable "reached the main screen" end state to
/// assert. Driving the horizontal pager (the «Дальше» CTA swaps its own
/// instance on the deposit page) is also animation-timing sensitive.
///
/// To enable: have `UITourLauncher` wire `onboarding`'s `onFinished` to mount
/// the main tab bar (e.g. a `-uitour-onboarding-finishes-to-main` flag), and
/// add stable ids to the primary CTA and a page-3 marker. Then assert tapping
/// «Дальше» twice reaches the deposit page and finishing lands on the tab bar.
final class OnboardingUITests: XCTestCase {

    func testOnboardingReachesMain() throws {
        throw XCTSkip("""
            Needs harness support: the -uitour onboarding mount does not wire \
            onFinished, so the flow has no observable terminal state. See the \
            file header for the enablement steps (#340).
            """)
    }
}
