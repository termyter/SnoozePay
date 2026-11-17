import Foundation
import os
import XCTest
@testable import SnoozePay

/// The recovery reservation composed with scoped occurrence finish (#1062 × #1063):
/// finish paths refuse `.busy` while recovery runs or while the SAME alarm's native
/// registration callback is in flight, and every registration exit releases it.
@MainActor
final class AlarmRecoveryGuardTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    private struct LoggedLine: Equatable {
        let category: AppLogCategory
        let level: OSLogType
        let message: String
    }

    private enum Registration: CaseIterable { case schedule, legacySnooze, trackedSnooze }

    override func setUp() {
        super.setUp()
        suite = "test.recoveryGuard.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - (a) callback in flight

    func testFinishPathsAreBusyOnlyForTheAlarmWhoseCallbackIsInFlight() throws {
        for registration in Registration.allCases {
            let backend = GuardBackend()
            let sessions = AlarmSnoozeSessionStore(defaults: defaults)
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                           snoozeSessions: sessions)
            let alarmA = Alarm()
            let alarmB = Alarm()
            // Settled sessions: the store's own live-callback check cannot answer `.busy`.
            let tokenA = try settledSession(sessions, alarmID: alarmA.id)
            let tokenB = try settledSession(sessions, alarmID: alarmB.id)
            var callbacks = 0
            switch registration {
            case .schedule:
                scheduler.schedule(alarmA) { _ in callbacks += 1 }
            case .legacySnooze:
                scheduler.scheduleSnooze(for: alarmA, snoozeCount: 1) { _ in callbacks += 1 }
            case .trackedSnooze:
                scheduler.scheduleTrackedSnooze(for: alarmA, token: tokenA) { _ in callbacks += 1 }
            }
            XCTAssertEqual(backend.registrations, 1, "\(registration)")
            let ticketA = try sessions.beginOccurrenceFinish(alarmID: alarmA.id, reference: .token(tokenA))
            let ticketB = try sessions.beginOccurrenceFinish(alarmID: alarmB.id, reference: .token(tokenB))

            for outcome in finishOutcomes(scheduler, alarmA, ticketA) {
                XCTAssertEqual(outcome, .busy, "\(registration): alarm A's callback is still in flight")
            }
            for outcome in finishOutcomes(scheduler, alarmB, ticketB) {
                XCTAssertNotEqual(outcome, .busy, "\(registration): alarm B has no registration in flight")
            }

            backend.finish?()
            XCTAssertEqual(callbacks, 1, "\(registration)")
            for outcome in finishOutcomes(scheduler, alarmA, ticketA) {
                XCTAssertNotEqual(outcome, .busy, "\(registration): the callback scope has ended")
            }
        }
    }

    // MARK: - (b) recovery in progress

    func testFinishPathsAreBusyWhileRecoveryRuns() throws {
        let backend = GuardBackend()
        let sessions = AlarmSnoozeSessionStore(defaults: defaults)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: sessions)
        let alarm = Alarm()
        let token = try settledSession(sessions, alarmID: alarm.id)
        let ticket = try sessions.beginOccurrenceFinish(alarmID: alarm.id, reference: .token(token))
        XCTAssertFalse(finishOutcomes(scheduler, alarm, ticket).contains(.busy), "control: idle is not busy")

        var observed: [AlarmOccurrenceFinishError?] = []
        backend.onRecovery = { observed = self.finishOutcomes(scheduler, alarm, ticket) }
        try scheduler.recoverCorruptAlarms {}.get()

        XCTAssertEqual(backend.recoveries, 1)
        XCTAssertEqual(observed, [.busy, .busy, .busy])
        XCTAssertFalse(finishOutcomes(scheduler, alarm, ticket).contains(.busy), "recovery scope has ended")
    }

    // MARK: - (c) early exits release the reservation

    func testLegacySnoozeRefusedByAPendingFinishReleasesTheReservation() throws {
        let backend = GuardBackend()
        let sessions = AlarmSnoozeSessionStore(defaults: defaults)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: sessions)
        let alarm = Alarm()
        _ = try sessions.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        var results: [Result<Void, AlarmScheduler.SchedulingError>] = []

        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { results.append($0) }

        XCTAssertEqual(results.count, 1, "refused synchronously, exactly once")
        guard case .failure(.system)? = results.first else { return XCTFail("expected a refusal") }
        XCTAssertEqual(backend.registrations, 0)
        XCTAssertEqual(backend.stops, 0)
        try scheduler.recoverCorruptAlarms {}.get()
        XCTAssertEqual(backend.recoveries, 1)
    }

    func testTrackedSnoozeWithoutASessionStoreReleasesTheReservation() throws {
        let backend = GuardBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        var results: [Result<AlarmSnoozeReceipt, Error>] = []

        scheduler.scheduleTrackedSnooze(for: Alarm(), token: .init(sessionID: UUID(), attemptID: UUID())) {
            results.append($0)
        }

        XCTAssertEqual(results.count, 1, "refused synchronously, exactly once")
        guard case .failure(let error)? = results.first else { return XCTFail("expected a refusal") }
        XCTAssertEqual(error as? AlarmSnoozeContextError, .unavailable)
        XCTAssertEqual(backend.registrations, 0)
        try scheduler.recoverCorruptAlarms {}.get()
        XCTAssertEqual(backend.recoveries, 1)
    }

    // MARK: - Recovery refusal diagnostics

    func testBusyRecoveryRefusalLogsItsState() {
        let backend = GuardBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        scheduler.schedule(Alarm())
        var lines: [LoggedLine] = []
        var result: Result<Void, AlarmRecoveryError>?

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            result = scheduler.recoverCorruptAlarms {}
        })

        XCTAssertEqual(result?.recoveryFailure, .busy)
        XCTAssertEqual(lines, [LoggedLine(
            category: .scheduler, level: .error,
            message: "Alarm recovery refused: busy recovering=false registrations=1"
        )])
        backend.finish?()
    }

    func testRecoveryWithoutABackendLogsTheRefusal() {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter())
        var lines: [LoggedLine] = []
        var result: Result<Void, AlarmRecoveryError>?

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            result = scheduler.recoverCorruptAlarms { XCTFail("an unsupported recovery cannot commit") }
        })

        XCTAssertEqual(result?.recoveryFailure, .unsupported)
        XCTAssertEqual(lines, [LoggedLine(
            category: .scheduler, level: .error, message: "Alarm recovery refused: no AlarmKit backend"
        )])
    }

    // MARK: - Helpers

    private func settledSession(_ sessions: AlarmSnoozeSessionStore, alarmID: UUID) throws -> AlarmSnoozeToken {
        let token = try sessions.reserve(alarmID: alarmID, sessionID: nil, expectedCount: 0)
        defer { sessions.operationEnded(token) }
        try sessions.recordCharge(token, alarmID: alarmID)
        return token
    }

    /// finishOccurrence, verifyPendingOccurrenceFinish, retireSupersededOccurrenceFinish.
    private func finishOutcomes(
        _ scheduler: AlarmScheduler, _ alarm: Alarm, _ ticket: AlarmOccurrenceFinishTicket
    ) -> [AlarmOccurrenceFinishError?] {
        [
            scheduler.finishOccurrence(for: alarm, ticket: ticket).finishFailure,
            scheduler.verifyPendingOccurrenceFinish(currentAlarm: alarm, ticket: ticket).finishFailure,
            scheduler.retireSupersededOccurrenceFinish(for: alarm, ticket: ticket).finishFailure
        ]
    }

    private final class GuardBackend: CoarseAlarmKitAuthorization, UnknownAlarmKitInventory,
        RefusesAlarmKitOccurrenceFinish, RefusesAlarmKitFinishVerification, RefusesAlarmKitSupersedeVerification {
        var isAuthorized = true
        var onRecovery: (() -> Void)?
        var finish: (() -> Void)?
        var recoveries = 0
        var registrations = 0
        var stops = 0
        func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
        func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
            registrations += 1
            finish = { completion(.success(())) }
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
            finish = { completion(.success(.init(systemID: alarm.id, fireDate: fireDate))) }
        }
        func cancelTrackedSnooze(_ alarmID: UUID) -> Bool { false }
        func clearRegisteredAlarmsForRecovery() -> Result<Void, AlarmRecoveryError> {
            recoveries += 1
            onRecovery?()
            return .success(())
        }
        func cancelOriginal(_ alarmID: UUID) {}
        func cancel(_ alarmID: UUID) {}
        func stop(_ alarmID: UUID) { stops += 1 }
    }
}

private extension Result where Failure == AlarmOccurrenceFinishError {
    var finishFailure: AlarmOccurrenceFinishError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

private extension Result where Failure == AlarmRecoveryError {
    var recoveryFailure: AlarmRecoveryError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
