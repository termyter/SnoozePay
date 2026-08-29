import UIKit
import XCTest
@testable import SnoozePay

/// Hide/restore symmetry for the three bar-less tabs (#517).
///
/// Three tab roots draw their own in-screen header and therefore hide the
/// system nav bar in `viewWillAppear` (`AlarmsList` and `Wallet` #280,
/// `Statistics` #319). Every one of them also pushes a child screen that needs
/// the bar back — for the back arrow, for the title, and (since #508) for the
/// canon `bg0` chrome, which a hidden bar renders none of.
///
/// Two of the three restored it. `Statistics` did not, so the referral screen
/// opened with no bar, no back button and content under the status bar. The
/// fix is one line; this file is the part that matters, because it asserts the
/// **symmetry** rather than the one screen: the table below is driven, so the
/// next tab to grow a push cannot repeat #517 unnoticed.
///
/// Subjects are hosted in a real (deliberately **not** visible) `UIWindow` —
/// `WalletLightThemeTests` documents why: making the window visible runs the
/// appearance cycle, and `viewWillAppear` can present an alert. Lifecycle is
/// driven by hand instead.
@MainActor
final class NavigationBarSymmetryTests: XCTestCase {

    /// One row per tab root that hides the system bar. Adding a fourth
    /// bar-less tab means adding a row here.
    private struct BarlessRoot {
        let name: String
        let make: () -> UIViewController
        /// The `@objc` action that pushes this tab's child screen. Reached via
        /// `perform` because the actions are `private` to their controllers —
        /// the ObjC runtime does not care, and a rename fails the
        /// `responds(to:)` guard below with a readable message.
        let pushAction: Selector
        /// What the push is expected to land on.
        let child: AnyClass
    }

    /// `debugReferralTapped` is `#if DEBUG`, which is the configuration the
    /// test target builds against; the referral entry point is debug-only too.
    private var barlessRoots: [BarlessRoot] {
        [
            BarlessRoot(
                name: "Будильники",
                make: { AlarmsListViewController() },
                pushAction: Selector(("openSettings")),
                child: SettingsViewController.self
            ),
            BarlessRoot(
                name: "Кошелёк",
                make: { WalletViewController() },
                pushAction: Selector(("openHistory")),
                child: WalletTransactionHistoryViewController.self
            ),
            BarlessRoot(
                name: "Статистика",
                make: { StatisticsViewController() },
                pushAction: Selector(("debugReferralTapped")),
                child: ReferralViewController.self
            )
        ]
    }

    /// Windows hosting the subjects. Held for the lifetime of the test case:
    /// a released window takes its subtree with it.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - The pair

    /// Direction one: these tabs are deliberately bar-less.
    func testEveryBarlessTab_hidesTheBarOnAppear() {
        for root in barlessRoots {
            let (controller, stack) = host(root)
            controller.viewWillAppear(false)
            XCTAssertTrue(
                stack.isNavigationBarHidden,
                "\(root.name) stopped hiding the bar — its in-screen header now double-titles the screen"
            )
        }
    }

    /// Direction two, and the actual #517 regression: a root that hides the
    /// bar must put it back before pushing, or the child ships with no back
    /// button and its content runs under the status bar.
    func testEveryBarlessTab_restoresTheBarBeforePushingItsChild() {
        for root in barlessRoots {
            let (controller, stack) = host(root)
            controller.viewWillAppear(false)
            XCTAssertTrue(stack.isNavigationBarHidden, "\(root.name) did not start bar-less")

            guard controller.responds(to: root.pushAction) else {
                XCTFail("\(root.name) no longer answers \(root.pushAction) — update the table")
                continue
            }
            _ = controller.perform(root.pushAction)

            XCTAssertEqual(
                stack.viewControllers.count, 2,
                "\(root.name) did not push a child at all"
            )
            XCTAssertTrue(
                stack.topViewController?.isKind(of: root.child) ?? false,
                "\(root.name) pushed \(String(describing: stack.topViewController)), expected \(root.child)"
            )
            XCTAssertFalse(
                stack.isNavigationBarHidden,
                """
                \(root.name) pushed a child onto a hidden bar — that is #517: \
                no back button, no title, content under the status bar
                """
            )
        }
    }

