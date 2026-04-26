import XCTest
@testable import SnoozePay

/// Unit tests for AlarmFiringCoordinator — the snooze-from-notification flow
/// extracted out of AppDelegate. Exercises the four `SnoozeOutcome` branches
/// against an isolated balance + repo so the real singletons stay untouched.
final class AlarmFiringCoordinatorTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var alarmRepo: AlarmRepository!
    private var balanceService: BalanceService!
    private var coordinator: AlarmFiringCoordinator!

    override func setUp() {
        super.setUp()
        suiteName = "test.coordinator.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        alarmRepo = AlarmRepository(defaults: testDefaults)
        balanceService = BalanceService(defaults: testDefaults)
        coordinator = AlarmFiringCoordinator(
            alarmRepository: alarmRepo,
            balanceService: balanceService,
            scheduler: AlarmScheduler.shared
        )
    }

    override func tearDown() {
        // Clean up any notifications the coordinator may have scheduled during
        // the success path so subsequent tests / app launches start clean.
        AlarmScheduler.shared.cancelAll()
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAlarm(penalty: Double = 50, progressive: Bool = false) -> Alarm {
        let alarm = Alarm(penaltyAmount: penalty, progressiveScale: progressive)
        alarmRepo.save(alarm)
        return alarm
    }

    // MARK: - Invalid payload

    func testHandleSnooze_missingAlarmID_returnsInvalidPayload() {
        let outcome = coordinator.handleSnooze(userInfo: ["snoozeCount": 0])
        XCTAssertEqual(outcome, .invalidPayload)
    }

    func testHandleSnooze_invalidAlarmIDString_returnsInvalidPayload() {
        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": "not-a-uuid",
            "snoozeCount": 0
        ])
        XCTAssertEqual(outcome, .invalidPayload)
    }

    func testHandleSnooze_missingSnoozeCount_returnsInvalidPayload() {
        let alarm = makeAlarm()
        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString
        ])
        XCTAssertEqual(outcome, .invalidPayload)
    }

    // MARK: - Alarm not found

    func testHandleSnooze_unknownAlarmID_returnsAlarmNotFound() {
        // Valid UUID, but no alarm with that ID was saved.
        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": UUID().uuidString,
            "snoozeCount": 0
        ])
        XCTAssertEqual(outcome, .alarmNotFound)
    }

    // MARK: - Insufficient funds

    func testHandleSnooze_insufficientBalance_returnsInsufficientFunds() {
        let alarm = makeAlarm(penalty: 100)
        // Balance is 0 (fresh UserDefaults suite).
        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString,
            "snoozeCount": 0
        ])
        XCTAssertEqual(outcome, .insufficientFunds)
        XCTAssertEqual(balanceService.balance, 0, "Balance must not be touched on a failed charge")
    }

    // MARK: - Success

    func testHandleSnooze_validRequest_chargesBalanceAndIncrementsCount() {
        let alarm = makeAlarm(penalty: 50)
        balanceService.topUp(amount: 200)

        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString,
            "snoozeCount": 0
        ])

        XCTAssertEqual(outcome, .scheduled(newSnoozeCount: 1, charged: 50))
        XCTAssertEqual(balanceService.balance, 150)
    }

    func testHandleSnooze_progressivePenalty_appliesToNewCount() {
        // snoozeCount=1 in payload + progressive scale → penalty(forSnoozeCount: 2) = 100
        let alarm = makeAlarm(penalty: 50, progressive: true)
        balanceService.topUp(amount: 500)

        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString,
            "snoozeCount": 1
        ])

        XCTAssertEqual(outcome, .scheduled(newSnoozeCount: 2, charged: 100))
        XCTAssertEqual(balanceService.balance, 400)
    }

    func testHandleSnooze_balanceExactlyEqualsPenalty_succeeds() {
        // Boundary: balance == penalty should be chargeable (>= comparison).
        let alarm = makeAlarm(penalty: 75)
        balanceService.topUp(amount: 75)

        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString,
            "snoozeCount": 0
        ])

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

        let outcome = coordinator.handleSnooze(userInfo: [
            "alarmID": alarm.id.uuidString,
            "snoozeCount": 0
        ])

        XCTAssertEqual(outcome, .alarmNotFound,
                       "From a notification action there's no recovery UI, so collapse to alarmNotFound")
        XCTAssertTrue(alarmRepo.lastLoadFailed,
                      "The checked fetch must arm the persistence lock so a follow-up save can't clobber the corrupt blob")
    }
}
