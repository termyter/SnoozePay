import XCTest
import UserNotifications
@testable import SnoozePay

/// #19 QA regression coverage for the lock-screen fallback burst:
/// 1. `scheduleSnooze` must emit burst identifiers of the form
///    `snooze_<id>_burstN` — the exact set `cancel(_:)` /
///    `cancelFallbackBursts(_:)` remove. A prior bug routed the label through
///    `burstTriggers` and produced `snooze_<id>_burst_burst0`, which the
///    belt-and-suspenders explicit-ID removal missed → orphan re-ring.
/// 2. `cancelFallbackBursts(_:)` must remove ONLY the `_burstN` follow-ups,
///    leaving the primary `day*/once/snooze` triggers armed so a repeating
///    alarm still fires on its next day.
final class AlarmSchedulerBurstCancellationTests: XCTestCase {

    private func makeAlarm() -> Alarm {
        Alarm(time: Date(), repeatDays: [], name: "Test", penaltyAmount: 50)
    }

    /// Force `criticalAlertsAvailable == false` (the fallback path) by resolving
    /// `requestPermission` through a denying center, matching the seam the other
    /// scheduler tests use.
    private func forceFallbackPath() {
        let denying = AlarmScheduler(notificationCenter: BurstTestCenter())
        let exp = expectation(description: "fallback permission resolved")
        denying.requestPermission { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        XCTAssertFalse(AlarmScheduler.criticalAlertsAvailable,
                       "precondition: must be on the fallback path")
    }

    func testScheduleSnooze_fallback_emitsCancellableBurstIDs() {
        forceFallbackPath()
        let center = BurstTestCenter()
        let scheduler = AlarmScheduler(notificationCenter: center)
        let alarm = makeAlarm()
        let snoozeID = scheduler.snoozeNotificationID(for: alarm.id)

        let exp = expectation(description: "snooze scheduled")
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)

        let ids = Set(center.addedRequests.map { $0.identifier })
        XCTAssertTrue(ids.contains(snoozeID), "primary snooze request must be scheduled")
        for index in 0..<3 {
            XCTAssertTrue(ids.contains("\(snoozeID)_burst\(index)"),
                          "burst \(index) must use the cancellable `snooze_<id>_burst\(index)` id")
        }
        XCTAssertFalse(ids.contains { $0.contains("_burst_burst") },
                       "no double-suffixed `burst_burst` ids — those evade explicit cancellation")
    }

    func testCancelFallbackBursts_removesOnlyBursts_keepsPrimary() {
        let alarmID = UUID()
        let prefix = "alarm_\(alarmID.uuidString)_"
        let snoozeID = "snooze_\(alarmID.uuidString)"

        // Seed a realistic pending set: weekly primary + its bursts, plus the
        // snooze primary + its bursts.
        let primaryIDs = ["\(prefix)day0", "\(prefix)once", snoozeID]
        let burstIDs = [
            "\(prefix)day0_burst0", "\(prefix)day0_burst1", "\(prefix)day0_burst2",
            "\(prefix)once_burst0",
            "\(snoozeID)_burst0", "\(snoozeID)_burst1", "\(snoozeID)_burst2"
        ]
        let center = BurstTestCenter()
        center.pending = (primaryIDs + burstIDs).map {
            UNNotificationRequest(identifier: $0, content: UNMutableNotificationContent(), trigger: nil)
        }
        let scoped = AlarmScheduler(notificationCenter: center)

        scoped.cancelFallbackBursts(alarmID)

        // Both the sync explicit-ID removal and the async prefix sweep run; give
        // the async completion a beat to drain.
        let drained = expectation(description: "removal drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        for id in burstIDs {
            XCTAssertTrue(center.removedIdentifiers.contains(id), "burst id \(id) must be removed")
        }
        for id in primaryIDs {
            XCTAssertFalse(center.removedIdentifiers.contains(id),
                           "primary id \(id) must survive — burst-only cancel keeps repeating alarms armed")
        }
    }
}

// MARK: - Test double

/// Records added requests + removed identifiers and answers the pending query
/// from a mutable backlog so `cancelFallbackBursts`'s sync + async passes can be
/// asserted. Grants nothing (denies authorization → fallback path).
private final class BurstTestCenter: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []
    var pending: [UNNotificationRequest] = []

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(false, nil)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completion: ((Error?) -> Void)?) {
        addedRequests.append(request)
        completion?(nil)
    }

    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
        completionHandler(pending)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        let drop = Set(identifiers)
        pending.removeAll { drop.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
        completionHandler([])
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}

    func removeAllPendingNotificationRequests() {
        pending.removeAll()
    }
}
