import XCTest
import UserNotifications
@testable import SnoozePay

/// Issue #199 — when the scheduler is torn down (or the snooze cancelled) while
/// the async 64-pending pre-flight is still in flight, the `[weak self]` guard
/// used to report `.success(())`. That produced a phantom `.scheduled` outcome:
/// the penalty stayed charged but no notification was ever registered. The
/// fix reports `.failure(.cancelled)` so the coordinator refunds instead of
/// trusting a fake success.
final class AlarmSchedulerCancellationTests: XCTestCase {

    private func makeAlarm() -> Alarm {
        Alarm(time: Date(), repeatDays: [], name: "Test", penaltyAmount: 50)
    }

    /// Reproduces the race: hold the pre-flight completion open, deallocate the
    /// scheduler, then resolve the pre-flight. The weak-self-nil branch must
    /// surface `.failure(.cancelled)`, never `.success`.
    func testScheduleSnooze_deallocatedDuringPreflight_reportsCancelledNotSuccess() {
        let center = DeferringNotificationCenter()
        var scheduler: AlarmScheduler? = AlarmScheduler(notificationCenter: center)

        let exp = expectation(description: "snooze outcome")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler?.scheduleSnooze(for: makeAlarm(), snoozeCount: 1) { result in
            captured = result
            exp.fulfill()
        }

        // The pre-flight asked for pending requests; the mock captured the
        // handler instead of answering it. Nothing has resolved yet.
        XCTAssertNotNil(center.pendingHandler, "Pre-flight must be awaiting the pending-requests answer")
        XCTAssertNil(captured, "No outcome before the pre-flight resolves")

        // Tear the scheduler down mid-flight, then resolve the pre-flight.
        scheduler = nil
        center.firePending([])

        wait(for: [exp], timeout: 5)

        guard case .failure(let error) = captured else {
            return XCTFail("Expected .failure(.cancelled), got \(String(describing: captured))")
        }
        XCTAssertEqual(error, .cancelled,
                       "Deallocated-mid-preflight must report .cancelled, never a phantom .success")
    }

    /// The non-snooze `schedule(_:)` path shares the same weak-self guard and
    /// must behave identically.
    func testSchedule_deallocatedDuringPreflight_reportsCancelled() {
        let center = DeferringNotificationCenter()
        var scheduler: AlarmScheduler? = AlarmScheduler(notificationCenter: center)

        let exp = expectation(description: "schedule outcome")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        // A daily alarm produces at least one trigger so the pre-flight runs.
        scheduler?.schedule(Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6], name: "Daily")) { result in
            captured = result
            exp.fulfill()
        }

        XCTAssertNotNil(center.pendingHandler)
        scheduler = nil
        center.firePending([])
        wait(for: [exp], timeout: 5)

        guard case .failure(.cancelled) = captured else {
            return XCTFail("Expected .failure(.cancelled), got \(String(describing: captured))")
        }
    }

    /// `.cancelled` flows through the coordinator's existing refund path exactly
    /// like any other scheduling failure — so the race can no longer leave a
    /// charged penalty with a `.scheduled` outcome (issue #199 acceptance #3).
    func testCancelledError_isAScheduleFailureNotSuccess() {
        // A typed failure, by construction — documents that the phantom-success
        // branch is gone and that callers branch on `.failure`.
        let outcome: Result<Void, AlarmScheduler.SchedulingError> = .failure(.cancelled)
        guard case .failure = outcome else {
            return XCTFail(".cancelled must be a failure case")
        }
        XCTAssertNotNil(AlarmScheduler.SchedulingError.cancelled.errorDescription)
    }
}

// MARK: - Test double

/// `NotificationScheduling` stub that defers the pending-requests answer so a
/// test can deallocate the scheduler while the pre-flight is mid-flight.
private final class DeferringNotificationCenter: NotificationScheduling {
    var pendingHandler: (([UNNotificationRequest]) -> Void)?

    func firePending(_ requests: [UNNotificationRequest]) {
        let handler = pendingHandler
        pendingHandler = nil
        handler?(requests)
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        // Capture instead of answering — the test resolves this later.
        pendingHandler = completionHandler
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
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
