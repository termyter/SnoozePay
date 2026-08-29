import UIKit
import XCTest
@testable import SnoozePay

/// Tour routes for the two warning screens, plus the appearance switch (#545).
///
/// The point of these routes is that the states behind them are otherwise
/// unreachable: `simctl privacy revoke notifications` is refused by the
/// current runtime, the probe answers "available" in a simulator, and
/// `AlarmOffWarningViewController` had no entry point at all until a DEBUG
/// button appeared in the statistics screen. Two defects survived on those two
/// screens (#514, #538) for exactly that reason — nobody could look at them.
///
/// So what's pinned here is reachability, not pixels: each route mounts the
/// controller it advertises, every warning variant is selectable and carries
/// real copy, and none of the forcing leaks into a caller that wired its own
/// dependencies.
@MainActor
final class UITourWarningRoutesTests: XCTestCase {

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var repo: AlarmRepository!
    private var testCenter: NotificationCenter!
    /// Held for the test's lifetime — a released window takes its subtree
    /// (and the controllers under assertion) with it.
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        suiteName = "test.uitourRoutes.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(
            defaults: testDefaults,
            scheduler: AlarmsListViewModelTests.StubScheduler()
        )
        testCenter = NotificationCenter()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        AlarmBackendMonitor.uiTourForcedAvailability = nil
    }

    override func tearDown() {
        // A leaked override would hand the NEXT test's default-constructed
        // monitor a fixed answer — the exact cross-contamination this seam is
        // shaped to avoid.
        AlarmBackendMonitor.uiTourForcedAvailability = nil
        window = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - alarm-off-warning

    func testAlarmOffWarningRoute_mountsTheWarningScreenItself() {
        UITourLauncher.mount("alarm-off-warning", in: window)

        XCTAssertTrue(
            window.rootViewController is AlarmOffWarningViewController,
            "route must land on the warning screen, not on \(type(of: window.rootViewController))"
        )
    }

    // MARK: - alarms-nobackend

    func testAlarmsNoBackendRoute_mountsTheAlarmsTab_andForcesAWarningState() {
        UITourLauncher.mount("alarms-nobackend", in: window)

        let tabBar = window.rootViewController as? UITabBarController
        XCTAssertNotNil(tabBar, "route must mount the production tab bar")
        XCTAssertEqual(tabBar?.selectedIndex, 0, "the alarms tab is the one carrying the banner")
        let alarmsRoot = (tabBar?.selectedViewController as? UINavigationController)?
            .viewControllers.first
        XCTAssertTrue(
            alarmsRoot is AlarmsListViewController,
            "alarms tab must root on the list screen, got \(type(of: alarmsRoot))"
        )

        let forced = AlarmBackendMonitor.uiTourForcedAvailability
        XCTAssertNotNil(forced, "the route has to force a non-ringing state, else there's no banner")
        XCTAssertNotNil(
            forced.flatMap { AlarmBackendWarning(availability: $0) },
            "forced state \(String(describing: forced)) renders no banner at all"
        )
    }

    private struct Variant {
        let argument: String?
        let availability: AlarmBackendAvailability
        /// Whether this state blocks creating / enabling an alarm.
        let gates: Bool
    }

    /// Every variant reachable, and each one actually different. If two
    /// arguments collapsed onto the same state, a screenshot pass would
    /// silently cover one case twice — the failure mode this whole issue is
    /// about.
    func testEveryBackendWarningVariant_isSelectable_andCarriesRealCopy() {
        let expected: [Variant] = [
            Variant(argument: nil, availability: .unavailable, gates: true),
            Variant(argument: "unavailable", availability: .unavailable, gates: true),
            Variant(argument: "notrequested", availability: .notRequested, gates: true),
            Variant(argument: "indeterminate", availability: .indeterminate, gates: false)
        ]

        for row in expected {
            let resolved = UITourLauncher.backendAvailability(forArgument: row.argument)
            XCTAssertEqual(
                resolved, row.availability,
                "-uitour-backend-warning \(row.argument ?? "<absent>") resolved to \(resolved)"
            )

            let warning = AlarmBackendWarning(availability: resolved)
            XCTAssertNotNil(warning, "\(resolved) must produce a banner")
            XCTAssertFalse(warning?.title.isEmpty ?? true, "\(resolved) banner title is empty")
            XCTAssertFalse(warning?.message.isEmpty ?? true, "\(resolved) banner message is empty")
            XCTAssertFalse(
                warning?.actionTitle.isEmpty ?? true,
                "\(resolved) banner action title is empty"
            )
            let expectedGate: Bool? = row.gates
            XCTAssertEqual(
                warning?.gatesAlarmCreation, expectedGate,
                "\(resolved) must \(row.gates ? "" : "not ")gate alarm creation"
            )
        }

        // The three states differ in copy, which is what makes screenshotting
        // all of them worth the flag.
        let messages = Set([AlarmBackendAvailability.unavailable, .notRequested, .indeterminate]
            .compactMap { AlarmBackendWarning(availability: $0)?.message })
        XCTAssertEqual(messages.count, 3, "warning variants must not share copy")
    }

    /// End to end through the seam the screen actually reads: the list VM
    /// builds its own monitor, so the forced state has to arrive there without
    /// anyone injecting anything.
    func testForcedState_reachesTheListViewModelsOwnMonitor() {
        for availability in [AlarmBackendAvailability.unavailable, .notRequested, .indeterminate] {
            AlarmBackendMonitor.uiTourForcedAvailability = availability

            let viewModel = AlarmsListViewModel(
                alarmRepository: repo,
                notificationCenter: testCenter
            )
            viewModel.refreshBackendAvailability()

            XCTAssertEqual(viewModel.backendAvailability, availability)
            XCTAssertNotNil(viewModel.backendWarning, "\(availability) must light the banner up")
            XCTAssertFalse(viewModel.backendWarning?.message.isEmpty ?? true)
        }
    }

    // MARK: - No leak into the production path

    func testWithoutTheOverride_theRouteIsInert() {
        // Any other route must leave the monitor alone; only `alarms-nobackend`
        // is allowed to force a state.
        UITourLauncher.mount("alarms", in: window)

        XCTAssertNil(
            AlarmBackendMonitor.uiTourForcedAvailability,
            "a plain route must not force a backend state"
        )
    }

    func testAnInjectedProbe_beatsTheTourOverride() {
        AlarmBackendMonitor.uiTourForcedAvailability = .unavailable

        let probe = AlarmsListBackendGuardTests.StubProbe(result: .available)
        let monitor = AlarmBackendMonitor(probe: probe, notificationCenter: testCenter)
        monitor.refresh()

        XCTAssertEqual(
            monitor.availability, .available,
            "an explicitly wired probe must win — otherwise a stale override hijacks real callers"
        )
        XCTAssertEqual(probe.probeCount, 1, "the injected probe is the one that must be asked")
    }

    // MARK: - Appearance switch

    func testAppearanceFlag_pinsTheWindowStyle() {
        UITourLauncher.applyAppearance("light", to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)

        UITourLauncher.applyAppearance("dark", to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
    }

    /// Without the flag the window keeps whatever `SceneDelegate` applied from
    /// `preferred_theme`. The reverse — the tour quietly rewriting the stored
    /// preference — would leak a test fixture into the user's settings.
    func testWithoutTheAppearanceFlag_theWindowIsUntouched() {
        window.overrideUserInterfaceStyle = .dark

        UITourLauncher.applyAppearance(nil, to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)

        UITourLauncher.applyAppearance("sepia", to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark, "an unknown value must be a no-op")

        // And the full mount path, which reads real launch arguments (none of
        // which are present under `xcodebuild test`), leaves it alone too.
        UITourLauncher.mount("alarm-off-warning", in: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
    }

    func testTheAppearanceFlag_doesNotWriteThePersistedTheme() {
        let themeService = ThemeService(defaults: testDefaults)
        let before = themeService.current

        UITourLauncher.applyAppearance("light", to: window)

        XCTAssertEqual(
            ThemeService(defaults: testDefaults).current, before,
            "the tour must pin the window only — `preferred_theme` belongs to the user"
        )
    }
}
