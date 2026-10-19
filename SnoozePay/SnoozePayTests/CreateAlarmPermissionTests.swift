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
        alarm: Alarm? = nil,
        repository: AlarmRepository? = nil
    ) -> CreateAlarmViewModel {
        CreateAlarmViewModel(
            alarm: alarm, repository: repository ?? self.repository,
            defaults: AlarmDefaults(defaults: defaults),
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
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
        let original = Alarm(repeatDays: [0, 2], name: "Disabled", enabled: false, repeatMode: .weekly)
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

    func testPendingSaveStaysExclusiveAcrossRepeatEditsAndBothSaveEntryPoints() throws {
        for editing in [false, true] {
            for startThroughUI in [false, true] {
                let delayed = DelayedScheduler()
                defer { delayed.completions.removeAll() }
                let repo = AlarmRepository(defaults: defaults, scheduler: delayed)
                let original = Alarm(name: "Original", penaltyAmount: 149, enabled: false)
                if editing { XCTAssertTrue(repo.save(original)) }
                let model = makeViewModel(
                    probe: AlarmsListBackendGuardTests.StubProbe(result: .available),
                    alarm: editing ? original : nil, repository: repo
                )
                model.enabled = true
                model.name = "Unconfirmed candidate"
                let controller = CreateAlarmViewController(viewModel: model)
                controller.loadViewIfNeeded()
                let saveButton = try XCTUnwrap(controller.saveButton)
                var savedCallbacks = 0
                controller.onSave = { savedCallbacks += 1 }
                if startThroughUI {
                    saveButton.sendActions(for: .touchUpInside)
                } else {
                    XCTAssertTrue(model.save())
                }
                XCTAssertTrue(model.isSaving)
                XCTAssertEqual(delayed.completions.count, 1)

                model.repeatDays = [0, 2]
                model.repeatMode = .weekly
                controller.refreshRepeatValidity()
                XCTAssertFalse(model.canSave)
                XCTAssertFalse(saveButton.isEnabled, "Editing repeat must not reopen a pending Save")
                var duplicateOutcome: CreateAlarmViewModel.SaveOutcome?
                model.save { duplicateOutcome = $0 }
                XCTAssertEqual(duplicateOutcome, .alreadySaving)
                XCTAssertFalse(model.save(), "The legacy entry point shares the same pending guard")
                saveButton.sendActions(for: .touchUpInside)
                XCTAssertEqual(delayed.completions.count, 1, "Overlapping taps must not start another schedule")
                XCTAssertEqual(savedCallbacks, 0, "An overlapping Save cannot dismiss or report success")

                delayed.completions[0]?(.failure(.backendUnavailable))

                XCTAssertFalse(model.isSaving)
                XCTAssertTrue(model.canSave)
                XCTAssertEqual(savedCallbacks, 0)
                XCTAssertEqual(repo.fetchAllOrFail(), editing ? [original] : [])
                if editing { XCTAssertTrue(repo.delete(id: original.id)) }
            }
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
