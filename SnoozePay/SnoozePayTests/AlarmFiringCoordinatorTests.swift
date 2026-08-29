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
    private var alarmKit: TestAlarmKitBackend!
    private var scheduler: AlarmScheduler!

    override func setUp() {
        super.setUp()
        suiteName = "test.coordinator.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        alarmRepo = AlarmRepository(defaults: testDefaults)
        balanceService = BalanceService(defaults: testDefaults)
        // Inject a stub AlarmKit backend so the success path doesn't touch a
        // real system alarm and the failure path is reproducible (rejected
        // schedule, revoked grant). The notification center stays stubbed too,
        // so an accidental notification would be visible. Production code keeps
        // using `AlarmScheduler.shared`.
        mockCenter = MockNotificationCenter()
        alarmKit = TestAlarmKitBackend()
        scheduler = AlarmScheduler(notificationCenter: mockCenter, alarmKit: alarmKit)
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

    /// Stub the AlarmKit backend to reject the reschedule so the scheduler's
    /// `scheduleSnooze` resolves to `.failure(.system)`. The coordinator must:
    ///   1. Surface `.scheduleFailed(error:)` as the outcome
    ///   2. Refund the penalty (balance back to pre-charge amount)
    ///   3. Keep ledger consistent — both charge and refund recorded.
    /// Without this fix the user pays for a snooze that never re-fires
    /// (silent-failure-hunter critical finding on PR #127).
    func testHandleSnooze_schedulerRejectsSnooze_refundsBalanceAndReportsScheduleFailed() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)
        let preCharge = balanceService.balance
        XCTAssertEqual(preCharge, 200)

        alarmKit.failSnooze = true

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        guard case .scheduleFailed(let error) = outcome else {
            return XCTFail("Expected .scheduleFailed, got \(String(describing: outcome))")
        }
        guard case .system(let message) = error else {
            return XCTFail("Expected .system error, got \(error)")
        }
        XCTAssertEqual(message, TestAlarmKitBackend.ScheduleRejected().localizedDescription,
                       "The backend's error message must reach the outcome verbatim")
        XCTAssertEqual(balanceService.balance, preCharge,
                       "Penalty must be refunded so the user isn't billed for a snooze that won't fire")

        // #358: the reversal is typed `.refund`, not `.topup` — the
        // notification-action path must not book phantom IAP revenue either.
        // A second repository over the same suite reads the ledger the
        // coordinator's BalanceService wrote.
        let ledger = TransactionRepository(defaults: testDefaults).fetchAllOrFail()
        let reversal = ledger.first { $0.refundsTransactionID != nil }
        XCTAssertEqual(reversal?.type, .refund)
        XCTAssertEqual(ledger.filter { $0.type == .topup }.count, 1,
                       "Only the 200 ₽ seed top-up is revenue")
    }

    /// Worst-case branch: schedule fails AND the offsetting refund also fails
    /// (typically because the ledger is locked from a corrupt blob — #72/#119).
    /// `.scheduleFailedAndRefundFailed` is the ONLY trigger for the stronger
    /// «обратитесь в поддержку» banner — without test coverage a regression
    /// silently swaps to `.scheduleFailed` and the user thinks money came back
    /// when in fact it didn't (issue #200).
    func testHandleSnooze_schedulerFails_andRefundAlsoFails_reportsDegradedOutcome() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)
        let pre = balanceService.balance

        // Swap in an AlarmKit backend that:
        //   1. Rejects the snooze (so the schedule resolves as .failure)
        //   2. Corrupts the transaction store BEFORE invoking the completion
        //      handler — by the time the coordinator tries to refund, record()
        //      refuses (TransactionRepository locked).
        let corruptingScheduler = AlarmScheduler(
            notificationCenter: MockNotificationCenter(),
            alarmKit: CorruptingThenFailingAlarmKit(defaults: testDefaults)
        )
        let coord = AlarmFiringCoordinator(
            alarmRepository: alarmRepo,
            balanceService: balanceService,
            scheduler: corruptingScheduler
        )

        let exp = expectation(description: "outcome")
        var captured: AlarmFiringCoordinator.SnoozeOutcome?
        coord.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString,
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]) { outcome in
            captured = outcome
            exp.fulfill()
        }
        // 5.0s, matching the suite's `resolveSnooze` helper. The prior 1.0s was
        // too tight for a loaded CI runner — the async handleSnooze + refund
        // chain (≈45ms locally) intermittently overran it under parallel-job
        // contention, leaving `captured` nil and flaking this test on most PRs
        // (#434). This is a tolerance budget, not a perf assertion.
        wait(for: [exp], timeout: 5.0)

        guard case .scheduleFailedAndRefundFailed = captured else {
            return XCTFail("Expected .scheduleFailedAndRefundFailed, got \(String(describing: captured))")
        }
        XCTAssertLessThan(balanceService.balance, pre,
            "Wallet is in degraded state — charge took money, refund did NOT land. Banner UX must surface this.")
    }

    /// No alarm grant at all. Same contract as the `.system` test above but
    /// with the other `SchedulingError` variant — the refund must happen
    /// regardless of which scheduling error class surfaces.
    ///
    /// This case replaces the 64-pending-limit pre-flight test: that limit was a
    /// property of notification scheduling, which the app no longer does (#472).
    /// The failure it stood in for — "the snooze was charged but nothing will
    /// re-ring" — is now reached through a missing grant instead.
    func testHandleSnooze_noAlarmGrant_refundsBalance() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)

        alarmKit.authorization = .denied

        let outcome = resolveSnooze(userInfo: userInfo(for: alarm, snoozeCount: 0))

        guard case .scheduleFailed(let error) = outcome else {
            return XCTFail("Expected .scheduleFailed, got \(String(describing: outcome))")
        }
        guard case .backendUnavailable = error else {
            return XCTFail("Expected .backendUnavailable, got \(error)")
        }
        XCTAssertEqual(balanceService.balance, 200,
                       "Penalty must be refunded when nothing can be armed")
        XCTAssertTrue(alarmKit.snoozedIDs.isEmpty,
                      "An unauthorized backend must not be asked to reschedule")
        XCTAssertTrue(mockCenter.addedRequests.isEmpty,
                      "And the refusal must not degrade into a notification (#472)")
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

/// Rejects the snooze to drive `.scheduleFailed`, but ALSO corrupts the
/// transaction store the moment before invoking the completion handler. By the
/// time the coordinator's refund path calls `refund`, the repository is locked
/// (decode failed on the corrupt blob) and `record()` refuses — reproducing the
/// `.scheduleFailedAndRefundFailed` outcome (issue #200).
private final class CorruptingThenFailingAlarmKit: AlarmKitScheduling {
    struct Rejected: LocalizedError {
        var errorDescription: String? { "AlarmKit rejected the schedule" }
    }

    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }

    var isAuthorized: Bool { true }
    var authorization: AlarmKitAuthorization { .authorized }

    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }

    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(Rejected()))
    }

    func scheduleSnooze(
        _ alarm: Alarm,
        fireDate: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Corrupt the transaction store so the next `record()` call refuses.
        defaults.set(Data("not json".utf8), forKey: "stored_transactions")
        completion(.failure(Rejected()))
    }

    func cancel(_ alarmID: UUID) {}
    func stop(_ alarmID: UUID) {}
}
