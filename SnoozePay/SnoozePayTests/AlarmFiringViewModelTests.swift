import XCTest
@testable import SnoozePay

/// Unit tests for AlarmFiringViewModel — snooze logic, penalty calculation, balance checks.
final class AlarmFiringViewModelIOS011Tests: XCTestCase {

    /// A scheduler whose backend actually arms the snooze.
    ///
    /// The default `AlarmScheduler.shared` refuses on CI since #472: nobody can
    /// tap "Allow" on a test runner, so AlarmKit stays unauthorized and every
    /// snooze here would be charged and then refunded — which is exactly what
    /// these balance assertions would misread as "the charge never happened".
    /// Before #472 the same call quietly "succeeded" through a notification that
    /// could never have woken anyone, so the suite was green for the wrong reason.
    private let scheduler = AlarmScheduler(
        notificationCenter: InertNotificationCenter(),
        alarmKit: TestAlarmKitBackend()
    )

    /// Every store the view model writes through — wallet, ledger, alarms,
    /// wake days — lives in this per-test suite, dropped in `tearDown` (#814).
    ///
    /// Until #814 this class drove `BalanceService.shared`, the view model's
    /// default `WakeEventStore.shared` and `AlarmRepository(defaults: .standard)`,
    /// and CI run 35861930577 measured it as the first writer of five keys in
    /// the host's real `UserDefaults.standard`: `user_balance`,
    /// `stored_transactions`, `wake_days`, `wake_times`, `stored_alarms`. Every
    /// later test that read one of them inherited whatever this class left.
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var wallet: BalanceService!
    /// Fails the test if it moved the host's real `UserDefaults.standard` (#830).
    private var domainGuard: AppDefaultsDomainGuard!

