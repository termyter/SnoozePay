import XCTest
@testable import SnoozePay

/// Issue #118, carried forward to the AlarmKit-only backend (#472).
///
/// `AlarmScheduler.schedule` must surface every reason an alarm did NOT get
/// armed to its UI caller instead of swallowing it to `AppLogger.scheduler.error`.
/// The original silent-failure regression — a "Будильник создан" toast on an
/// alarm that never registered — has two shapes now:
///
/// 1. the backend rejected the schedule → `.system(message:)`;
/// 2. the backend was never authorized, so nothing was even attempted →
///    `.backendUnavailable`.
///
/// Before #472 case 2 did not exist: an unauthorized AlarmKit quietly degraded
/// to a `.timeSensitive` notification and the caller was told "success". That
/// notification pings once and cannot wake a sleeping user, which made "the
/// alarm is set" a lie the app had no way of noticing.
final class AlarmSchedulerErrorPropagationTests: XCTestCase {

    private func makeAlarm() -> Alarm {
        Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6], name: "Daily", penaltyAmount: 50)
    }

    // MARK: - schedule(_:completion:) error path

    func testSchedule_propagatesBackendErrorToCompletion() {
        let backend = TestAlarmKitBackend(failSchedule: true)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(makeAlarm()) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.system(let message)) = captured else {
            return XCTFail("Expected .failure(.system), got \(String(describing: captured))")
        }
        XCTAssertFalse(message.isEmpty, "The backend's reason must reach the user, not just Console")
    }

    func testSchedule_successPath_completesWithSuccess() {
        let backend = TestAlarmKitBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        let alarm = makeAlarm()

        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(alarm) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .success = captured else {
            return XCTFail("Expected .success, got \(String(describing: captured))")
        }
        XCTAssertEqual(backend.scheduledIDs, [alarm.id])
    }

    func testSchedule_disabledAlarm_skipsBackendAndReportsSuccess() {
        let backend = TestAlarmKitBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(Alarm(name: "Off", penaltyAmount: 50, enabled: false)) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .success = captured else {
            return XCTFail("A disabled alarm is a no-op success, got \(String(describing: captured))")
        }
        XCTAssertTrue(backend.scheduledIDs.isEmpty, "A disabled alarm must not reach the backend")
    }

    // MARK: - Refusal without a grant (#472)

    func testSchedule_unauthorizedBackend_refusesWithTypedError() {
        let backend = TestAlarmKitBackend(authorization: .denied)
        let center = InertNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: backend)

        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(makeAlarm()) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.backendUnavailable) = captured else {
            return XCTFail("Expected .failure(.backendUnavailable), got \(String(describing: captured))")
        }
        XCTAssertTrue(backend.scheduledIDs.isEmpty, "An unauthorized backend must not be called")
        XCTAssertTrue(center.addedRequests.isEmpty,
                      "Refusal must NOT degrade to a notification — that fallback is gone (#472)")
    }

    func testSchedule_notDeterminedBackend_refusesToo() {
        let backend = TestAlarmKitBackend(authorization: .notDetermined)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(makeAlarm()) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.backendUnavailable) = captured else {
            return XCTFail("An unanswered prompt still means no alarm, got \(String(describing: captured))")
        }
    }

    func testSchedule_noBackendWired_refuses() {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)

        let exp = expectation(description: "schedule completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(makeAlarm()) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.backendUnavailable) = captured else {
            return XCTFail("Expected .failure(.backendUnavailable), got \(String(describing: captured))")
        }
    }

    /// The refusal must read as an explanation, not as an empty string — this is
    /// the text the create / toggle path shows the user.
    func testBackendUnavailable_hasUserFacingDescription() {
        let description = AlarmScheduler.SchedulingError.backendUnavailable.errorDescription
        XCTAssertNotNil(description)
        XCTAssertFalse(description?.isEmpty ?? true)
    }

    // MARK: - scheduleSnooze error path

    func testScheduleSnooze_propagatesBackendErrorToCompletion() {
        let backend = TestAlarmKitBackend(failSnooze: true)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)

        let exp = expectation(description: "snooze completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.scheduleSnooze(for: makeAlarm(), snoozeCount: 1) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.system) = captured else {
            return XCTFail("Expected .failure(.system), got \(String(describing: captured))")
        }
    }

    /// The penalty is charged before the re-ring is armed, so a refusal MUST be
    /// a typed failure — the coordinator refunds on it.
    func testScheduleSnooze_unauthorizedBackend_refusesWithTypedError() {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)

        let exp = expectation(description: "snooze completes")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.scheduleSnooze(for: makeAlarm(), snoozeCount: 1) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        guard case .failure(.backendUnavailable) = captured else {
            return XCTFail("Expected .failure(.backendUnavailable), got \(String(describing: captured))")
        }
    }
}
