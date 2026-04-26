import XCTest
import UserNotifications
@testable import SnoozePay

/// Pins the snooze fire-date arithmetic and identifier scheme.
///
/// The arithmetic is dangerous: `now + snoozeMinutes * 60`. If the `* 60`
/// drops, snooze fires immediately; if it becomes `* 60 * 60`, snooze fires
/// hours later. Both regressions silently break the core product, so we
/// pin them via the pure factory `AlarmScheduler.scheduledFireDate`.
final class AlarmSchedulerSnoozeTests: XCTestCase {

    private let scheduler = AlarmScheduler.shared

    // MARK: - scheduledFireDate arithmetic

    func testScheduledFireDate_addsExactlyTheGivenMinutesInSeconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snoozeMinutes = 9

        let fireDate = AlarmScheduler.scheduledFireDate(now: now, snoozeMinutes: snoozeMinutes)

        XCTAssertEqual(
            fireDate.timeIntervalSince(now),
            TimeInterval(9 * 60),
            accuracy: 0.001,
            "9 minutes must add 540 seconds — guards against minute↔hour↔second unit confusion"
        )
    }

    func testScheduledFireDate_zeroMinutes_returnsNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fireDate = AlarmScheduler.scheduledFireDate(now: now, snoozeMinutes: 0)
        XCTAssertEqual(fireDate.timeIntervalSince(now), 0, accuracy: 0.001)
    }

    func testScheduledFireDate_oneMinute_addsSixtySeconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fireDate = AlarmScheduler.scheduledFireDate(now: now, snoozeMinutes: 1)
        XCTAssertEqual(fireDate.timeIntervalSince(now), 60, accuracy: 0.001)
    }

    func testScheduledFireDate_fifteenMinutes_addsNineHundredSeconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fireDate = AlarmScheduler.scheduledFireDate(now: now, snoozeMinutes: 15)
        XCTAssertEqual(
            fireDate.timeIntervalSince(now),
            900,
            accuracy: 0.001,
            "15 min must be exactly 900s — not 15h (54000s) or 15s"
        )
    }

    /// Verify a future date (real `Date()`) wires through correctly — the
    /// previous tests use a fixed timestamp; this one mimics the production
    /// call site at `scheduleSnooze`.
    func testScheduledFireDate_realNow_isInFutureBySnoozeMinutes() {
        let before = Date()
        let fireDate = AlarmScheduler.scheduledFireDate(now: before, snoozeMinutes: 5)
        let after = Date()

        XCTAssertGreaterThanOrEqual(fireDate.timeIntervalSince(before), 5 * 60 - 0.001)
        XCTAssertLessThanOrEqual(fireDate.timeIntervalSince(after), 5 * 60 + 0.001)
    }

    // MARK: - Snooze notification identifier

    func testSnoozeNotificationID_isStableAndScopedToAlarmID() {
        let alarmID = UUID()
        let id = scheduler.snoozeNotificationID(for: alarmID)

        XCTAssertEqual(id, "snooze_\(alarmID.uuidString)",
                       "Snooze identifier must follow `snooze_<alarmUUID>` — used by cancel(_:)")
    }

    func testSnoozeNotificationID_differsBetweenAlarms() {
        let id1 = scheduler.snoozeNotificationID(for: UUID())
        let id2 = scheduler.snoozeNotificationID(for: UUID())
        XCTAssertNotEqual(id1, id2,
                          "Different alarms must get distinct snooze IDs to avoid clobbering each other")
    }

    /// `cancel(_:)` filters pending requests by both the per-trigger prefix
    /// (`alarm_<UUID>_*`) and the snooze ID. Pinning the prefix here guards
    /// against the IOS-070-style regression where cancel missed a label.
    func testSnoozeNotificationID_doesNotShareScheduledAlarmPrefix() {
        let alarmID = UUID()
        let snoozeID = scheduler.snoozeNotificationID(for: alarmID)

        XCTAssertFalse(snoozeID.hasPrefix("alarm_"),
                       "Snooze ID must use a distinct prefix from scheduled-day IDs " +
                       "so cancel(_:) can filter both sets independently")
    }

    // MARK: - Snooze notification content (payload contents)

    func testScheduleSnooze_contentReflectsSnoozeCount() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 1)

        XCTAssertEqual(content.userInfo["snoozeCount"] as? Int, 1,
                       "Snooze re-fire payload must carry the running snooze count " +
                       "so the next charge is calculated from the right base")
    }

    func testScheduleSnooze_contentEscalatesPenaltyForProgressiveScale() {
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)

        // After 1 snooze, the next charge would be the 2nd snooze → 50 * 2 = 100
        let content = scheduler.makeContent(for: alarm, snoozeCount: 1)

        XCTAssertEqual(content.subtitle, "Отложить \u{00B7} 100 ₽",
                       "Progressive scale must compound the penalty across snooze re-fires")
    }
}