    override func setUp() {
        super.setUp()
        domainGuard = AppDefaultsDomainGuard()
        suiteName = "test.firing.vm.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        wallet = nil
        defaults = nil
        suiteName = nil
        domainGuard.assertUntouched()
        domainGuard = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// The view model with every store pinned to this test's suite. Only
    /// `alarmRepository` and `wakeStore` are overridable, for the tests that
    /// need to hold on to the same instance to assert on it.
    private func makeViewModel(
        _ alarm: Alarm,
        snoozeCount: Int = 0,
        alarmRepository: AlarmRepository? = nil,
        wakeStore: WakeEventStore? = nil
    ) -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: snoozeCount,
            balanceService: wallet,
            alarmRepository: alarmRepository ?? AlarmRepository(defaults: defaults),
            scheduler: scheduler,
            wakeStore: wakeStore ?? WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults)
        )
    }

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

    /// Set balance to an exact value for deterministic testing. The wallet
    /// starts empty in a fresh suite, so a top-up is all it takes.
    private func setBalance(_ amount: Double) {
        if amount > 0 {
            wallet.topUp(amount: amount)
        }
    }

    // MARK: - Snooze success / failure

    func testSnooze_whenBalanceSufficient_returnsTrue() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        let result = vm.snooze()
        XCTAssertTrue(result, "Snooze should succeed when balance covers the penalty")
    }

    func testSnooze_whenBalanceInsufficient_returnsFalse() {
        setBalance(10)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        let result = vm.snooze()
        XCTAssertFalse(result, "Snooze should fail when balance is less than penalty")
    }

    func testSnooze_whenBalanceExactlyEqualsPenalty_returnsTrue() {
        setBalance(50)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        let result = vm.snooze()
        XCTAssertTrue(result, "Snooze should succeed when balance exactly equals penalty")
        XCTAssertEqual(wallet.balance, 0, accuracy: 0.001,
                       "Balance should be zero after charging exact amount")
    }

    func testSnooze_whenBalanceOneLessThanPenalty_returnsFalse() {
        setBalance(49)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        let result = vm.snooze()
        XCTAssertFalse(result, "Snooze should fail when balance is penalty - 1")
    }

    /// #381: with a zero balance the paid snooze must take *no* money and *not*
    /// snooze — the balance stays at 0 (never negative) and the snooze count is
    /// untouched. The user is instead routed to the Apple Pay top-up (the VC's
    /// no-balance state), and the actual snooze only runs after a successful
    /// top-up flips `canSnooze` true. This is the in-app guard the AlarmKit
    /// lock-screen Snooze button now relies on (it only opens the app; it never
    /// charges), so a −50 ₽ button at 0 ₽ can't snooze for free or go negative.
    func testSnooze_atZeroBalance_takesNoMoneyAndDoesNotSnooze() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        let result = vm.snooze()

        XCTAssertFalse(result, "A paid snooze at 0 ₽ must not proceed")
        XCTAssertFalse(vm.canSnooze, "0 ₽ cannot afford a −50 ₽ snooze")
        XCTAssertEqual(vm.snoozeCount, 0, "snoozeCount must not advance on a refused snooze")
        XCTAssertEqual(wallet.balance, 0, accuracy: 0.001,
                       "Balance must stay at 0 — never deducted, never negative")
    }

    // MARK: - Snooze count

    func testSnooze_incrementsSnoozeCount() {
        setBalance(500)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        XCTAssertEqual(vm.snoozeCount, 0)

        vm.snooze()
        XCTAssertEqual(vm.snoozeCount, 1, "Snooze count should increment after successful snooze")

        vm.snooze()
        XCTAssertEqual(vm.snoozeCount, 2, "Snooze count should increment again on second snooze")
    }

    func testSnooze_doesNotIncrementCountOnFailure() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        vm.snooze()
        XCTAssertEqual(vm.snoozeCount, 0,
                       "Snooze count should not increment when snooze fails")
    }

    // MARK: - Dismiss

    func testDismiss_doesNotChargeBalance() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        let balanceBefore = wallet.balance
        vm.dismiss()
        let balanceAfter = wallet.balance

        XCTAssertEqual(balanceBefore, balanceAfter, accuracy: 0.001,
                       "Dismiss should not deduct any balance")
    }

    func testDismiss_disablesNonRepeatingAlarm() {
        let repo = AlarmRepository(defaults: defaults)
        let alarm = Alarm(repeatDays: [], penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel(alarm, alarmRepository: repo)
        vm.dismiss()

        let saved = repo.fetchOrFail(id: alarm.id)
        XCTAssertEqual(saved?.enabled, false,
                       "Non-repeating alarm should be disabled after dismiss")
    }

    func testDismiss_keepsRepeatingAlarmEnabled() {
        let repo = AlarmRepository(defaults: defaults)
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], penaltyAmount: 50, enabled: true) // Weekdays
        repo.save(alarm)

        let vm = makeViewModel(alarm, alarmRepository: repo)
        vm.dismiss()

        let saved = repo.fetchOrFail(id: alarm.id)
        XCTAssertEqual(saved?.enabled, true,
                       "Repeating alarm should stay enabled after dismiss")
    }

    /// #235: dismissing a firing alarm means the user got up — the wake day
    /// must land in the injected WakeEventStore so the statistics heatmap can
    /// render the "встал сразу" cell.
    func testDismiss_recordsWakeDayInStore() {
        let wakeStore = WakeEventStore(defaults: defaults)

        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm, wakeStore: wakeStore)

        XCTAssertTrue(wakeStore.wakeDays().isEmpty, "Precondition: isolated store starts empty")
        vm.dismiss()

        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(wakeStore.wakeDays(), [today],
                       "Dismiss should record exactly today's wake day")
    }

    /// Issue #54: when the alarm has already been deleted from the repository
    /// (e.g. user removed it from list while firing screen was up), `dismiss()`
    /// must not crash and must not leak any user-facing error — the desired
    /// end-state is already achieved.
    func testDismiss_alarmAlreadyRemoved_doesNotCrash() {
        let repo = AlarmRepository(defaults: defaults)
        let alarm = Alarm(repeatDays: [], penaltyAmount: 50, enabled: true)
        // Intentionally do NOT save — simulate "already removed" repo state.

        let vm = makeViewModel(alarm, alarmRepository: repo)

        // Should complete without throwing/crashing; returned Bool is consumed inside dismiss().
        vm.dismiss()

        XCTAssertNil(repo.fetchOrFail(id: alarm.id),
                     "Alarm should remain absent from repo after dismiss on missing alarm")
    }

    // MARK: - Penalty calculation (progressive scale)

    func testCurrentPenalty_firstSnooze_returnsBase() {
        let alarm = makeAlarm(penalty: 50, progressive: true)
        let vm = makeViewModel(alarm)

        // snoozeCount=0 → penalty(forSnoozeCount: 1) = 50
        XCTAssertEqual(vm.currentPenalty, 50)
    }

    func testCurrentPenalty_withProgressiveScale_doubles() {
        let alarm = makeAlarm(penalty: 50, progressive: true)

        let vm1 = makeViewModel(alarm, snoozeCount: 1)
        XCTAssertEqual(vm1.currentPenalty, 100, "2nd snooze: 50 * 2 = 100")

        let vm2 = makeViewModel(alarm, snoozeCount: 2)
        XCTAssertEqual(vm2.currentPenalty, 200, "3rd snooze: 50 * 4 = 200")

        let vm3 = makeViewModel(alarm, snoozeCount: 3)
        XCTAssertEqual(vm3.currentPenalty, 400, "4th snooze: 50 * 8 = 400 (ceiling)")

        // Ladder caps at base × 8 — the 5th snooze stays at 400, not 800 (#274).
        let vm4 = makeViewModel(alarm, snoozeCount: 4)
        XCTAssertEqual(vm4.currentPenalty, 400, "5th snooze stays at ceiling: 50 * 8 = 400")
    }

    func testCurrentPenalty_withoutProgressiveScale_staysFlat() {
        let alarm = makeAlarm(penalty: 50, progressive: false)

        let vm0 = makeViewModel(alarm)
        XCTAssertEqual(vm0.currentPenalty, 50)

        let vm3 = makeViewModel(alarm, snoozeCount: 3)
        XCTAssertEqual(vm3.currentPenalty, 50, "Without progressive scale, penalty is always base")
    }

    func testCurrentPenalty_progressiveCeilingWithHighBase() {
        // Ladder caps at base × 8: base=1000 → ceiling 8000, not 16000 (#274).
        let alarm = makeAlarm(penalty: 1000, progressive: true)
        let vm = makeViewModel(alarm, snoozeCount: 4)
        XCTAssertEqual(vm.currentPenalty, 8000,
                       "5th snooze with base=1000 stays at ceiling 8000")
    }

    // MARK: - canSnooze

    func testCanSnooze_whenBalanceZero_returnsFalse() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        XCTAssertFalse(vm.canSnooze, "Cannot snooze with zero balance")
    }

    func testCanSnooze_whenBalanceSufficient_returnsTrue() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        XCTAssertTrue(vm.canSnooze, "Should be able to snooze when balance covers penalty")
    }

    // MARK: - Snooze button title

    func testSnoozeButtonTitle_whenCanSnooze_showsPenalty() {
        setBalance(100)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        // V2 copy: "+{minutes} минут · −{penalty} ₽" (default snooze = 9 min,
        // fmtRub narrow no-break space before ₽).
        XCTAssertEqual(vm.snoozeButtonTitle, "+9 минут \u{00B7} −50\u{202F}₽")
    }

    /// The minutes noun agrees with the count (#907). Until then every length
    /// read «минут», so the 1…15 range an alarm allows showed «+1 минут» and
    /// «+3 минут». 11 is the teen that must NOT take the singular.
    func testSnoozeButtonTitle_declinesTheMinutesForTheCount() {
        setBalance(100)
        let expected: [(Int, String)] = [
            (1, "+1 минуту \u{00B7} −50\u{202F}₽"),
            (3, "+3 минуты \u{00B7} −50\u{202F}₽"),
            (5, "+5 минут \u{00B7} −50\u{202F}₽"),
            (11, "+11 минут \u{00B7} −50\u{202F}₽")
        ]
        for (minutes, title) in expected {
            let viewModel = makeViewModel(makeAlarm(penalty: 50, snoozeMinutes: minutes))
            XCTAssertEqual(viewModel.snoozeButtonTitle, title, "snoozeMinutes = \(minutes)")
        }
    }

    func testSnoozeButtonTitle_whenCannotSnooze_showsEmpty() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        XCTAssertEqual(vm.snoozeButtonTitle, "Баланс пуст")
    }

    // MARK: - State change callback

    func testSnooze_callsOnStateChanged() {
        setBalance(200)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        var callbackCalled = false
        vm.onStateChanged = { callbackCalled = true }

        vm.snooze()
        XCTAssertTrue(callbackCalled, "onStateChanged should fire after successful snooze")
    }

    func testSnooze_doesNotCallOnStateChangedOnFailure() {
        setBalance(0)
        let alarm = makeAlarm(penalty: 50)
        let vm = makeViewModel(alarm)

        var callbackCalled = false
        vm.onStateChanged = { callbackCalled = true }

        vm.snooze()
        XCTAssertFalse(callbackCalled,
                       "onStateChanged should not fire when snooze fails")
    }
}
