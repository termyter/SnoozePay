import XCTest
import UserNotifications
import AlarmKit
@testable import SnoozePay

// `import AlarmKit` brings `AlarmKit.Alarm` into scope, which collides with the
// app's `SnoozePay.Alarm` model. We need both: the AlarmKit `Schedule` /
// `Recurrence` enums for pattern-matching the mapping output, and the app model
// to build test fixtures. `AppAlarm` disambiguates the app model so every
// fixture / mock signature is unambiguous.
private typealias AppAlarm = SnoozePay.Alarm

/// Unit tests for the AlarmKit (Strategy A) integration in `AlarmScheduler`
/// (#377). Covers the iOS-26-vs-notification-fallback branching through the
/// injectable `AlarmKitScheduling` seam, plus the `Alarm` → AlarmKit config
/// mapping. The branching tests run on any host because they exercise the
/// `AlarmScheduling` API; the config-mapping tests are gated to iOS 26.
final class AlarmKitSchedulerTests: XCTestCase {

    // MARK: - Branching: schedule routes to the right backend

    /// When AlarmKit is authorized (Strategy A), `schedule` must hand the alarm
    /// to the AlarmKit backend and NOT register any notification request.
    func testSchedule_authorizedAlarmKit_routesToAlarmKitNotNotifications() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50)) { result in
            if case .failure = result { XCTFail("expected success on AlarmKit path") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(alarmKit.scheduledIDs.count, 1,
                       "Authorized AlarmKit must receive the schedule call")
        XCTAssertTrue(center.addedRequests.isEmpty,
                      "Strategy A must not also register a notification (Strategy B)")
    }

    /// When AlarmKit is present but NOT authorized, `schedule` must fall back to
    /// the notification path so the user is never left without an alarm.
    func testSchedule_unauthorizedAlarmKit_fallsBackToNotifications() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: false)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50)) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(alarmKit.scheduledIDs.isEmpty,
                      "Unauthorized AlarmKit must not be used")
        XCTAssertFalse(center.addedRequests.isEmpty,
                       "Fallback must register at least one notification (Strategy B)")
    }

    /// With no AlarmKit backend wired (the pre-#377 / iOS < 26 shape), behaviour
    /// is unchanged: the alarm is scheduled via notifications.
    func testSchedule_noAlarmKitBackend_usesNotificationFallback() {
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: nil)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50)) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertFalse(center.addedRequests.isEmpty,
                       "Without AlarmKit the notification fallback must still schedule")
    }

    /// A disabled alarm short-circuits on every backend — no AlarmKit schedule,
    /// no notification add.
    func testSchedule_disabledAlarm_isNoOpOnBothBackends() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let center = RecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)

        let exp = expectation(description: "schedule completes")
        scheduler.schedule(AppAlarm(penaltyAmount: 50, enabled: false)) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(alarmKit.scheduledIDs.isEmpty)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    // MARK: - Cancel + stop forward to AlarmKit

    func testCancel_forwardsToAlarmKitBackend() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)
        let id = UUID()

        scheduler.cancel(id)

        XCTAssertEqual(alarmKit.cancelledIDs, [id],
                       "cancel(_:) must also cancel the AlarmKit system alarm")
    }

    func testStopSystemAlarm_forwardsToAlarmKitBackend() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)
        let id = UUID()

        scheduler.stopSystemAlarm(id)

        XCTAssertEqual(alarmKit.stoppedIDs, [id])
    }

    func testStopSystemAlarm_noBackend_isNoOp() {
        // No crash when no AlarmKit backend exists (iOS < 26 / fallback shape).
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: nil)
        scheduler.stopSystemAlarm(UUID())
    }

    // MARK: - Authorization request

    func testRequestAlarmKitAuthorization_forwardsGrant() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit branch only runs on iOS 26+")
        }
        let alarmKit = MockAlarmKitScheduler(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: alarmKit)

        let exp = expectation(description: "authorization resolves")
        scheduler.requestAlarmKitAuthorization { granted in
            XCTAssertTrue(granted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(alarmKit.authorizationRequests, 1)
    }

    func testRequestAlarmKitAuthorization_noBackend_completesFalse() {
        let scheduler = AlarmScheduler(notificationCenter: RecordingCenter(), alarmKit: nil)
        let exp = expectation(description: "completes")
        scheduler.requestAlarmKitAuthorization { granted in
            XCTAssertFalse(granted, "No backend → cannot be authorized")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Config mapping (iOS 26 only)

    func testMakeSchedule_weeklyAlarm_mapsRepeatDaysToWeekdays() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        // Monday (0) + Sunday (6) selected, weekly mode.
        let alarm = AppAlarm(repeatDays: [0, 6], penaltyAmount: 50, repeatMode: .weekly)
        let schedule = AlarmKitScheduler.makeSchedule(for: alarm)

        guard case let .relative(relative) = schedule,
              case let .weekly(days) = relative.repeats else {
            return XCTFail("Weekly alarm must map to a relative weekly schedule")
        }
        XCTAssertTrue(days.contains(.monday))
        XCTAssertTrue(days.contains(.sunday))
        XCTAssertEqual(days.count, 2)
    }

    func testMakeSchedule_oneShotAlarm_usesNeverRecurrence() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let alarm = AppAlarm(repeatDays: [], penaltyAmount: 50)
        let schedule = AlarmKitScheduler.makeSchedule(for: alarm)

        guard case let .relative(relative) = schedule,
              case .never = relative.repeats else {
            return XCTFail("One-shot alarm must use .never recurrence")
        }
    }

    func testWeekdayMapping_coversAllSevenIndices() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("AlarmKit types require iOS 26+")
        }
        let expected: [Int: Locale.Weekday] = [
            0: .monday, 1: .tuesday, 2: .wednesday, 3: .thursday,
            4: .friday, 5: .saturday, 6: .sunday
        ]
        for (index, weekday) in expected {
            XCTAssertEqual(AlarmKitScheduler.weekday(forMondayFirstIndex: index), weekday)
        }
        XCTAssertNil(AlarmKitScheduler.weekday(forMondayFirstIndex: 7),
                     "Out-of-range index is dropped, not crashed")
    }
}

// MARK: - Test doubles

/// Records the calls `AlarmScheduler` makes against its AlarmKit seam so the
/// Strategy-A-vs-fallback branching can be asserted on any host OS. Mirrors the
/// `PermissionStubCenter` pattern from `AlarmSchedulerTests`.
private final class MockAlarmKitScheduler: AlarmKitScheduling {
    private let authorized: Bool
    private(set) var scheduledIDs: [UUID] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    private(set) var authorizationRequests = 0

    init(authorized: Bool) { self.authorized = authorized }

    var isAuthorized: Bool { authorized }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequests += 1
        completion(authorized)
    }

    func schedule(_ alarm: AppAlarm) throws {
        scheduledIDs.append(alarm.id)
    }

    func cancel(_ alarmID: UUID) {
        cancelledIDs.append(alarmID)
    }

    func stop(_ alarmID: UUID) {
        stoppedIDs.append(alarmID)
    }
}

/// `NotificationScheduling` double that records every `add` so the fallback
/// path can be observed. Completes async members with empty results so the
/// pre-flight 64-pending check resolves deterministically.
private final class RecordingCenter: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        addedRequests.append(request)
        completion?(nil)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        completionHandler([])
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
        completionHandler(true, nil)
    }
}