    /// Coming back re-hides it: the tab is bar-less by design, so the restore
    /// must not leak past the child.
    func testPoppingBackToABarlessTab_hidesTheBarAgain() {
        for root in barlessRoots {
            let (controller, stack) = host(root)
            controller.viewWillAppear(false)
            guard controller.responds(to: root.pushAction) else {
                XCTFail("\(root.name) no longer answers \(root.pushAction) — update the table")
                continue
            }
            _ = controller.perform(root.pushAction)
            XCTAssertFalse(stack.isNavigationBarHidden, "\(root.name) did not restore before the push")

            // What UIKit runs when the child is popped.
            controller.viewWillAppear(true)
            XCTAssertTrue(
                stack.isNavigationBarHidden,
                "\(root.name) kept the bar after the child was popped"
            )
        }
    }

    // MARK: - Interrupted transition

    /// A swipe-back the user **cancels** halfway has already run the root's
    /// `viewWillAppear`, so the bar is hidden — while the child is still the
    /// screen on display. Left alone that is the reported state, reached
    /// without any push being involved.
    ///
    /// The branch is exercised through the lifted-out helper: a real
    /// `transitionCoordinator` exists only during a live transition and cannot
    /// be injected into a `UIViewController`.
    func testCancelledSwipeBack_givesTheBarBackToTheChild() {
        let stack = AppNavigationBarStyle.makeNavigationController(rootViewController: UIViewController())
        stack.setNavigationBarHidden(true, animated: false)

        AppNavigationBarStyle.restoreBarIfInteractionCancelled(on: stack, cancelled: true)
        XCTAssertFalse(
            stack.isNavigationBarHidden,
            "a cancelled swipe-back left the child bar-less"
        )
    }

    /// The other half: a transition that completes must leave the root's own
    /// hide standing, or the bar-less tabs grow a bar on every pop.
    func testCompletedSwipeBack_keepsTheBarHidden() {
        let stack = AppNavigationBarStyle.makeNavigationController(rootViewController: UIViewController())
        stack.setNavigationBarHidden(true, animated: false)

        AppNavigationBarStyle.restoreBarIfInteractionCancelled(on: stack, cancelled: false)
        XCTAssertTrue(
            stack.isNavigationBarHidden,
            "a completed pop un-hid the bar on a deliberately bar-less tab"
        )
    }

    // MARK: - The reported screen, through the real wiring

    /// End-to-end on the app's own tab bar rather than a hand-built stack, and
    /// the join with #508: the bar the referral screen gets back is the shared
    /// `bg0` chrome, not system default. A screen whose bar stays hidden never
    /// receives that styling at all, which is why the two issues are the same
    /// fix from the user's side.
    func testStatisticsTab_opensReferralWithTheCanonBar() throws {
        let tabBarController = try XCTUnwrap(SceneDelegate.makeMainTabBar() as? UITabBarController)
        let stack = try XCTUnwrap(
            tabBarController.viewControllers?
                .compactMap { $0 as? UINavigationController }
                .first { $0.viewControllers.first is StatisticsViewController },
            "no tab is rooted at StatisticsViewController any more"
        )
        let statistics = try XCTUnwrap(stack.viewControllers.first as? StatisticsViewController)
        let window = makeHostWindow()
        window.rootViewController = tabBarController
        statistics.loadViewIfNeeded()

        statistics.viewWillAppear(false)
        _ = statistics.perform(Selector(("debugReferralTapped")))

        let referral = try XCTUnwrap(
            stack.topViewController as? ReferralViewController,
            "the referral screen is not what the statistics tab pushes"
        )
        // The window is not visible, so nothing else drives the child's
        // `viewDidLoad` — and the title is set there.
        referral.loadViewIfNeeded()
        XCTAssertFalse(stack.isNavigationBarHidden, "the referral screen still opens without a nav bar")
        XCTAssertFalse(
            referral.title?.isEmpty ?? true,
            "a visible bar with no title reads as an empty strip"
        )
        XCTAssertEqual(
            channels(stack.navigationBar.standardAppearance.backgroundColor?.resolved(.light)),
            channels(AppColors.bg0.resolved(.light)),
            "the restored bar is not on the shared #508 chrome"
        )
    }

    // MARK: - Helpers

    private func host(_ root: BarlessRoot) -> (UIViewController, UINavigationController) {
        let controller = root.make()
        let stack = AppNavigationBarStyle.makeNavigationController(rootViewController: controller)
        let window = makeHostWindow()
        window.rootViewController = stack
        controller.loadViewIfNeeded()
        return (controller, stack)
    }

    private func makeHostWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        hostWindows.append(window)
        return window
    }

    /// RGBA as a comparable array — tuples aren't `Equatable`, and rounding
    /// keeps float noise out of the comparison.
    private func channels(_ color: UIColor?) -> [CGFloat]? {
        guard let color = color else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return [red, green, blue, alpha].map { ($0 * 10_000).rounded() / 10_000 }
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}
