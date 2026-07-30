import XCTest
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

        init(result: AlarmBackendAvailability) {
            self.result = result
        }

        func probe(completion: @escaping (AlarmBackendAvailability) -> Void) {
            probeCount += 1
            completion(result)
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

    /// Undecided notifications are not a backend *yet* — the guard is exactly
    /// the nudge that gets them decided.
    func testNotDetermined_resolvesUnavailable() {
        XCTAssertEqual(
            SystemAlarmBackendProbe.availability(forNotificationStatus: .notDetermined),
            .unavailable
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
}
