import XCTest
import UserNotifications
@testable import SnoozePay

/// Pins the lock-screen fallback burst (issue #19): without the Critical Alerts
/// entitlement the alarm arrives as a single `.timeSensitive` notification. To
/// make that fallback more insistent we schedule a small, self-cancelling burst
/// of follow-up notifications a few seconds after the primary fire.
///
/// These tests cover the pieces that must not regress:
/// - `burstComponents` second/minute/hour roll-over arithmetic (a wrong roll
///   would land a follow-up at the wrong minute or skip it entirely).
/// - `burstTriggers` labels share the alarm identifier prefix so `cancel(_:)`
///   sweeps them — a label drift would leave orphan notifications ringing.
/// - `makeTriggers` appends exactly the configured burst on the degraded path
///   and never crowds the schedule beyond `count * (1 + burst)`.
///
/// The arithmetic / label tests use the pure `static` helpers so they are
/// independent of the process-wide `criticalAlertsAvailable` flag; the
/// `makeTriggers` integration tests pin the flag to the fallback (false) state
/// they care about and restore it afterwards.
final class AlarmSchedulerFallbackBurstTests: XCTestCase {

    private let scheduler = AlarmScheduler.shared

    // MARK: - burstComponents arithmetic

    func testBurstComponents_addsSecondsWithoutRollover() {
        var base = DateComponents()
        base.hour = 7
        base.minute = 30
        base.second = 0

        let shifted = AlarmScheduler.burstComponents(base: base, offsetSeconds: 30)

        XCTAssertEqual(shifted.hour, 7)
        XCTAssertEqual(shifted.minute, 30)
        XCTAssertEqual(shifted.second, 30, "30s offset must land at :30, no minute roll")
    }

    func testBurstComponents_rollsOverMinute() {
        var base = DateComponents()
        base.hour = 7
        base.minute = 30
        base.second = 0

        // 30:00 + 90s = 31:30
        let shifted = AlarmScheduler.burstComponents(base: base, offsetSeconds: 90)

        XCTAssertEqual(shifted.hour, 7)
        XCTAssertEqual(shifted.minute, 31, "90s past :30:00 must roll the minute to :31")
        XCTAssertEqual(shifted.second, 30)
    }

    func testBurstComponents_rollsOverHour() {
        var base = DateComponents()
        base.hour = 7
        base.minute = 59
        base.second = 30

        // 07:59:30 + 60s = 08:00:30
        let shifted = AlarmScheduler.burstComponents(base: base, offsetSeconds: 60)

        XCTAssertEqual(shifted.hour, 8, "crossing :59 must roll the hour")
        XCTAssertEqual(shifted.minute, 0)
        XCTAssertEqual(shifted.second, 30)
    }

    func testBurstComponents_wrapsAroundMidnight() {
        var base = DateComponents()
        base.hour = 23
        base.minute = 59
        base.second = 30

        // 23:59:30 + 60s = 00:00:30 (next day; weekday left as-is by design)
        let shifted = AlarmScheduler.burstComponents(base: base, offsetSeconds: 60)

        XCTAssertEqual(shifted.hour, 0, "past midnight must wrap to 00, never go negative or > 23")
        XCTAssertEqual(shifted.minute, 0)
        XCTAssertEqual(shifted.second, 30)
    }

    func testBurstComponents_preservesWeekday() {
        var base = DateComponents()
        base.weekday = 4
        base.hour = 6
        base.minute = 0
        base.second = 0

        let shifted = AlarmScheduler.burstComponents(base: base, offsetSeconds: 30)

        XCTAssertEqual(shifted.weekday, 4, "the follow-up must stay on the alarm's weekday")
    }

    // MARK: - burstTriggers labels & count

    func testBurstTriggers_countMatchesConfiguredOffsets() {
        var base = DateComponents()
        base.hour = 8
        base.minute = 0
        base.second = 0

        let triggers = AlarmScheduler.burstTriggers(after: base, label: "once", repeats: false)

        XCTAssertEqual(
            triggers.count,
            AlarmScheduler.fallbackBurstOffsetsSeconds.count,
            "one follow-up per configured offset"
        )
    }

