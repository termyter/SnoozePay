import XCTest
import UserNotifications
@testable import SnoozePay

/// Issue #427 — saved alarms were never re-armed after a timezone / DST shift,
/// a reboot, or an AlarmKit / notification authorization change, so they could
/// fire at the wrong wall-clock time or stop firing entirely. `rescheduleAll`
/// is the re-arm primitive AppDelegate calls from the relevant system signals.
/// It must `cancel` + `schedule` every **enabled** alarm and leave **disabled**
/// ones untouched (they hold no triggers to re-arm).
final class AlarmSchedulerRescheduleAllTests: XCTestCase {

    /// The schedule path hops through `DispatchQueue.main.async` (the 64-pending
    /// pre-flight) before reaching `add`. Enqueueing a fulfilment block on main
    /// after `rescheduleAll` lets those queued schedule turns run first (FIFO),
    /// so `add` has landed by the time assertions run.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    private func dailyAlarm(name: String, enabled: Bool) -> Alarm {
        // A 7-day repeat guarantees a trigger regardless of the current time, so
        // the schedule path actually reaches `add` for enabled alarms.
        Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6], name: name, enabled: enabled)
    }

    func testRescheduleAll_reschedulesEnabled_skipsDisabled() {
        let center = RecordingNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center)

        let on = dailyAlarm(name: "On", enabled: true)
        let off = dailyAlarm(name: "Off", enabled: false)

        scheduler.rescheduleAll([on, off])
        drainMainQueue()

        // Enabled alarm was re-armed: at least one notification request added,
        // every added identifier belongs to it.
        XCTAssertFalse(center.addedIdentifiers.isEmpty,
                       "Enabled alarm must be rescheduled (add called)")
        XCTAssertTrue(
            center.addedIdentifiers.allSatisfy { $0.contains(on.id.uuidString) },
            "Every added request must belong to the enabled alarm"
        )

        // Disabled alarm was skipped entirely — its id appears in neither the
        // adds nor the cancel removals.
        XCTAssertFalse(
            center.addedIdentifiers.contains { $0.contains(off.id.uuidString) },
            "Disabled alarm must not be scheduled"
        )
        XCTAssertFalse(
            center.removedIdentifiers.contains { $0.contains(off.id.uuidString) },
            "Disabled alarm must not be cancelled (nothing to re-arm)"
        )

        // Enabled alarm was cancelled before being re-scheduled (cancel removes
        // its explicit pending identifiers synchronously).
        XCTAssertTrue(
            center.removedIdentifiers.contains { $0.contains(on.id.uuidString) },
            "Enabled alarm must be cancelled before reschedule"
        )
    }

    func testRescheduleAll_allDisabled_doesNothing() {
        let center = RecordingNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center)

        scheduler.rescheduleAll([
            dailyAlarm(name: "A", enabled: false),
            dailyAlarm(name: "B", enabled: false)
        ])

        XCTAssertTrue(center.addedIdentifiers.isEmpty,
                      "No enabled alarms — nothing should be scheduled")
    }

    func testRescheduleAll_emptyList_doesNothing() {
        let center = RecordingNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center)

        scheduler.rescheduleAll([])

        XCTAssertTrue(center.addedIdentifiers.isEmpty)
        XCTAssertTrue(center.removedIdentifiers.isEmpty)
    }
}

// MARK: - Test double

/// `NotificationScheduling` stub that answers the 64-pending pre-flight
/// immediately (so `schedule` reaches `add` synchronously) and records every
/// added / removed identifier for assertions.
private final class RecordingNotificationCenter: NotificationScheduling {
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedIdentifiers: [String] = []

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        addedIdentifiers.append(request.identifier)
        completion?(nil)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        completionHandler([])
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func getDeliveredNotifications(
        completionHandler: @escaping ([UNNotification]) -> Void
    ) {
        completionHandler([])
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeAllPendingNotificationRequests() {}
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(false, nil)
    }
}
