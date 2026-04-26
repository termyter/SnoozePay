import XCTest
import UserNotifications
@testable import SnoozePay

/// Issue #118 — `AlarmScheduler.schedule` must surface `UNUserNotificationCenter.add`
/// errors and the iOS 64-pending-limit cap to UI callers instead of swallowing them
/// to `AppLogger.scheduler.error`. Without these tests the original silent-failure
/// regression (a "Будильник создан" toast on a notification that never registered)
/// can sneak back in undetected.
final class AlarmSchedulerErrorPropagationTests: XCTestCase {

    // MARK: - Mock notification center

    private final class MockNotificationCenter: NotificationScheduling {
        /// Pre-canned `add(_:)` failure. When non-nil every `add` call invokes its
        /// completion with this error; otherwise the call is treated as a successful
        /// schedule.
        var addError: Error?
        /// Pending requests reported by `getPendingNotificationRequests` — used by the
        /// 64-limit pre-flight check.
        var pendingRequests: [UNNotificationRequest] = []

        private(set) var addedRequests: [UNNotificationRequest] = []

        func add(
            _ request: UNNotificationRequest,
            withCompletionHandler completion: ((Error?) -> Void)?
        ) {
            addedRequests.append(request)
            completion?(addError)
        }

        func getPendingNotificationRequests(
            completionHandler: @escaping ([UNNotificationRequest]) -> Void
        ) {
            completionHandler(pendingRequests)
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

    // MARK: - schedule(_:completion:) error path

    func testSchedule_propagatesUNAddErrorToCompletion() {
        let mock = MockNotificationCenter()
        let underlyingMessage = "Notifications are not allowed for this application"
        mock.addError = NSError(
            domain: "UNErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: underlyingMessage]
        )
        let scheduler = AlarmScheduler(notificationCenter: mock)
        let alarm = Alarm(penaltyAmount: 50, enabled: true)

        let exp = expectation(description: "schedule completion called")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(alarm) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        guard case .failure(let error) = captured else {
            return XCTFail("Expected failure, got \(String(describing: captured))")
        }
        guard case .system(let message) = error else {
            return XCTFail("Expected .system, got \(error)")
        }
        XCTAssertEqual(message, underlyingMessage,
                       "UN error description must reach the VM verbatim")
        XCTAssertNotNil(error.errorDescription,
                        "SchedulingError must localize for UI alerts")
        XCTAssertTrue(
            error.errorDescription?.contains(underlyingMessage) ?? false,
            "Error description must include underlying reason for the user"
        )
    }

    func testSchedule_successPath_completesWithSuccess() {
        let mock = MockNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: mock)
        let alarm = Alarm(penaltyAmount: 50, enabled: true)

        let exp = expectation(description: "schedule completion called")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(alarm) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        guard case .success = captured else {
            return XCTFail("Expected success, got \(String(describing: captured))")
        }
        XCTAssertFalse(mock.addedRequests.isEmpty,
                       "Successful schedule must actually add a request")
    }

    func testSchedule_disabledAlarm_skipsAddAndReportsSuccess() {
        let mock = MockNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: mock)
        let alarm = Alarm(penaltyAmount: 50, enabled: false)

        let exp = expectation(description: "schedule completion called")
        scheduler.schedule(alarm) { result in
            if case .success = result { exp.fulfill() }
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(mock.addedRequests.isEmpty,
                      "Disabled alarms must not register notifications")
    }

    // MARK: - 64-pending-limit pre-flight

    func testSchedule_blocksWhenPendingLimitWouldExceed() {
        let mock = MockNotificationCenter()
        // Simulate a near-full pending queue. iOS hard cap is 64; we leave 0
        // slots free so any new schedule trips the pre-flight.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let content = UNMutableNotificationContent()
        mock.pendingRequests = (0..<AlarmScheduler.pendingNotificationLimit).map { idx in
            UNNotificationRequest(identifier: "stub_\(idx)", content: content, trigger: trigger)
        }
        let scheduler = AlarmScheduler(notificationCenter: mock)
        let alarm = Alarm(penaltyAmount: 50, enabled: true)

        let exp = expectation(description: "schedule completion called")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.schedule(alarm) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        guard case .failure(let error) = captured else {
            return XCTFail("Expected failure, got \(String(describing: captured))")
        }
        guard case .pendingLimitReached(let count) = error else {
            return XCTFail("Expected pendingLimitReached, got \(error)")
        }
        XCTAssertEqual(count, AlarmScheduler.pendingNotificationLimit)
        XCTAssertTrue(mock.addedRequests.isEmpty,
                      "Pre-flight must short-circuit before any add() call")
        XCTAssertTrue(
            error.errorDescription?.contains("лимит") ?? false,
            "Error description must mention the iOS limit so users understand the cause"
        )
    }

    // MARK: - scheduleSnooze error path

    func testScheduleSnooze_propagatesUNErrorToCompletion() {
        let mock = MockNotificationCenter()
        mock.addError = NSError(
            domain: "UNErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Too many notifications"]
        )
        let scheduler = AlarmScheduler(notificationCenter: mock)
        let alarm = Alarm(penaltyAmount: 50, enabled: true)

        let exp = expectation(description: "scheduleSnooze completion called")
        var captured: Result<Void, AlarmScheduler.SchedulingError>?
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        guard case .failure = captured else {
            return XCTFail("Expected failure, got \(String(describing: captured))")
        }
    }
}