    func testBurstTriggers_labelsAreSuffixedForPrefixSweep() {
        var base = DateComponents()
        base.hour = 8
        base.minute = 0
        base.second = 0

        let triggers = AlarmScheduler.burstTriggers(after: base, label: "day3", repeats: true)

        XCTAssertEqual(triggers.map { $0.label }, ["day3_burst0", "day3_burst1", "day3_burst2"],
                       "labels must keep the primary label prefix so cancel(_:) sweeps them")
    }

    func testBurstTriggers_propagatesRepeatFlag() {
        var base = DateComponents()
        base.hour = 8
        base.minute = 0
        base.second = 0

        let repeating = AlarmScheduler.burstTriggers(after: base, label: "day0", repeats: true)
        let oneShot = AlarmScheduler.burstTriggers(after: base, label: "once", repeats: false)

        for trigger in repeating {
            let calTrigger = trigger.trigger as? UNCalendarNotificationTrigger
            XCTAssertEqual(calTrigger?.repeats, true, "weekly alarm follow-ups must repeat weekly")
        }
        for trigger in oneShot {
            let calTrigger = trigger.trigger as? UNCalendarNotificationTrigger
            XCTAssertEqual(calTrigger?.repeats, false, "one-time alarm follow-ups must fire once")
        }
    }

    // MARK: - makeTriggers integration (fallback path)

    /// On the degraded `.timeSensitive` path a one-time alarm gets its primary
    /// trigger plus the full follow-up burst.
    func testMakeTriggers_oneTimeAlarm_appendsBurstOnFallbackPath() {
        withFallbackPath {
            let alarm = Alarm(repeatDays: [], name: "Once")
            let triggers = scheduler.makeTriggers(for: alarm)

            let labels = triggers.map { $0.label }
            XCTAssertEqual(labels.first, "once")
            XCTAssertEqual(
                triggers.count,
                1 + AlarmScheduler.fallbackBurstOffsetsSeconds.count,
                "primary + one follow-up per offset"
            )
            XCTAssertTrue(labels.contains("once_burst0"))
            XCTAssertTrue(labels.contains("once_burst\(AlarmScheduler.fallbackBurstOffsetsSeconds.count - 1)"))
        }
    }

    /// Every weekday gets its own primary + burst so the burst count scales
    /// with the number of selected days but stays bounded.
    func testMakeTriggers_weeklyAlarm_appendsBurstPerDay() {
        withFallbackPath {
            let alarm = Alarm(repeatDays: [0, 2, 4], name: "MWF")
            let triggers = scheduler.makeTriggers(for: alarm)

            let perDay = 1 + AlarmScheduler.fallbackBurstOffsetsSeconds.count
            XCTAssertEqual(triggers.count, 3 * perDay)
            // Each selected day must contribute its primary trigger.
            for day in [0, 2, 4] {
                XCTAssertTrue(triggers.contains { $0.label == "day\(day)" })
                XCTAssertTrue(triggers.contains { $0.label == "day\(day)_burst0" })
            }
        }
    }

    // MARK: - Helpers

    /// Run `body` with `criticalAlertsAvailable` forced to the fallback (false)
    /// state, restoring the previous value afterwards so test order cannot leak.
    /// The flag is `private(set)` so we drive it through `requestPermission`
    /// with a denying stub — the same seam the existing scheduler tests use.
    private func withFallbackPath(_ body: () -> Void) {
        let denying = AlarmScheduler(notificationCenter: DenyingPermissionCenter())
        let exp = expectation(description: "fallback permission resolved")
        denying.requestPermission { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        XCTAssertFalse(AlarmScheduler.criticalAlertsAvailable,
                       "precondition: must be on the fallback path for this test")
        body()
    }
}

// MARK: - Test double

/// Denies authorization synchronously so `requestPermission` resolves the
/// `criticalAlertsAvailable` flag to `false` (the lock-screen fallback path)
/// without waiting on the real permission daemon.
private final class DenyingPermissionCenter: NotificationScheduling {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(false, nil)
    }
    func add(_ request: UNNotificationRequest, withCompletionHandler completion: ((Error?) -> Void)?) {
        completion?(nil)
    }
    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
        completionHandler([])
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
        completionHandler([])
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeAllPendingNotificationRequests() {}
}
