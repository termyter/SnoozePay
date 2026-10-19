import XCTest
@testable import SnoozePay

/// Permission changes and asynchronous scheduling failures must never leave an
/// apparently armed alarm, discard existing user data or duplicate a retry.
final class CreateAlarmPermissionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var scheduler: AlarmsListViewModelTests.StubScheduler!
    private var repository: AlarmRepository!

    override func setUp() {
        super.setUp()
        suite = "test.createPermission.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        scheduler = AlarmsListViewModelTests.StubScheduler()
        repository = AlarmRepository(defaults: defaults, scheduler: scheduler)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeViewModel(
        probe: AlarmsListBackendGuardTests.StubProbe,
        alarm: Alarm? = nil
    ) -> CreateAlarmViewModel {
        CreateAlarmViewModel(
            alarm: alarm, repository: repository,
            backendMonitor: AlarmBackendMonitor(probe: probe, notificationCenter: NotificationCenter())
        )
    }

    func testEveryUnconfirmedGrantRefusesBothSaveEntryPointsWithoutPersisting() {
        for state in [AlarmBackendAvailability.notRequested, .unavailable, .indeterminate, .unresolved] {
            let model = makeViewModel(probe: AlarmsListBackendGuardTests.StubProbe(result: state))
            var outcome: CreateAlarmViewModel.SaveOutcome?
            model.save { outcome = $0 }
            XCTAssertEqual(outcome, .permissionRequired(state))
            XCTAssertFalse(model.save())
            XCTAssertTrue(repository.fetchAllOrFail().isEmpty)
            XCTAssertTrue(scheduler.scheduledIDs.isEmpty)
        }
    }

    func testSaveRechecksAuthorizationRevokedWhileTheFormWasOpen() {
        let probe = AlarmsListBackendGuardTests.StubProbe(result: .available)
        let model = makeViewModel(probe: probe)
        model.backendMonitor.refresh()
        probe.result = .unavailable
        var outcomes: [CreateAlarmViewModel.SaveOutcome] = []

        model.save { outcomes.append($0) }

        XCTAssertEqual(outcomes, [.permissionRequired(.unavailable)])
        XCTAssertTrue(repository.fetchAllOrFail().isEmpty)
        XCTAssertTrue(scheduler.scheduledIDs.isEmpty)
        XCTAssertEqual(probe.authorizationRequestCount, 0, "Save must explain before requesting")
    }

    func testRejectedScheduleLeavesNoRecordAndRetryCreatesExactlyOneAlarm() {
        let model = makeViewModel(probe: AlarmsListBackendGuardTests.StubProbe(result: .available))
        scheduler.scheduleResult = .failure(.backendUnavailable)
        var outcomes: [CreateAlarmViewModel.SaveOutcome] = []
        for _ in 0..<3 {
            model.save { outcomes.append($0) }
            XCTAssertTrue(repository.fetchAllOrFail().isEmpty, "A failed draft must not become a saved alarm")
        }
        XCTAssertEqual(outcomes, Array(repeating: .schedulingFailed(.backendUnavailable), count: 3))

        scheduler.scheduleResult = .success(())
        model.save { outcomes.append($0) }
        XCTAssertEqual(outcomes.last, .success)
        XCTAssertEqual(repository.fetchAllOrFail().count, 1)
        XCTAssertEqual(Set(scheduler.scheduledIDs).count, 1, "Retries retain the draft identity")
    }

    func testRevocationDuringSchedulingRollsBackBeforeReportingFailure() {
        let probe = AlarmsListBackendGuardTests.StubProbe(result: .available)
        let model = makeViewModel(probe: probe)
        scheduler.onSchedule = { probe.result = .unavailable }
        scheduler.scheduleResult = .failure(.backendUnavailable)
        var outcomes: [CreateAlarmViewModel.SaveOutcome] = []

        model.save { outcome in
            outcomes.append(outcome)
            XCTAssertTrue(self.repository.fetchAllOrFail().isEmpty, "Rollback precedes the UI error callback")
        }

        XCTAssertEqual(outcomes, [.schedulingFailed(.backendUnavailable)])
        model.backendMonitor.refresh()
        XCTAssertEqual(model.backendMonitor.availability, .unavailable)
    }

    func testRejectedEditPreservesOriginalFieldsAndDisablesTheUnarmedAlarm() {
        let original = Alarm(name: "Original", penaltyAmount: 149, enabled: true, volume: 0.4)
        XCTAssertTrue(repository.save(original))
        let model = makeViewModel(probe: AlarmsListBackendGuardTests.StubProbe(result: .available), alarm: original)
        model.name = "Rejected edit"
        model.penaltyAmount = 499
        scheduler.scheduleResult = .failure(.system(message: "limit"))
        var outcome: CreateAlarmViewModel.SaveOutcome?

        model.save { outcome = $0 }

        XCTAssertEqual(outcome, .schedulingFailed(.system(message: "limit")))
        XCTAssertEqual(repository.fetchAllOrFail(), [original.with(enabled: false)])
    }

    func testDeniedPermissionStillAllowsEditingAnAlreadyDisabledAlarm() {
        let original = Alarm(name: "Disabled", enabled: false)
        XCTAssertTrue(repository.save(original))
        let model = makeViewModel(probe: AlarmsListBackendGuardTests.StubProbe(result: .unavailable), alarm: original)
        model.name = "Renamed"
        var outcome: CreateAlarmViewModel.SaveOutcome?

        model.save { outcome = $0 }

        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(repository.fetchAllOrFail(), [original.with(name: "Renamed")])
        XCTAssertTrue(scheduler.scheduledIDs.isEmpty)
    }

    func testLateFailureNeverUndoesANewerSaveEvenWithIdenticalValues() {
        for identical in [false, true] {
            let delayed = DelayedScheduler()
            let repo = AlarmRepository(defaults: defaults, scheduler: delayed)
            let candidate = Alarm(name: "First")
            XCTAssertTrue(repo.save(candidate, rollbackOnSchedulingFailure: true))
            let later = identical ? candidate : candidate.with(name: "Later")
            XCTAssertTrue(repo.save(later, rollbackOnSchedulingFailure: true))

            delayed.completions[1]?(.success(()))
            delayed.completions[0]?(.failure(.backendUnavailable))

            XCTAssertEqual(repo.fetchOrFail(id: candidate.id), later)
            XCTAssertTrue(repo.delete(id: candidate.id))
            delayed.completions.removeAll()
        }
    }

    private final class DelayedScheduler: AlarmScheduling {
        var completions: [((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?] = []
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completions.append(completion)
        }
        func cancel(_ alarmID: UUID) {}
    }
}
