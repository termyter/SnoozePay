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
/// So what's pinned here is reachability, not pixels: each route opens the
/// controller it advertises the way the app opens it, every warning variant is
/// selectable and carries real copy, and none of the forcing leaks into a
/// caller that wired its own dependencies.
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
        // #693, same class of failure as #618. This is one of the few suites
        // that spins the main run loop, so without a drain it inherits the
        // deferred UIKit work the ~1000 preceding synchronous tests left
        // queued, and spends it inside the wait below. The clean build of
        // 2026-09-01 shows exactly that: 45 s of wall clock burned on a 5 s
        // timeout, i.e. the main queue never yielded once — not even to the
        // poll's own unconditional deadline block, which is what should have
        // turned "not presented" into a readable assertion failure.
        //
        // The drain takes that backlog out of what the wait measures, so the
        // 5 s window keeps meaning "this route is broken" instead of "this
        // runner was busy". Widening it would have to cover the whole backlog,
        // and a window that wide stops noticing the regression the wait is for.
        drainMainQueue()
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
        // Dismiss and unroot before hiding: a window released while it still
        // owns a presentation hands UIKit a dismissal to run *later*, and
        // "later" is the next suite's first wait — this class contributing to
        // the very backlog it drains for in `setUp` (#693).
        window?.rootViewController?.dismiss(animated: false)
        window?.rootViewController = nil
        // Hide before releasing: a visible window holding a presented sheet
        // outlives the test case otherwise.
        window?.isHidden = true
        window = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - alarm-off-warning

    /// The route has to OPEN the screen the way the app does — as a pageSheet
    /// over the statistics tab. #514 was a crash on opening, so a route that
    /// merely built and laid out the controller would walk around the exact
    /// path it exists to exercise.
    func testAlarmOffWarningRoute_presentsTheSheetOverStatistics() {
        // A local binding, not the property: the poll below runs inside an
        // escaping closure, and capturing the test case there is what makes
        // Swift ask for an explicit `self`.
        let host: UIWindow = window
        host.isHidden = false
        UITourLauncher.mount("alarm-off-warning", in: host)

        let tabBar = host.rootViewController as? UITabBarController
        XCTAssertEqual(tabBar?.selectedIndex, 2, "the sheet's production presenter is the stats tab")

        // `presentLater` waits a beat for the root to lay out, so poll instead
        // of hard-coding that delay — same shape as `AlarmSchedulerTests`. The
        // deadline fulfils unconditionally so a route that never presents ends
        // the test at the assertion below, which can name what IS on screen,
        // rather than at a bare "Asynchronous wait failed".
        let presented = expectation(description: "warning sheet presented")
        let deadline = Date().addingTimeInterval(4)
        func poll() {
            if host.rootViewController?.presentedViewController != nil || Date() >= deadline {
                presented.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        poll()
        wait(for: [presented], timeout: 5)

        let sheet = host.rootViewController?.presentedViewController
        let diagnostics = presentationDiagnostics(rootedAt: host.rootViewController)
        // Naming the class through the optional, not `type(of: sheet)`: that
        // reports `Optional<UIViewController>` for every outcome, which tells
        // the next reader nothing about what actually came up.
        let sheetName = sheet.map { String(describing: type(of: $0)) } ?? "nothing"
        XCTAssertTrue(
            sheet is AlarmOffWarningViewController,
            """
            route presented \(sheetName) over the stats tab, expected the warning sheet. \
            \(diagnostics)
            """
        )
    }

    /// The presentation shape itself, asserted without waiting: a `.large`
    /// pageSheet, same as `StatisticsViewController` builds.
    func testAlarmOffWarningSheet_matchesTheProductionPresentation() {
        let sheet = UITourRoutes.makeAlarmOffWarningSheet()

        XCTAssertEqual(sheet.modalPresentationStyle, .pageSheet)
        // `Detent` instances compare by identity, so match on the identifier.
        let detents = sheet.sheetPresentationController?.detents ?? []
        XCTAssertEqual(detents.count, 1)
        let expectedIdentifier: UISheetPresentationController.Detent.Identifier? = .large
        XCTAssertEqual(
            detents.first?.identifier, expectedIdentifier,
            "the warning fills the sheet, it isn't a peek"
        )
        let expectedRadius: CGFloat? = AppRadius.xl
        XCTAssertEqual(sheet.sheetPresentationController?.preferredCornerRadius, expectedRadius)
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
        UITourLauncher.mount("alarms", in: window)
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
