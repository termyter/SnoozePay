import os
import UserNotifications
import XCTest
@testable import SnoozePay

/// Logical routing only: the scoped sink does not read production unified logs.
final class AlarmSchedulerRearmDiagnosticTests: XCTestCase {
    private struct Line {
        let category: AppLogCategory
        let level: OSLogType
        let message: String
    }

    func testUnknownInventoryLogsOneErrorAndPreservesAllSchedules() {
        let backend = TestAlarmKitBackend(alertingAlarmIDs: nil)
        let center = RearmDiagnosticNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: backend)
        let alarms = [dailyAlarm(enabled: true), dailyAlarm(enabled: true), dailyAlarm(enabled: false)]
        var lines: [Line] = []
        var outcomes: [Int] = []

        AppLogger.withTestSink({ lines.append(Line(category: $0, level: $1, message: $2)) }, perform: {
            scheduler.rescheduleAll(alarms) { outcomes.append($0) }
        })

        XCTAssertEqual(outcomes, [2], "Unknown state must report each enabled alarm once without rearming")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.category, .scheduler)
        XCTAssertEqual(lines.first?.level, .error)
        XCTAssertEqual(lines.first?.message, "rescheduleAll skipped: current AlarmKit state unavailable")
        assertNoBackendActivity(backend, center: center)
    }

    @MainActor
    func testHealthyEmptyInventoryRearmsWithoutUnavailableDiagnostic() async {
        let backend = TestAlarmKitBackend(alertingAlarmIDs: [])
        let center = RearmDiagnosticNotificationCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: backend)
        let enabled = dailyAlarm(enabled: true)
        let disabled = dailyAlarm(enabled: false)
        let completed = expectation(description: "actual rearm completion")
        completed.assertForOverFulfill = true
        var outcomes: [Int] = []
        var lines: [Line] = []

        await AppLogger.withAsyncTestSink({
            lines.append(Line(category: $0, level: $1, message: $2))
        }, perform: {
            scheduler.rescheduleAll([enabled, disabled]) {
                outcomes.append($0)
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 5)
        })

        XCTAssertEqual(outcomes, [0])
        XCTAssertTrue(lines.isEmpty, "A known empty inventory is healthy, unlike an unreadable one")
        XCTAssertEqual(backend.cancelledOriginalIDs, [enabled.id])
        XCTAssertEqual(backend.scheduledIDs, [enabled.id])
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
        XCTAssertTrue(backend.snoozedIDs.isEmpty)
        XCTAssertTrue(backend.stoppedIDs.isEmpty)
        XCTAssertEqual(backend.authorizationRequests, 0)
        let legacyIDs = (0..<7).map { "alarm_\(enabled.id.uuidString)_day\($0)" }
            + ["alarm_\(enabled.id.uuidString)_once", "snooze_\(enabled.id.uuidString)"]
        XCTAssertEqual(center.inert.removedIdentifiers, legacyIDs)
        XCTAssertEqual(center.deliveredRemovals, [legacyIDs])
        XCTAssertTrue(center.inert.addedRequests.isEmpty)
        XCTAssertEqual(center.otherMutations, 0)
    }

    func testDisabledAndEmptyInputsCompleteWithoutDiagnosticOrBackendActivity() {
        let inputs: [[Alarm]] = [[dailyAlarm(enabled: false)], []]
        for alarms in inputs {
            let backend = TestAlarmKitBackend(alertingAlarmIDs: nil)
            let center = RearmDiagnosticNotificationCenter()
            let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: backend)
            var lines: [Line] = []
            var outcomes: [Int] = []

            AppLogger.withTestSink({ lines.append(Line(category: $0, level: $1, message: $2)) }, perform: {
                scheduler.rescheduleAll(alarms) { outcomes.append($0) }
            })

            XCTAssertEqual(outcomes, [0], "A deliberate no-op is neither a rearm failure nor an unknown-state error")
            XCTAssertTrue(lines.isEmpty)
            assertNoBackendActivity(backend, center: center)
        }
    }

    private func dailyAlarm(enabled: Bool) -> Alarm {
        Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6], enabled: enabled)
    }

    private func assertNoBackendActivity(
        _ backend: TestAlarmKitBackend, center: RearmDiagnosticNotificationCenter,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(backend.scheduledIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(backend.snoozedIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(backend.cancelledOriginalIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(backend.cancelledIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(backend.stoppedIDs.isEmpty, file: file, line: line)
        XCTAssertEqual(backend.authorizationRequests, 0, file: file, line: line)
        XCTAssertTrue(center.inert.addedRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(center.inert.removedIdentifiers.isEmpty, file: file, line: line)
        XCTAssertTrue(center.deliveredRemovals.isEmpty, file: file, line: line)
        XCTAssertEqual(center.otherMutations, 0, file: file, line: line)
    }
}

/// Reuses the inert center and records its otherwise invisible mutation APIs.
private final class RearmDiagnosticNotificationCenter: NotificationScheduling {
    let inert = InertNotificationCenter()
    private(set) var deliveredRemovals: [[String]] = []
    private(set) var otherMutations = 0

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: (@Sendable (Error?) -> Void)?
    ) {
        inert.add(request, withCompletionHandler: completion)
    }

    func getPendingNotificationRequests(
        completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void
    ) {
        inert.getPendingNotificationRequests(completionHandler: completionHandler)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        inert.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        deliveredRemovals.append(identifiers)
        inert.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void) {
        inert.getDeliveredNotifications(completionHandler: completionHandler)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        otherMutations += 1
        inert.setNotificationCategories(categories)
    }

    func removeAllPendingNotificationRequests() {
        otherMutations += 1
        inert.removeAllPendingNotificationRequests()
    }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        otherMutations += 1
        inert.requestAuthorization(options: options, completionHandler: completionHandler)
    }
}
