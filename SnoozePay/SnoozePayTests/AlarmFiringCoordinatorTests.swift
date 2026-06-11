import XCTest
import UserNotifications
@testable import SnoozePay

/// Unit tests for AlarmFiringCoordinator — the snooze-from-notification flow
/// extracted out of AppDelegate. Exercises every `SnoozeOutcome` branch
/// against an isolated balance + repo so the real singletons stay untouched.
final class AlarmFiringCoordinatorTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var alarmRepo: AlarmRepository!
    private var balanceService: BalanceService!
    private var coordinator: AlarmFiringCoordinator!
    private var mockCenter: MockNotificationCenter!
    private var scheduler: AlarmScheduler!

    override func setUp() {
        super.setUp()
        suiteName = "test.coordinator.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        alarmRepo = AlarmRepository(defaults: testDefaults)
        balanceService = BalanceService(defaults: testDefaults)
        // Inject a stub UNUserNotificationCenter so the success path doesn't
        // pollute the real notification daemon and the failure path is
        // reproducible (revoked permission / 64-pending limit). Production
        // code keeps using `AlarmScheduler.shared`.
        mockCenter = MockNotificationCenter()
        scheduler = AlarmScheduler(notificationCenter: mockCenter)
        coordinator = AlarmFiringCoordinator(
            alarmRepository: alarmRepo,
            balanceService: balanceService,
            scheduler: scheduler
        )
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAlarm(penalty: Double = 50, progressive: Bool = false) -> Alarm {
        let alarm = Alarm(penaltyAmount: penalty, progressiveScale: progressive)
        alarmRepo.save(alarm)
        return alarm
    }

    /// Build a COMPLETE notification `userInfo` for the alarm. `AlarmNotificationPayload`
    /// requires penalty/progressive/snoozeMinutes/soundID in addition to alarmID +
    /// snoozeCount; hand-rolled two-key dicts now decode to nil → `.invalidPayload`.
    /// Routing through the real encoder keeps these tests in lock-step with the
    /// payload contract.
    private func userInfo(for alarm: Alarm, snoozeCount: Int) -> [String: Any] {
        AlarmNotificationPayload(alarm: alarm, snoozeCount: snoozeCount).asUserInfo()
    }

    /// Drive `handleSnooze` to a single resolution and return its outcome.
    /// Wraps the async completion in an expectation so tests stay imperative.
    private func resolveSnooze(
        userInfo: [AnyHashable: Any],
        timeout: TimeInterval = 5.0,
        file: StaticString = #file,
        line: UInt = #line
    ) -> AlarmFiringCoordinator.SnoozeOutcome? {
        let exp = expectation(description: "handleSnooze completion")
        var captured: AlarmFiringCoordinator.SnoozeOutcome?
        coordinator.handleSnooze(userInfo: userInfo) { outcome in
            captured = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        if captured == nil {
            XCTFail("handleSnooze never produced an outcome", file: file, line: line)
        }
        return captured
    }

    // MARK: - Invalid payload

    func testHandleSnooze_missingAlarmID_returnsInvalidPayload() {
        let outcome = resolveSnooze(userInfo: ["snoozeCount": 0])
        XCTAssertEqual(outcome, .invalidPayload)
    }

    func testHandleSnooze_invalidAlarmIDString_returnsInvalidPayload() {
        let outcome = resolveSnooze(userInfo: [
            "alarmID": "not-a-uuid",
            "snoozeCount": 0
        ])
        XCTAssertEqual(outcome, .invalidPayload)
    }

    func testHandleSnooze_missingSnoozeCount_returnsInvalidPayload() {
        let alarm = makeAlarm()
        let outcome = resolveSnooze(userInfo: [
            "alarmID": alarm.id.uuidString
        ])
        XCTAssertEqual(outcome, .invalidPayload)
    }

    // MARK: - Alarm not found

    func testHandleSnooze_unknownAlarmID_returnsAlarmNotFound() {
        // Valid UUID, but no alarm with that ID was saved.
        let outcome = resolveSnooze(userInfo: userInfo(for: Alarm(), snoozeCount: 0))
        XCTAssertEqual(outcome, .alarmNotFound)
    }

    // MARK: - Insufficient funds

    func testHandleSnooze_insufficientBalance_returnsInsufficientFunds() {
        let alarm = makeAlarm(penalty: 100)
        // Balance is 0 (fresh UserDefaults suite).
        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))
        XCTAssertEqual(outcome, .insufficientFunds)
        XCTAssertEqual(balanceService.balance, 0, "Balance must not be touched on a failed charge")
    }

    // MARK: - Success

    func testHandleSnooze_validRequest_chargesBalanceAndIncrementsCount() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        XCTAssertEqual(outcome, .scheduled(newSnoozeCount: 1, charged: 50))
        XCTAssertEqual(balanceService.balance, 150)
    }

    func testHandleSnooze_progressivePenalty_appliesToNewCount() {
        // snoozeCount=1 in payload + progressive scale → penalty(forSnoozeCount: 2) = 100
        let alarm = makeAlarm(penalty: 50, progressive: true)
        balanceService.topUp(amount: 500)

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 1))

        XCTAssertEqual(outcome, .scheduled(newSnoozeCount: 2, charged: 100))
        XCTAssertEqual(balanceService.balance, 400)
    }

    func testHandleSnooze_balanceExactlyEqualsPenalty_succeeds() {
        // Boundary: balance == penalty should be chargeable (>= comparison).
        let alarm = makeAlarm(penalty: 75)
        balanceService.topUp(amount: 75)

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        XCTAssertEqual(outcome, .scheduled(newSnoozeCount: 1, charged: 75))
        XCTAssertEqual(balanceService.balance, 0)
    }

    // MARK: - Issue #117: corrupted store must not collapse into alarmNotFound silently

    /// When the alarm store is corrupt, `handleSnooze` must still report
    /// `.alarmNotFound` (callers can't do anything else from a notification
    /// action), but the path must run through the throwing fetch so the
    /// decode error gets logged and the persistence lock arms — without
    /// this the snooze silently drops with no diagnostic trail (issue #117).
    func testHandleSnooze_corruptedAlarmStore_returnsAlarmNotFoundAndArmsLock() {
        // Save an alarm so `valid UUID + missing key` isn't the failure mode,
        // then corrupt the persistence store under the coordinator's feet.
        let alarm = makeAlarm()
        testDefaults.set(Data("not json".utf8), forKey: "stored_alarms")

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        XCTAssertEqual(outcome, .alarmNotFound,
                       "From a notification action there's no recovery UI, so collapse to alarmNotFound")
        XCTAssertTrue(alarmRepo.lastLoadFailed,
                      "The checked fetch must arm the persistence lock so a follow-up save can't clobber the corrupt blob")
    }

    // MARK: - Issue #130: scheduler failure must surface and refund the user

    /// Stub the notification center to reject `add(_:)` so the scheduler's
    /// `scheduleSnooze` resolves to `.failure(.system)`. The coordinator must:
    ///   1. Surface `.scheduleFailed(error:)` as the outcome
    ///   2. Refund the penalty (balance back to pre-charge amount)
    ///   3. Keep ledger consistent — both charge and refund recorded.
    /// Without this fix the user pays for a snooze that never re-fires
    /// (silent-failure-hunter critical finding on PR #127).
    func testHandleSnooze_schedulerRejectsAdd_refundsBalanceAndReportsScheduleFailed() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)
        let preCharge = balanceService.balance
        XCTAssertEqual(preCharge, 200)

        mockCenter.addError = NSError(
            domain: "UNErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Notifications are not allowed for this application"]
        )

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        guard case .scheduleFailed(let error) = outcome else {
            return XCTFail("Expected .scheduleFailed, got \(String(describing: outcome))")
        }
        guard case .system(let message) = error else {
            return XCTFail("Expected .system error, got \(error)")
        }
        XCTAssertEqual(message, "Notifications are not allowed for this application",
                       "Underlying UN error message must reach the outcome verbatim")
        XCTAssertEqual(balanceService.balance, preCharge,
                       "Penalty must be refunded so the user isn't billed for a snooze that won't fire")
    }

    /// 64-pending-limit pre-flight failure path. Same contract as the
    /// `.system` test above but with a different `SchedulingError` variant —
    /// the refund must happen regardless of which scheduling error class
    /// surfaces.
    func testHandleSnooze_schedulerHitsPendingLimit_refundsBalance() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)

        // Saturate the pending-request queue so the pre-flight rejects.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let content = UNMutableNotificationContent()
        mockCenter.pendingRequests = (0..<AlarmScheduler.pendingNotificationLimit).map { idx in
            UNNotificationRequest(identifier: "stub_\(idx)", content: content, trigger: trigger)
        }

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        guard case .scheduleFailed(let error) = outcome else {
            return XCTFail("Expected .scheduleFailed, got \(String(describing: outcome))")
        }
        guard case .pendingLimitReached = error else {
            return XCTFail("Expected .pendingLimitReached, got \(error)")
        }
        XCTAssertEqual(balanceService.balance, 200,
                       "Penalty must be refunded when the pending-limit pre-flight rejects")
        XCTAssertTrue(mockCenter.addedRequests.isEmpty,
                      "Pre-flight must short-circuit before any add() call, so no notification was registered")
    }
}

// MARK: - Test doubles

/// Lightweight stub for `NotificationScheduling`. Mirrors the one used in
/// `AlarmSchedulerErrorPropagationTests`; lifted here so the coordinator tests
/// can exercise success and failure paths without touching the real daemon.
private final class MockNotificationCenter: NotificationScheduling {
    var addError: Error?
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
