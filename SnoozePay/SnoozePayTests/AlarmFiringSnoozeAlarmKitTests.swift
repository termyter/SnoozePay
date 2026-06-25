import XCTest
import UserNotifications
@testable import SnoozePay

/// #383 — the in-app snooze on the AlarmKit (Strategy A, iOS 26+) path must:
///   • charge the penalty exactly once,
///   • reschedule the snooze through AlarmKit (a real system alarm) and NOT as
///     a notification (Strategy B),
///   • surface `usesAlarmKit == true` so the firing screen dismisses (rather
///     than running the in-place notification-snooze countdown) and skips its
///     own `AudioService` (the system owns the sound).
///
/// The screen-level stop/dismiss/audio behaviour lives in the VC; here we pin
/// the model + scheduler seam that drives it, since those are the testable
/// non-UI surfaces. Routes through the injectable `AlarmKitScheduling` /
/// `NotificationScheduling` seams so the iOS-26 path is exercisable from the
/// branching logic on any host (the AlarmKit branch itself is iOS-26 gated).
final class AlarmFiringSnoozeAlarmKitTests: XCTestCase {

    private func makeAlarm(penalty: Double = 50) -> Alarm {
        Alarm(snoozeMinutes: 9, penaltyAmount: penalty)
    }

    // MARK: - usesAlarmKit plumbing

    func testUsesAlarmKit_authorizedBackend_isTrue() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit branch is iOS 26+") }
        let scheduler = AlarmScheduler(
            notificationCenter: SnoozeRecordingCenter(),
            alarmKit: SnoozeMockAlarmKit(authorized: true)
        )
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(),
            balanceService: SnoozeStubBalance(balanceValue: 500),
            scheduler: scheduler
        )
        XCTAssertTrue(vm.usesAlarmKit, "Authorized AlarmKit backend must surface usesAlarmKit == true")
    }

    func testUsesAlarmKit_noBackend_isFalse() {
        let scheduler = AlarmScheduler(notificationCenter: SnoozeRecordingCenter(), alarmKit: nil)
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(),
            balanceService: SnoozeStubBalance(balanceValue: 500),
            scheduler: scheduler
        )
        XCTAssertFalse(vm.usesAlarmKit, "Without an AlarmKit backend the path stays Strategy B")
    }

    // MARK: - Snooze on the AlarmKit path

    /// A successful AlarmKit snooze charges once and reschedules via AlarmKit
    /// (stop-then-reschedule), never a notification.
    func testSnooze_alarmKitPath_chargesOnceAndReschedulesViaAlarmKit() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit branch is iOS 26+") }
        let alarmKit = SnoozeMockAlarmKit(authorized: true)
        let center = SnoozeRecordingCenter()
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: alarmKit)
        let billing = SnoozeStubBalance(balanceValue: 500)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, balanceService: billing, scheduler: scheduler)

        let exp = expectation(description: "snooze outcome")
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        let charged = vm.snooze { outcome = $0; exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(charged, "Snooze charges when the balance covers the penalty")
        XCTAssertEqual(billing.chargeCalls, [50], "The penalty must be charged exactly once")
        XCTAssertTrue(billing.topUpCalls.isEmpty, "No refund on a successful AlarmKit snooze")
        XCTAssertEqual(outcome, .scheduled)
        XCTAssertEqual(alarmKit.snoozedIDs, [alarm.id], "Snooze must reschedule via AlarmKit")
        XCTAssertEqual(alarmKit.stoppedIDs, [alarm.id], "The ringing alarm must be stopped on snooze")
        XCTAssertTrue(center.addedRequests.isEmpty, "AlarmKit snooze must not register a notification")
        XCTAssertEqual(vm.snoozeCount, 1)
    }

    /// At zero balance the AlarmKit snooze takes no money and does not snooze —
    /// the #381 top-up guard is unchanged on this path (no charge, no negative).
    func testSnooze_alarmKitPath_zeroBalance_takesNoMoney() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit branch is iOS 26+") }
        let alarmKit = SnoozeMockAlarmKit(authorized: true)
        let scheduler = AlarmScheduler(notificationCenter: SnoozeRecordingCenter(), alarmKit: alarmKit)
        let billing = SnoozeStubBalance(balanceValue: 0)
        let vm = AlarmFiringViewModel(alarm: makeAlarm(penalty: 50), balanceService: billing, scheduler: scheduler)

        let result = vm.snooze()

        XCTAssertFalse(result, "A paid snooze at 0 ₽ must not proceed")
        XCTAssertTrue(billing.chargeCalls.isEmpty, "Nothing is charged when the balance can't cover it")
        XCTAssertTrue(alarmKit.snoozedIDs.isEmpty, "No reschedule when the snooze is refused")
        XCTAssertEqual(vm.snoozeCount, 0)
    }
}

// MARK: - Test doubles

private final class SnoozeMockAlarmKit: AlarmKitScheduling {
    private let authorized: Bool
    private(set) var scheduledIDs: [UUID] = []
    private(set) var snoozedIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    private(set) var cancelledIDs: [UUID] = []

    init(authorized: Bool) { self.authorized = authorized }

    var isAuthorized: Bool { authorized }
    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(authorized) }
    func schedule(_ alarm: Alarm) throws { scheduledIDs.append(alarm.id) }
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date) throws { snoozedIDs.append(alarm.id) }
    func cancel(_ alarmID: UUID) { cancelledIDs.append(alarmID) }
    func stop(_ alarmID: UUID) { stoppedIDs.append(alarmID) }
}

private final class SnoozeStubBalance: AlarmFiringBalancing {
    private(set) var balance: Double
    private(set) var chargeCalls: [Double] = []
    private(set) var topUpCalls: [Double] = []

    init(balanceValue: Double) { self.balance = balanceValue }

    func canAfford(_ amount: Double) -> Bool { balance >= amount }

    @discardableResult
    func charge(amount: Double, alarmID: UUID?) -> Bool {
        chargeCalls.append(amount)
        guard balance >= amount else { return false }
        balance -= amount
        return true
    }

    @discardableResult
    func topUp(amount: Double, refundsTransactionID: UUID?) -> Bool {
        topUpCalls.append(amount)
        balance += amount
        return true
    }
}

private final class SnoozeRecordingCenter: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []

    func add(_ request: UNNotificationRequest, withCompletionHandler completion: ((Error?) -> Void)?) {
        addedRequests.append(request)
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
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(true, nil)
    }
}
