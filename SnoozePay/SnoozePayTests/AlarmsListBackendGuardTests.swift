import XCTest
import UIKit
import UserNotifications
@testable import SnoozePay

/// Tests for the proactive "no backend can ring an alarm" guard (#428).
///
/// Covers the single source of truth end to end: how the two OS backends fold
/// into one `AlarmBackendAvailability`, what the alarms-list VM derives from
/// it, and the foreground re-probe that keeps the banner honest when the user
/// flips a permission in iOS Settings mid-session.
final class AlarmsListBackendGuardTests: XCTestCase {

    /// Synchronous probe stub — resolves on the calling (main) thread so the
    /// monitor applies the value without an async hop.
    final class StubProbe: AlarmBackendProbing {
        var result: AlarmBackendAvailability
        private(set) var probeCount = 0
        private(set) var authorizationRequestCount = 0
        /// Value the OS "answers" with once the prompt is dismissed.
        var resultAfterAuthorizationRequest: AlarmBackendAvailability?

        init(result: AlarmBackendAvailability) {
            self.result = result
        }

        func probe(completion: @escaping (AlarmBackendAvailability) -> Void) {
            probeCount += 1
            completion(result)
        }

        func requestAuthorization(completion: @escaping () -> Void) {
            authorizationRequestCount += 1
            if let answered = resultAfterAuthorizationRequest {
                result = answered
            }
            completion()
        }
    }

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!
    private var testCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        suiteName = "test.backendGuard.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(
            defaults: testDefaults,
            scheduler: AlarmsListViewModelTests.StubScheduler()
        )
        testCenter = NotificationCenter()
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeViewModel(
        probe: StubProbe
    ) -> (AlarmsListViewModel, AlarmBackendMonitor) {
        let monitor = AlarmBackendMonitor(probe: probe, notificationCenter: testCenter)
        let viewModel = AlarmsListViewModel(
            alarmRepository: repo,
            balanceService: .shared,
            notificationCenter: testCenter,
            backendMonitor: monitor
        )
        return (viewModel, monitor)
    }

    // MARK: - Both backends unavailable

    func testNoBackend_activatesGuard() {
        let (viewModel, _) = makeViewModel(probe: StubProbe(result: .unavailable))

        viewModel.refreshBackendAvailability()

        XCTAssertEqual(viewModel.backendAvailability, .unavailable)
        XCTAssertFalse(viewModel.canCreateAlarms, "create/enable CTAs must be gated with no backend")
        let warning = viewModel.backendWarning
        XCTAssertNotNil(warning, "no-backend state must surface a banner")
        XCTAssertEqual(warning?.title, "Будильники не зазвонят")
        XCTAssertTrue(warning?.gatesAlarmCreation == true)
        // The copy has to lead somewhere, not just state the problem.
        XCTAssertTrue(warning?.message.contains("Настройках") == true)
        XCTAssertEqual(warning?.actionTitle, "Открыть Настройки")
    }

    // MARK: - At least one backend available

    func testBackendAvailable_noGuard() {
        let (viewModel, _) = makeViewModel(probe: StubProbe(result: .available))

        viewModel.refreshBackendAvailability()

        XCTAssertEqual(viewModel.backendAvailability, .available)
        XCTAssertNil(viewModel.backendWarning, "a working backend must not show a banner")
        XCTAssertTrue(viewModel.canCreateAlarms)
    }

    func testAlarmKitAuthorized_isEnoughEvenWithNotificationsDenied() {
        let probe = SystemAlarmBackendProbe(
            alarmKitAuthorized: { true },
            notificationStatus: { completion in completion(.denied) }
        )
        var resolved: AlarmBackendAvailability?
        probe.probe { resolved = $0 }

        XCTAssertEqual(resolved, .available)
    }

    func testNotificationsAuthorized_isEnoughWithoutAlarmKit() {
        let probe = SystemAlarmBackendProbe(
            alarmKitAuthorized: { false },
            notificationStatus: { completion in completion(.authorized) }
        )
        var resolved: AlarmBackendAvailability?
        probe.probe { resolved = $0 }

        XCTAssertEqual(resolved, .available)
    }

    func testBothBackendsDenied_resolvesUnavailable() {
        let probe = SystemAlarmBackendProbe(
            alarmKitAuthorized: { false },
            notificationStatus: { completion in completion(.denied) }
        )
        var resolved: AlarmBackendAvailability?
        probe.probe { resolved = $0 }

        XCTAssertEqual(resolved, .unavailable)
    }

    /// Undecided notifications are their OWN state: still no alarm, but the
    /// remedy is the in-app prompt, not a trip to Settings.
    func testNotDetermined_resolvesNotRequested() {
        XCTAssertEqual(
            SystemAlarmBackendProbe.availability(forNotificationStatus: .notDetermined),
            .notRequested
        )
    }

    func testNotRequested_asksInAppInsteadOfSendingToSettings() {
        let (viewModel, _) = makeViewModel(probe: StubProbe(result: .notRequested))

        viewModel.refreshBackendAvailability()

        XCTAssertEqual(viewModel.backendAvailability, .notRequested)
        let warning = viewModel.backendWarning
        XCTAssertNotNil(warning, "an unasked permission still means alarms won't ring")
        XCTAssertTrue(warning?.gatesAlarmCreation == true, "gate stays on — the alarm would not ring")
        XCTAssertTrue(warning?.canRequestInApp == true, "the OS prompt is still available in this state")
        XCTAssertEqual(warning?.actionTitle, "Разрешить")
        XCTAssertFalse(
            warning?.message.contains("выключено") == true,
            "copy must not claim a permission was switched off when it was never requested"
        )
    }

    func testDeniedState_routesToSettingsNotAnInAppPrompt() {
        let (viewModel, _) = makeViewModel(probe: StubProbe(result: .unavailable))

        viewModel.refreshBackendAvailability()

        XCTAssertFalse(
            viewModel.backendWarning?.canRequestInApp == true,
            "a decided grant can only be changed in Settings — an in-app prompt would no-op"
        )
        XCTAssertEqual(viewModel.backendWarning?.actionTitle, "Открыть Настройки")
    }

    func testRequestAlarmPermissions_promptsThenRefreshes() {
        let probe = StubProbe(result: .notRequested)
        probe.resultAfterAuthorizationRequest = .available
        let (viewModel, _) = makeViewModel(probe: probe)
        viewModel.refreshBackendAvailability()
        XCTAssertFalse(viewModel.canCreateAlarms)

        viewModel.requestAlarmPermissions()

        XCTAssertEqual(probe.authorizationRequestCount, 1)
        XCTAssertEqual(viewModel.backendAvailability, .available, "the grant must be re-probed, not assumed")
        XCTAssertNil(viewModel.backendWarning)
        XCTAssertTrue(viewModel.canCreateAlarms)
    }

    func testRequestAlarmPermissions_isNoOpOnceTheGrantIsDecided() {
        let probe = StubProbe(result: .unavailable)
        let (viewModel, _) = makeViewModel(probe: probe)
        viewModel.refreshBackendAvailability()

        viewModel.requestAlarmPermissions()

        XCTAssertEqual(
            probe.authorizationRequestCount, 0,
            "requesting a decided grant silently does nothing — callers must route to Settings"
        )
    }

    /// Provisional notifications are delivered quietly — they cannot wake a
    /// sleeping user, so they must not count as an alarm backend.
    func testProvisional_resolvesUnavailable() {
        XCTAssertEqual(
            SystemAlarmBackendProbe.availability(forNotificationStatus: .provisional),
            .unavailable
        )
    }

    func testAuthorized_resolvesAvailable() {
        XCTAssertEqual(
            SystemAlarmBackendProbe.availability(forNotificationStatus: .authorized),
            .available
        )
    }

    // MARK: - Unresolved / indeterminate must not read as "all fine"

    func testBeforeFirstProbe_stateIsUnresolvedAndSilent() {
        let (viewModel, _) = makeViewModel(probe: StubProbe(result: .unavailable))

        // No probe has answered yet: claim nothing, show nothing, gate nothing.
        XCTAssertEqual(viewModel.backendAvailability, .unresolved)
        XCTAssertNil(viewModel.backendWarning)
        XCTAssertTrue(viewModel.canCreateAlarms)
    }

    func testIndeterminate_warnsButDoesNotGate() {
        let (viewModel, _) = makeViewModel(probe: StubProbe(result: .indeterminate))

        viewModel.refreshBackendAvailability()

        XCTAssertEqual(viewModel.backendAvailability, .indeterminate)
        let warning = viewModel.backendWarning
        XCTAssertNotNil(warning, "an unreadable status must never pass for 'everything is fine'")
        XCTAssertEqual(warning?.title, "Не удалось проверить разрешения")
        XCTAssertFalse(warning?.gatesAlarmCreation == true, "our failure must not block the user")
        XCTAssertTrue(viewModel.canCreateAlarms)
    }

    // MARK: - Foreground transition (return from iOS Settings)

    /// The foreground tests below post `foregroundNotificationName` — the same
    /// constant the monitor subscribes to — so they would stay green if that
    /// constant were changed to a name UIKit never posts. This pins it to the
    /// real system notification, which is what actually makes the banner
    /// refresh on the way back from Settings (#428).
    func testForegroundNotificationName_isTheRealSystemActivation() {
        XCTAssertEqual(
            AlarmBackendMonitor.foregroundNotificationName,
            UIApplication.didBecomeActiveNotification
        )
    }

    func testForegroundActivation_reprobesAndPublishesTransition() {
        let probe = StubProbe(result: .available)
        let (viewModel, _) = makeViewModel(probe: probe)
        viewModel.refreshBackendAvailability()
        XCTAssertNil(viewModel.backendWarning)

        // User walks into iOS Settings and revokes the grant.
        probe.result = .unavailable

        let published = expectation(description: "availability transition published")
        var reported: AlarmBackendAvailability?
        viewModel.onBackendAvailabilityChanged = { availability in
            reported = availability
            published.fulfill()
        }
        testCenter.post(name: AlarmBackendMonitor.foregroundNotificationName, object: nil)
        wait(for: [published], timeout: 2)

        XCTAssertEqual(reported, .unavailable)
        XCTAssertEqual(viewModel.backendAvailability, .unavailable)
        XCTAssertFalse(viewModel.canCreateAlarms)
        XCTAssertNotNil(viewModel.backendWarning)
        XCTAssertGreaterThanOrEqual(probe.probeCount, 2, "foreground must re-query, not reuse cold-launch state")
    }

    func testForegroundActivation_clearsGuardOnceGranted() {
        let probe = StubProbe(result: .unavailable)
        let (viewModel, _) = makeViewModel(probe: probe)
        viewModel.refreshBackendAvailability()
        XCTAssertFalse(viewModel.canCreateAlarms)

        // User grants the permission and comes back.
        probe.result = .available

        let published = expectation(description: "availability transition published")
        viewModel.onBackendAvailabilityChanged = { _ in published.fulfill() }
        testCenter.post(name: AlarmBackendMonitor.foregroundNotificationName, object: nil)
        wait(for: [published], timeout: 2)

        XCTAssertEqual(viewModel.backendAvailability, .available)
        XCTAssertNil(viewModel.backendWarning, "banner must dismount once a backend is authorized")
        XCTAssertTrue(viewModel.canCreateAlarms)
    }

    func testRepeatedProbeWithSameResult_doesNotRepublish() {
        let probe = StubProbe(result: .unavailable)
        let (viewModel, _) = makeViewModel(probe: probe)
        var publishCount = 0
        viewModel.onBackendAvailabilityChanged = { _ in publishCount += 1 }

        viewModel.refreshBackendAvailability()
        viewModel.refreshBackendAvailability()
        viewModel.refreshBackendAvailability()

        XCTAssertEqual(publishCount, 1, "only real transitions should re-render the banner")
    }

    // MARK: - CTA gating decisions

    func testShouldInterceptToggle_coversAllFourCombinations() {
        let gated = makeViewModel(probe: StubProbe(result: .unavailable)).0
        gated.refreshBackendAvailability()
        let open = makeViewModel(probe: StubProbe(result: .available)).0
        open.refreshBackendAvailability()

        // Switching ON with no backend is the only case worth interrupting.
        XCTAssertTrue(gated.shouldInterceptToggle(isOn: true))
        // Switching OFF always works — an alert here would fire on every
        // disable, which is worse than the bug being guarded against.
        XCTAssertFalse(gated.shouldInterceptToggle(isOn: false))
        XCTAssertFalse(open.shouldInterceptToggle(isOn: true))
        XCTAssertFalse(open.shouldInterceptToggle(isOn: false))
    }

    func testShouldInterceptCreate_followsTheGate() {
        let gated = makeViewModel(probe: StubProbe(result: .unavailable)).0
        gated.refreshBackendAvailability()
        let open = makeViewModel(probe: StubProbe(result: .available)).0
        open.refreshBackendAvailability()
        let unprobed = makeViewModel(probe: StubProbe(result: .unavailable)).0

        XCTAssertTrue(gated.shouldInterceptCreate)
        XCTAssertFalse(open.shouldInterceptCreate)
        XCTAssertFalse(unprobed.shouldInterceptCreate, "an un-probed app must not block the CTA")
    }

    // MARK: - Observation seam

    /// A VM handed an isolated `NotificationCenter` must not quietly build its
    /// monitor on the process-global one: a test-host activation would then
    /// drive `AlarmScheduler.shared` / `UNUserNotificationCenter` from inside
    /// unit tests.
    func testDefaultMonitor_observesTheInjectedNotificationCenter() {
        let viewModel = AlarmsListViewModel(
            alarmRepository: repo,
            balanceService: .shared,
            notificationCenter: testCenter
        )

        XCTAssertTrue(viewModel.backendMonitor.notificationCenter === testCenter)
    }
}
