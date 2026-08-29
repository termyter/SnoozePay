import Foundation
import UserNotifications
@testable import SnoozePay

/// Shared `AlarmKitScheduling` double.
///
/// Since #472 AlarmKit is the ONLY backend, so "a scheduler that succeeds" can
/// no longer be expressed with a permissive `UNUserNotificationCenter` stub —
/// every suite that used to get a working `AlarmScheduler` for free now has to
/// hand it an authorized AlarmKit backend. Sharing one double keeps that from
/// being re-implemented in six files.
///
/// Defaults to authorized-and-succeeding: the common case is "the backend works,
/// I'm testing something else".
final class TestAlarmKitBackend: AlarmKitScheduling {

    struct ScheduleRejected: LocalizedError {
        var errorDescription: String? { "AlarmKit rejected the schedule" }
    }

    var authorization: AlarmKitAuthorization
    /// When true, `schedule` reports `.failure` — models an async AlarmKit
    /// reject (alarm limit, revoked auth, backend reject).
    var failSchedule: Bool
    /// When true, `scheduleSnooze` reports `.failure`.
    var failSnooze: Bool

    private(set) var scheduledIDs: [UUID] = []
    private(set) var snoozedIDs: [UUID] = []
    private(set) var snoozeFireDates: [Date] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    private(set) var authorizationRequests = 0

    init(
        authorization: AlarmKitAuthorization = .authorized,
        failSchedule: Bool = false,
        failSnooze: Bool = false
    ) {
        self.authorization = authorization
        self.failSchedule = failSchedule
        self.failSnooze = failSnooze
    }

    var isAuthorized: Bool { authorization == .authorized }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequests += 1
        completion(isAuthorized)
    }

    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
        scheduledIDs.append(alarm.id)
        completion(failSchedule ? .failure(ScheduleRejected()) : .success(()))
    }

    func scheduleSnooze(
        _ alarm: Alarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        snoozedIDs.append(alarm.id)
        snoozeFireDates.append(fireDate)
        completion(failSnooze ? .failure(ScheduleRejected()) : .success(()))
    }

    func cancel(_ alarmID: UUID) { cancelledIDs.append(alarmID) }

    func stop(_ alarmID: UUID) { stoppedIDs.append(alarmID) }
}

/// Inert `NotificationScheduling` double.
///
/// `AlarmScheduler` still holds a notification-center seam after #472, but only
/// to sweep away alarm notifications a pre-#472 build left pending — it never
/// schedules one. Tests that care about scheduling therefore want a center that
/// simply answers every query empty and records nothing, so an unexpected `add`
/// is visible instead of silently swallowed.
final class InertNotificationCenter: NotificationScheduling {

    /// Any request that reached `add(_:)`. Must stay empty: nothing in the app
    /// schedules a notification any more.
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

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
