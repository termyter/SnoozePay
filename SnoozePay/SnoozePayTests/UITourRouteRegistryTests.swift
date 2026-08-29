#if DEBUG
import UIKit
import XCTest
@testable import SnoozePay

/// Pins the `-uitour <screen>` route names (#564).
///
/// Route names are an external contract: `/audit`, `audit-design`,
/// `ui-explorer`, `qa-tester` and the `SnoozePayUITests` suite pass them as
/// launch arguments, and none of that is type-checked. Renaming or dropping a
/// route therefore breaks nothing loudly — the launcher falls back to the
/// alarms tab, the harness screenshots a plausible screen, and the audit
/// silently reports on the wrong thing.
///
/// So this test is deliberately a hardcoded list rather than a derived one:
/// its whole value is that it fails when the registry changes, forcing whoever
/// changed it to also update the skills and UI tests that name these screens.
/// Adding a route is a one-line edit here; renaming one is a prompt to grep.
@MainActor
final class UITourRouteRegistryTests: XCTestCase {

    /// Every screen id the tour is expected to answer to. Keep in sync with the
    /// "Supported screens" list in `UITourRoutes`' doc comment.
    private let expectedRoutes: Set<String> = [
        "onboarding",
        "permissions",
        "alarms",
        "alarms-nobackend",
        "alarm-off-warning",
        "wallet",
        "stats",
        "settings",
        "create",
        "edit",
        "theme-picker",
        "sound-picker",
        "volume-picker",
        "confirm-delete",
        "firing",
        "firing-snoozed",
        "firing-progressive",
        "firing-nobalance",
        "firing-topup",
        "txhistory",
        "periodpicker",
        "deposit",
        "streak"
    ]

    func testRouteRegistry_matchesThePublishedScreenList() {
        let actual = Set(UITourRoutes.mounters.keys)

        let removed = expectedRoutes.subtracting(actual).sorted()
        let added = actual.subtracting(expectedRoutes).sorted()

        XCTAssertTrue(
            removed.isEmpty,
            """
            Route(s) \(removed) disappeared from UITourRoutes. Anything passing \
            `-uitour <name>` now lands on the alarms tab instead: grep the name \
            in SnoozePayUITests/ and .claude/{skills,agents}/ before changing it.
            """
        )
        XCTAssertTrue(
            added.isEmpty,
            """
            New route(s) \(added). Add them to this list and to the \
            "Supported screens" doc comment in UITourRoutes, so the audit \
            harness can discover them.
            """
        )
    }

    /// The names travel through `app.launchArguments` and shell-quoted skill
    /// invocations, so a route id with a space or a capital in it would be
    /// unusable long before anyone noticed the screen was missing.
    func testRouteNames_areLaunchArgumentSafe() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz-")
        for name in UITourRoutes.mounters.keys {
            XCTAssertFalse(name.isEmpty, "an empty route id can never be selected")
            XCTAssertTrue(
                name.unicodeScalars.allSatisfy { allowed.contains($0) },
                "route id '\(name)' must be lowercase-and-hyphens to survive a launch argument"
            )
        }
    }

    /// The routes with a test or skill hardcoding them are called out
    /// separately: for these, the generic list above is not the only reader,
    /// and the failure message should say who breaks.
    func testRoutesUsedByTheEndToEndSuite_areStillRegistered() {
        let e2eRoutes = [
            "onboarding": "OnboardingFlowUITests",
            "create": "CreateAlarmUITests",
            "confirm-delete": "ConfirmDeleteRouteUITests",
            "firing": "FiringFlowUITests",
            "firing-progressive": "ProgressiveSnoozeUITests",
            "firing-nobalance": "NoBalanceTopUpUITests"
        ]

        for (route, suite) in e2eRoutes {
            XCTAssertNotNil(
                UITourRoutes.mounters[route],
                "`-uitour \(route)` is launched by \(suite) — dropping it makes that test screenshot the wrong screen"
            )
        }
    }

    /// An unknown id must land somewhere obvious rather than hang, so a typo in
    /// an audit script shows up as "wrong screen" instead of "black window".
    func testUnknownRoute_fallsBackToTheAlarmsTab() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        UITourRoutes.mounter(for: "no-such-screen")(window)

        let tabBar = window.rootViewController as? UITabBarController
        XCTAssertNotNil(tabBar, "unknown route must still mount the production tab bar")
        XCTAssertEqual(tabBar?.selectedIndex, 0, "the fallback is the alarms tab")

        window.isHidden = true
        window.rootViewController = nil
    }
}
#endif
