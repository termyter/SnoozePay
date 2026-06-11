import XCTest
@testable import SnoozePay

/// Unit tests for AlarmFiringViewModel — snooze logic, penalty calculation, balance checks.
final class AlarmFiringViewModelIOS011Tests: XCTestCase {

    // MARK: - Helpers

    private func makeAlarm(
        penalty: Double = 50,
        progressive: Bool = false,
        snoozeMinutes: Int = 9
    ) -> Alarm {
        Alarm(
            snoozeMinutes: snoozeMinutes,
            penaltyAmount: penalty,
            progressiveScale: progressive
        )
    }

    /// Set balance to an exact value for deterministic testing.
    private func setBalance(_ amount: Double) {
        let service = BalanceService.shared
        let current = service.balance
        if current > 0 {
            service.charge(amount: current, alarmID: nil)
        }
        if amount > 0 {
            service.topUp(amount: amount)
        }
    }

    override func tearDown() {
        // Reset balance after each test to avoid side effects
        let service = BalanceService.shared
        let current = service.balance
        if current > 0 {
            service.charge(amount: current, alarmID: nil)
        }
        super.tearDown()
    }

    // MARK: - Snooze success / failure

    func testSnooze_whenBalanceSufficient_returnsTrue() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        let result = vm.snooze()
        XCTAssertTrue(result, "Snooze should succeed when balance covers the penalty")
    }

    func testSnooze_whenBalanceInsufficient_returnsFalse() {
        setBalance(10)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        let result = vm.snooze()
        XCTAssertFalse(result, "Snooze should fail when balance is less than penalty")
    }

    func testSnooze_whenBalanceExactlyEqualsPenalty_returnsTrue() {
        setBalance(50)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        let result = vm.snooze()
        XCTAssertTrue(result, "Snooze should succeed when balance exactly equals penalty")
        XCTAssertEqual(BalanceService.shared.balance, 0, accuracy: 0.001,
                       "Balance should be zero after charging exact amount")
    }

    func testSnooze_whenBalanceOneLessThanPenalty_returnsFalse() {
        setBalance(49)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        let result = vm.snooze()
        XCTAssertFalse(result, "Snooze should fail when balance is penalty - 1")
    }

    // MARK: - Snooze count

    func testSnooze_incrementsSnoozeCount() {
        setBalance(500)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        XCTAssertEqual(vm.snoozeCount, 0)

        vm.snooze()
        XCTAssertEqual(vm.snoozeCount, 1, "Snooze count should increment after successful snooze")

        vm.snooze()
        XCTAssertEqual(vm.snoozeCount, 2, "Snooze count should increment again on second snooze")
    }

    func testSnooze_doesNotIncrementCountOnFailure() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        vm.snooze()
        XCTAssertEqual(vm.snoozeCount, 0,
                       "Snooze count should not increment when snooze fails")
    }

    // MARK: - Dismiss

    func testDismiss_doesNotChargeBalance() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        let balanceBefore = BalanceService.shared.balance
        vm.dismiss()
        let balanceAfter = BalanceService.shared.balance

        XCTAssertEqual(balanceBefore, balanceAfter, accuracy: 0.001,
                       "Dismiss should not deduct any balance")
    }

    func testDismiss_disablesNonRepeatingAlarm() {
        let repo = AlarmRepository(defaults: .standard)
        var alarm = Alarm(penaltyAmount: 50)
        alarm.repeatDays = []
        alarm.enabled = true
        repo.save(alarm)

        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, alarmRepository: repo)
        vm.dismiss()

        let saved = repo.fetch(id: alarm.id)
        XCTAssertEqual(saved?.enabled, false,
                       "Non-repeating alarm should be disabled after dismiss")

        // Cleanup
        repo.delete(id: alarm.id)
    }

    func testDismiss_keepsRepeatingAlarmEnabled() {
        let repo = AlarmRepository(defaults: .standard)
        var alarm = Alarm(penaltyAmount: 50)
        alarm.repeatDays = [0, 1, 2, 3, 4] // Weekdays
        alarm.enabled = true
        repo.save(alarm)

        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, alarmRepository: repo)
        vm.dismiss()

        let saved = repo.fetch(id: alarm.id)
        XCTAssertEqual(saved?.enabled, true,
                       "Repeating alarm should stay enabled after dismiss")

        // Cleanup
        repo.delete(id: alarm.id)
    }

    /// Issue #54: when the alarm has already been deleted from the repository
    /// (e.g. user removed it from list while firing screen was up), `dismiss()`
    /// must not crash and must not leak any user-facing error — the desired
    /// end-state is already achieved.
    func testDismiss_alarmAlreadyRemoved_doesNotCrash() {
        let repo = AlarmRepository(defaults: .standard)
        var alarm = Alarm(penaltyAmount: 50)
        alarm.repeatDays = []
        alarm.enabled = true
        // Intentionally do NOT save — simulate "already removed" repo state.

        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, alarmRepository: repo)

        // Should complete without throwing/crashing; returned Bool is consumed inside dismiss().
        vm.dismiss()

        XCTAssertNil(repo.fetch(id: alarm.id),
                     "Alarm should remain absent from repo after dismiss on missing alarm")
    }

    // MARK: - Penalty calculation (progressive scale)

    func testCurrentPenalty_firstSnooze_returnsBase() {
        let alarm = makeAlarm(penalty: 50, progressive: true)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        // snoozeCount=0 → penalty(forSnoozeCount: 1) = 50
        XCTAssertEqual(vm.currentPenalty, 50)
    }

    func testCurrentPenalty_withProgressiveScale_doubles() {
        let alarm = makeAlarm(penalty: 50, progressive: true)

        let vm1 = AlarmFiringViewModel(alarm: alarm, snoozeCount: 1)
        XCTAssertEqual(vm1.currentPenalty, 100, "2nd snooze: 50 * 2 = 100")

        let vm2 = AlarmFiringViewModel(alarm: alarm, snoozeCount: 2)
        XCTAssertEqual(vm2.currentPenalty, 200, "3rd snooze: 50 * 4 = 200")

        let vm3 = AlarmFiringViewModel(alarm: alarm, snoozeCount: 3)
        XCTAssertEqual(vm3.currentPenalty, 400, "4th snooze: 50 * 8 = 400")

        let vm4 = AlarmFiringViewModel(alarm: alarm, snoozeCount: 4)
        XCTAssertEqual(vm4.currentPenalty, 800, "5th snooze: 50 * 16 = 800")
    }

    func testCurrentPenalty_withoutProgressiveScale_staysFlat() {
        let alarm = makeAlarm(penalty: 50, progressive: false)

        let vm0 = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)
        XCTAssertEqual(vm0.currentPenalty, 50)

        let vm3 = AlarmFiringViewModel(alarm: alarm, snoozeCount: 3)
        XCTAssertEqual(vm3.currentPenalty, 50, "Without progressive scale, penalty is always base")
    }

    func testCurrentPenalty_progressiveFifthSnoozeWithHighBase() {
        // Verify overflow scenario: base=1000, 5th snooze = 1000 * 16 = 16000
        let alarm = makeAlarm(penalty: 1000, progressive: true)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 4)
        XCTAssertEqual(vm.currentPenalty, 16000,
                       "5th snooze with base=1000 should be 16000")
    }

    // MARK: - canSnooze

    func testCanSnooze_whenBalanceZero_returnsFalse() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        XCTAssertFalse(vm.canSnooze, "Cannot snooze with zero balance")
    }

    func testCanSnooze_whenBalanceSufficient_returnsTrue() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        XCTAssertTrue(vm.canSnooze, "Should be able to snooze when balance covers penalty")
    }

    // MARK: - Snooze button title

    func testSnoozeButtonTitle_whenCanSnooze_showsPenalty() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        // V2 copy: "+{minutes} минут · −{penalty} ₽" (default snooze = 9 min,
        // fmtRub narrow no-break space before ₽).
        XCTAssertEqual(vm.snoozeButtonTitle, "+9 минут \u{00B7} −50\u{202F}₽")
    }

    func testSnoozeButtonTitle_whenCannotSnooze_showsEmpty() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        XCTAssertEqual(vm.snoozeButtonTitle, "Баланс пуст")
    }

    // MARK: - State change callback

    func testSnooze_callsOnStateChanged() {
        setBalance(200)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        var callbackCalled = false
        vm.onStateChanged = { callbackCalled = true }

        vm.snooze()
        XCTAssertTrue(callbackCalled, "onStateChanged should fire after successful snooze")
    }

    func testSnooze_doesNotCallOnStateChangedOnFailure() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)

        var callbackCalled = false
        vm.onStateChanged = { callbackCalled = true }

        vm.snooze()
        XCTAssertFalse(callbackCalled,
                       "onStateChanged should not fire when snooze fails")
    }
}
