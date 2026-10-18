import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
final class AlarmSchedulerPaidSnoozeRearmTests: XCTestCase {
    private let alarmID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private let snoozeID = UUID(uuid: (0x53, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private let originalDate = Date(timeIntervalSince1970: 2_000_000_000)
    private let paidFireDate = Date(timeIntervalSince1970: 2_000_000_123.375)

    func testRepeatedRearmPreservesPaidSnoozeAndSkipsDisabledSchedules() {
        let alarm = dailyAlarm()
        let disabled = Alarm(time: originalDate, enabled: false)
        let backend = backendWithPaidSnooze(alarm)
        backend.schedule(disabled) { _ in }
        backend.scheduleSnooze(disabled, fireDate: paidFireDate) { _ in }
        let before = backend.pending
        let center = InertNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: backend)

        for _ in 0..<2 {
            XCTAssertEqual(rearm(scheduler, alarms: [alarm, disabled]), 0)
            XCTAssertEqual(backend.pending, before)
            XCTAssertEqual(backend.pending[snoozeID], paidFireDate,
                           "Foreground rearm must neither cancel nor restart the paid deadline")
            XCTAssertEqual(backend.pending[alarmID], originalDate)
        }

        let legacyIDs = (0..<7).map { "alarm_\(alarmID.uuidString)_day\($0)" }
            + ["alarm_\(alarmID.uuidString)_once", "snooze_\(alarmID.uuidString)"]
        XCTAssertEqual(Set(center.removedIdentifiers), Set(legacyIDs))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testRejectedRearmPreservesPaidSnoozeAndReportsOriginalFailure() {
        let alarm = dailyAlarm()
        let backend = backendWithPaidSnooze(alarm)
        backend.failSchedule = true
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        XCTAssertEqual(rearm(scheduler, alarms: [alarm]), 1)
        XCTAssertEqual(backend.pending, [snoozeID: paidFireDate])
    }

    func testRevokedAuthorizationPreservesPaidSnoozeAndReportsOriginalFailure() {
        let alarm = dailyAlarm()
        let backend = backendWithPaidSnooze(alarm)
        backend.authorization = .denied
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        XCTAssertEqual(rearm(scheduler, alarms: [alarm]), 1)
        XCTAssertEqual(backend.pending, [snoozeID: paidFireDate])
    }

    func testExplicitFullCancelRemovesOriginalAndPaidSnoozeEvenAfterAuthorizationRevoked() {
        let alarm = dailyAlarm()
        let backend = backendWithPaidSnooze(alarm)
        XCTAssertEqual(backend.pending, [alarmID: originalDate, snoozeID: paidFireDate])
        backend.authorization = .denied
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        scheduler.cancel(alarm.id)

        XCTAssertTrue(backend.pending.isEmpty,
                      "Disable, delete and finish must still cancel both system IDs")
    }

    private func dailyAlarm() -> Alarm {
        Alarm(id: alarmID, time: originalDate, repeatDays: [0, 1, 2, 3, 4, 5, 6])
    }

    private func backendWithPaidSnooze(_ alarm: Alarm) -> PendingAlarmKitBackend {
        let backend = PendingAlarmKitBackend()
        backend.schedule(alarm) { _ in }
        backend.scheduleSnooze(alarm, fireDate: paidFireDate) { _ in }
        XCTAssertEqual(backend.pending, [alarmID: originalDate, snoozeID: paidFireDate])
        return backend
    }

    private func rearm(_ scheduler: AlarmScheduler, alarms: [Alarm]) -> Int? {
        let completed = expectation(description: "all rearm outcomes reported")
        var failures: Int?
        scheduler.rescheduleAll(alarms) { failures = $0; completed.fulfill() }
        wait(for: [completed], timeout: 5)
        return failures
    }
}

/// Retains actual pending IDs/dates, and executes the production cancellation
/// methods against that state. A recording-only `cancel` would hide #935.
@available(iOS 26.0, *)
private final class PendingAlarmKitBackend: AlarmKitScheduling {
    var authorization: AlarmKitAuthorization = .authorized
    var isAuthorized: Bool { authorization == .authorized }
    var failSchedule = false
    private(set) var pending: [UUID: Date] = [:]
    private lazy var cancellation = AlarmKitScheduler(cancelAlarm: { [unowned self] alarmID in
        _ = self.pending.removeValue(forKey: alarmID)
    })

    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(isAuthorized) }

    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !failSchedule else {
            completion(.failure(TestAlarmKitBackend.ScheduleRejected()))
            return
        }
        pending[alarm.id] = alarm.time
        completion(.success(()))
    }

    func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        pending[AlarmKitScheduler.snoozeID(for: alarm.id)] = fireDate
        completion(.success(()))
    }

    func cancelOriginal(_ alarmID: UUID) { cancellation.cancelOriginal(alarmID) }
    func cancel(_ alarmID: UUID) { cancellation.cancel(alarmID) }
    func stop(_ alarmID: UUID) {}
}
