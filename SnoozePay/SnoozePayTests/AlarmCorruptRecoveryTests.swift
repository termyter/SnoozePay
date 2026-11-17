import XCTest
@testable import SnoozePay

@MainActor
final class AlarmCorruptRecoveryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let corrupt = Data("unreadable alarm store".utf8)

    override func setUp() {
        super.setUp()
        suite = "test.corruptRecovery.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testVerifiedCleanupCommitsOnlyAfterBackendSuccessAndKeepsBackup() throws {
        let backend = RecoveryBackend()
        let repository = makeRepository(backend)
        defaults.set(corrupt, forKey: "stored_alarms")
        backend.onRecovery = {
            XCTAssertEqual(self.defaults.data(forKey: "stored_alarms"), self.corrupt)
            XCTAssertEqual(self.defaults.data(forKey: AlarmRepository.corruptBackupKey), self.corrupt)
        }
        try repository.clearCorruptState().get()
        XCTAssertEqual(backend.recoveries, 1)
        XCTAssertEqual(backend.fullCancels, 0)
        XCTAssertFalse(repository.lastLoadFailed)
        XCTAssertNil(defaults.object(forKey: "stored_alarms"))
        XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertTrue(repository.save(Alarm(enabled: false)))
    }

    func testFailedCleanupPreservesBytesBackupAndLockAndCanRetry() throws {
        let failures: [AlarmRecoveryError] = [
            .unsupported, .inventoryUnavailable, .cancellationFailed, .registrationsRemain
        ]
        for failure in failures {
            let backend = RecoveryBackend()
            let repository = makeRepository(backend)
            defaults.set(corrupt, forKey: "stored_alarms")
            backend.outcome = .failure(failure)
            XCTAssertEqual(repository.clearCorruptState().failure, failure)
            XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
            XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
            XCTAssertTrue(repository.lastLoadFailed)
            XCTAssertFalse(repository.save(Alarm(enabled: false)))
            backend.outcome = .success(())
            try repository.clearCorruptState().get()
            XCTAssertNil(defaults.object(forKey: "stored_alarms"))
            XCTAssertFalse(repository.lastLoadFailed)
        }
    }

    func testStaleFailureFlagDoesNotSweepOrEraseAHealthyStore() throws {
        let backend = RecoveryBackend()
        let repository = makeRepository(backend)
        defaults.set(corrupt, forKey: "stored_alarms")
        XCTAssertThrowsError(try repository.fetchAllChecked())
        let healthy = try JSONEncoder().encode([Alarm(enabled: false)])
        defaults.set(healthy, forKey: "stored_alarms")
        try repository.clearCorruptState().get()
        XCTAssertEqual(defaults.data(forKey: "stored_alarms"), healthy)
        XCTAssertFalse(repository.lastLoadFailed)
        XCTAssertEqual(backend.recoveries, 0)
    }

    func testUnknownBackendCannotAuthorizeErasingCorruptData() {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())
        let repository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        defaults.set(corrupt, forKey: "stored_alarms")
        XCTAssertEqual(repository.clearCorruptState().failure, .unsupported)
        XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
        XCTAssertTrue(repository.lastLoadFailed)
    }

    func testEveryRegistrationPathBlocksRecoveryUntilItsCallbackEndsExactlyOnce() throws {
        for path in 0..<6 {
            let backend = RecoveryBackend()
            backend.failRegistration = path >= 3
            let sessions = AlarmSnoozeSessionStore(defaults: defaults)
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                           snoozeSessions: sessions)
            let repository = AlarmRepository(defaults: defaults, scheduler: scheduler)
            defaults.set(corrupt, forKey: "stored_alarms")
            let alarm = Alarm()
            let token = try sessions.reserve(alarmID: alarm.id, sessionID: nil, expectedCount: 0)
            try sessions.recordCharge(token, alarmID: alarm.id)
            defer { sessions.operationEnded(token) }
            var callbacks = 0
            var commits = 0
            let completed: (Bool) -> Void = { failed in
                MainActor.assertIsolated()
                XCTAssertEqual(failed, path >= 3)
                callbacks += 1
                XCTAssertEqual(scheduler.recoverCorruptAlarms { commits += 1 }.failure, .busy)
            }
            switch path % 3 {
            case 0: scheduler.schedule(alarm) { completed($0.didFail) }
            case 1: scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { completed($0.didFail) }
            default: scheduler.scheduleTrackedSnooze(for: alarm, token: token) { completed($0.didFail) }
            }
            XCTAssertEqual(scheduler.recoverCorruptAlarms { commits += 1 }.failure, .busy)
            XCTAssertEqual(repository.clearCorruptState().failure, .busy)
            XCTAssertTrue(repository.lastLoadFailed)
            XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
            XCTAssertEqual(backend.recoveries, 0)
            backend.finish?()
            backend.finish?()
            XCTAssertEqual(callbacks, 1)
            try repository.clearCorruptState().get()
            XCTAssertNil(defaults.object(forKey: "stored_alarms"))
            XCTAssertFalse(repository.lastLoadFailed)
            XCTAssertEqual(commits, 0)
            XCTAssertEqual(backend.recoveries, 1)
        }
    }

    func testRecoveryPreventsAllRegistrationsThroughSynchronousCommit() throws {
        let backend = RecoveryBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        let alarm = Alarm()
        var refusals = 0
        let attemptRegistrations = {
            scheduler.schedule(alarm) { result in
                if case .failure = result { refusals += 1 }
            }
            scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { result in
                if case .failure = result { refusals += 1 }
            }
            scheduler.scheduleTrackedSnooze(for: alarm, token: .init(sessionID: UUID(), attemptID: UUID())) { result in
                if case .failure = result { refusals += 1 }
            }
        }
        backend.onRecovery = attemptRegistrations
        try scheduler.recoverCorruptAlarms {
            MainActor.assertIsolated()
            XCTAssertEqual(scheduler.recoverCorruptAlarms {}.failure, .busy)
            attemptRegistrations()
        }.get()
        XCTAssertEqual(refusals, 6)
        XCTAssertEqual(backend.registrations, 0)
        XCTAssertEqual(backend.stops, 0)
        scheduler.schedule(alarm)
        XCTAssertEqual(backend.registrations, 1, "registration resumes after the commit scope")
        backend.finish?()
        try scheduler.recoverCorruptAlarms {}.get()
    }

    private func makeRepository(_ backend: RecoveryBackend) -> AlarmRepository {
        AlarmRepository(defaults: defaults, scheduler: AlarmScheduler(
            notificationCenter: InertNotificationCenter(), alarmKit: backend
        ))
    }

    private final class RecoveryBackend: AlarmKitScheduling {
        var isAuthorized = true
        var outcome: Result<Void, AlarmRecoveryError> = .success(())
        var onRecovery: (() -> Void)?
        var finish: (() -> Void)?
        var recoveries = 0
        var registrations = 0
        var stops = 0
        var fullCancels = 0
        var failRegistration = false
        func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
        func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
            registrations += 1
            finish = { completion(self.failRegistration
                ? .failure(AlarmRecoveryError.unsupported) : .success(())) }
        }
        func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
            schedule(alarm, completion: completion)
        }
        // swiftlint:disable:next function_parameter_count
        func scheduleTrackedSnooze(
            _ alarm: Alarm, fireDate: Date, token: AlarmSnoozeToken, attemptCount: Int,
            isCurrent: @escaping () -> Bool, completion: @escaping (Result<AlarmSnoozeReceipt, Error>) -> Void
        ) {
            registrations += 1
            finish = { completion(self.failRegistration ? .failure(AlarmRecoveryError.unsupported)
                : .success(.init(systemID: alarm.id, fireDate: fireDate))) }
        }
        func clearRegisteredAlarmsForRecovery() -> Result<Void, AlarmRecoveryError> {
            recoveries += 1
            onRecovery?()
            return outcome
        }
        func cancelOriginal(_ alarmID: UUID) {}
        func cancel(_ alarmID: UUID) { fullCancels += 1 }
        func stop(_ alarmID: UUID) { stops += 1 }
    }
}

private extension Result where Failure == AlarmRecoveryError {
    var failure: AlarmRecoveryError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

private extension Result {
    var didFail: Bool {
        if case .failure = self { return true }
        return false
    }
}
