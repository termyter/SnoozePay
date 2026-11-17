import XCTest
@testable import SnoozePay

/// Issue #427 — saved alarms were never re-armed after a timezone / DST shift,
/// a reboot, or an authorization change, so they could fire at the wrong
/// wall-clock time or stop firing entirely. `rescheduleAll` is the re-arm
/// primitive AppDelegate calls from the relevant system signals. It must
/// `cancelOriginal` + `schedule` every future **enabled** alarm and leave alerting
/// originals and **disabled** alarms untouched.
///
/// Since #472 the re-arm goes to AlarmKit and nowhere else, so the assertions
/// read the AlarmKit backend rather than a notification center.
final class AlarmSchedulerRescheduleAllTests: XCTestCase {

    private func dailyAlarm(name: String, enabled: Bool) -> Alarm {
        Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6], name: name, enabled: enabled)
    }

    private func makeScheduler(
        _ backend: TestAlarmKitBackend
    ) -> AlarmScheduler {
        AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
    }

    func testRescheduleAll_reschedulesEnabled_skipsDisabled() {
        let backend = TestAlarmKitBackend(alertingAlarmIDs: [])
        let scheduler = makeScheduler(backend)

        let on = dailyAlarm(name: "On", enabled: true)
        let off = dailyAlarm(name: "Off", enabled: false)

        let exp = expectation(description: "completion")
        scheduler.rescheduleAll([on, off]) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)

        XCTAssertEqual(backend.scheduledIDs, [on.id],
                       "Only the enabled alarm is re-armed")
        XCTAssertTrue(backend.cancelledIDs.isEmpty, "Rearm must never request a full cancellation")
        XCTAssertEqual(backend.cancelledOriginalIDs, [on.id],
                       "Only the original enabled alarm is cancelled before being re-scheduled; "
                       + "a disabled one is not touched at all")
    }

    func testRescheduleAll_allEnabledAlerting_reportsZeroWithoutCancellation() {
        let alarms = [dailyAlarm(name: "A", enabled: true), dailyAlarm(name: "B", enabled: true)]
        let backend = TestAlarmKitBackend(alertingAlarmIDs: Set(alarms.map(\.id)))
        let scheduler = makeScheduler(backend)
        let exp = expectation(description: "completion")
        var reported: Int?

        scheduler.rescheduleAll(alarms) { reported = $0; exp.fulfill() }

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(reported, 0, "Preserving an already alerting alarm is a successful no-op")
        XCTAssertTrue(backend.cancelledOriginalIDs.isEmpty)
        XCTAssertTrue(backend.scheduledIDs.isEmpty)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
    }

    func testRescheduleAll_allDisabled_doesNothing() {
        let backend = TestAlarmKitBackend()
        let scheduler = makeScheduler(backend)

        let exp = expectation(description: "completion")
        scheduler.rescheduleAll([
            dailyAlarm(name: "A", enabled: false),
            dailyAlarm(name: "B", enabled: false)
        ]) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)

        XCTAssertTrue(backend.scheduledIDs.isEmpty,
                      "No enabled alarms — nothing should be scheduled")
        XCTAssertTrue(backend.cancelledOriginalIDs.isEmpty)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
    }

    func testRescheduleAll_emptyList_doesNothing() {
        let backend = TestAlarmKitBackend()
        let scheduler = makeScheduler(backend)

        let exp = expectation(description: "completion")
        scheduler.rescheduleAll([]) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)

        XCTAssertTrue(backend.scheduledIDs.isEmpty)
        XCTAssertTrue(backend.cancelledOriginalIDs.isEmpty)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
    }

    // MARK: - Failure aggregation (#442)

    func testRescheduleAll_allSchedulesSucceed_reportsZeroFailed() {
        let scheduler = makeScheduler(TestAlarmKitBackend(alertingAlarmIDs: []))

        let exp = expectation(description: "completion")
        var reported: Int?
        scheduler.rescheduleAll([
            dailyAlarm(name: "A", enabled: true),
            dailyAlarm(name: "B", enabled: true)
        ]) { reported = $0; exp.fulfill() }

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(reported, 0, "All schedules succeeded → zero failures reported")
    }

    func testRescheduleAll_scheduleFailures_reportsFailedCount() {
        let scheduler = makeScheduler(TestAlarmKitBackend(failSchedule: true, alertingAlarmIDs: []))

        let exp = expectation(description: "completion")
        var reported: Int?
        scheduler.rescheduleAll([
            dailyAlarm(name: "A", enabled: true),
            dailyAlarm(name: "B", enabled: true),
            dailyAlarm(name: "Off", enabled: false)
        ]) { reported = $0; exp.fulfill() }

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(reported, 2,
                       "Both enabled alarms failed to re-arm → failedCount 2 (disabled skipped)")
    }

    /// A revoked grant is the #427 case that used to be invisible: before #472
    /// the alarm silently moved to a notification and `rescheduleAll` reported
    /// zero failures. Now every enabled alarm counts as failed, which is what
    /// makes `AppDelegate.handleRescheduleOutcome` able to warn.
    func testRescheduleAll_unauthorizedBackend_countsEveryEnabledAlarmAsFailed() {
        let backend = TestAlarmKitBackend(authorization: .denied)
        let scheduler = makeScheduler(backend)
        let alarms = [dailyAlarm(name: "A", enabled: true), dailyAlarm(name: "B", enabled: true)]

        let exp = expectation(description: "completion")
        var reported: Int?
        scheduler.rescheduleAll(alarms) { reported = $0; exp.fulfill() }

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(reported, 2, "Without a grant nothing is armed — and it must be reported")
        XCTAssertEqual(backend.cancelledOriginalIDs, alarms.map(\.id),
                       "Revoked authorization must still clean up originals even when inventory is unknown")
        XCTAssertTrue(backend.scheduledIDs.isEmpty, "The unavailable backend must not receive a schedule")
        XCTAssertTrue(backend.cancelledIDs.isEmpty, "Cleanup must preserve independently scheduled paid snoozes")
    }

    func testRescheduleAll_emptyEnabled_reportsZeroImmediately() {
        let scheduler = makeScheduler(TestAlarmKitBackend())

        let exp = expectation(description: "completion")
        var reported: Int?
        scheduler.rescheduleAll([dailyAlarm(name: "Off", enabled: false)]) { reported = $0; exp.fulfill() }

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(reported, 0)
    }
}
