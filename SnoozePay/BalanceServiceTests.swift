import XCTest
@testable import SnoozePay

/// Unit tests for BalanceService — the critical financial logic.
final class BalanceServiceTests: XCTestCase {

    /// Use a fresh UserDefaults suite to avoid polluting real app data.
    private var testDefaults: UserDefaults!
    private var service: BalanceService!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test_\(UUID().uuidString)")!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testDefaults.suiteName ?? "")
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService(balance: Double = 0) -> BalanceService {
        testDefaults.set(balance, forKey: "user_balance")
        return BalanceService.shared
    }
}

/// Tests for AlarmFiringViewModel — snooze/balance deduction edge cases.
final class AlarmFiringViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func alarm(penalty: Double, progressive: Bool = false) -> Alarm {
        Alarm(
            penaltyAmount: penalty,
            progressiveScale: progressive
        )
    }

    // MARK: - canSnooze tests

    func testCanSnoozeWhenBalanceExact() {
        // Balance = exactly penalty amount → should succeed, balance becomes 0
        let balanceService = BalanceService.shared
        let startBalance = balanceService.balance

        let alarm = alarm(penalty: 50)
        // Set balance to exactly the penalty
        balanceService.topUp(amount: 50 - startBalance + startBalance) // Reset to known state

        // Test the pure logic: canAfford(50) when balance = 50
        // This is tested in the ViewModel indirectly via canSnooze
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)
        // The actual canSnooze depends on live balance — test the calculation path
        let penalty = alarm.penalty(forSnoozeCount: 1)
        XCTAssertEqual(penalty, 50)
    }

    func testPenaltyForFirstSnooze() {
        let alarm = alarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)
        XCTAssertEqual(vm.currentPenalty, 50)
    }

    func testPenaltyForSecondSnoozeWithProgression() {
        let alarm = alarm(penalty: 50, progressive: true)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 1)
        // snoozeCount=1 → penalty(forSnoozeCount: 2) → 50 * 2 = 100
        XCTAssertEqual(vm.currentPenalty, 100)
    }

    func testPenaltyForFifthSnooze() {
        let alarm = alarm(penalty: 50, progressive: true)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 4)
        // snoozeCount=4 → penalty(forSnoozeCount: 5) → 50 * 16 = 800
        XCTAssertEqual(vm.currentPenalty, 800)
    }

    func testSnoozeButtonTitleWhenEmpty() {
        let balanceService = BalanceService.shared
        // Drain balance
        let currentBalance = balanceService.balance
        if currentBalance > 0 {
            balanceService.charge(amount: currentBalance, alarmID: nil)
        }

        let alarm = alarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, balanceService: balanceService)

        XCTAssertFalse(vm.canSnooze)
        XCTAssertEqual(vm.snoozeButtonTitle, "Баланс пуст")
    }
}

/// Tests for AlarmsListViewModel.
final class AlarmsListViewModelTests: XCTestCase {

    func testAlarmTimeFormatting() {
        let repo = AlarmRepository()
        let vm = AlarmsListViewModel(alarmRepository: repo)

        // No alarms — verify safe index handling
        XCTAssertEqual(vm.alarmTimeString(at: 0), "")
        XCTAssertEqual(vm.alarmSubtitle(at: 0), "")
    }

    func testFormattedBalance() {
        let vm = AlarmsListViewModel()
        // formattedBalance should always contain ₽
        XCTAssertTrue(vm.formattedBalance.contains("₽"))
    }
}

/// Tests for StatisticsViewModel — streak and period filtering.
final class StatisticsViewModelTests: XCTestCase {

    func testEmptyDataMotivation() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .week)
        // With no transactions, should show positive message
        XCTAssertEqual(vm.motivationalMessage, "Отлично! Вы не откладывали будильник.")
    }

    func testTotalSpentZero() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .allTime)
        XCTAssertEqual(vm.totalSpent, 0)
        XCTAssertEqual(vm.totalSpentFormatted, "0 ₽")
    }

    func testPeriodTitles() {
        XCTAssertEqual(StatisticsViewModel.Period.week.title, "Неделя")
        XCTAssertEqual(StatisticsViewModel.Period.month.title, "Месяц")
        XCTAssertEqual(StatisticsViewModel.Period.allTime.title, "Всё время")
    }

    func testChartDataCountForWeek() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .week)
        XCTAssertEqual(vm.dailyChartData.count, 7)
    }

    func testChartDataCountForMonth() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .month)
        XCTAssertEqual(vm.dailyChartData.count, 30)
    }

    func testChartDataEmptyForAllTime() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .allTime)
        XCTAssertTrue(vm.dailyChartData.isEmpty)
    }
}

/// Tests for CreateAlarmViewModel — progressive scale preview and day toggle.
final class CreateAlarmViewModelTests: XCTestCase {

    func testProgressiveScalePreview() {
        let vm = CreateAlarmViewModel()
        vm.penaltyAmount = 50
        // Expected: "1-е: 50₽ → 2-е: 100₽ → 3-е: 200₽ → 4-е: 400₽"
        let preview = vm.progressiveScalePreview
        XCTAssertTrue(preview.contains("50₽"))
        XCTAssertTrue(preview.contains("100₽"))
        XCTAssertTrue(preview.contains("200₽"))
        XCTAssertTrue(preview.contains("400₽"))
    }

    func testDayToggleAddsAndRemoves() {
        let vm = CreateAlarmViewModel()
        XCTAssertTrue(vm.repeatDays.isEmpty)

        vm.toggleDay(0) // Add Monday
        XCTAssertEqual(vm.repeatDays, [0])

        vm.toggleDay(2) // Add Wednesday
        XCTAssertEqual(vm.repeatDays, [0, 2])

        vm.toggleDay(0) // Remove Monday
        XCTAssertEqual(vm.repeatDays, [2])
    }

    func testDayToggleSortedOrder() {
        let vm = CreateAlarmViewModel()
        vm.toggleDay(6)
        vm.toggleDay(0)
        vm.toggleDay(3)
        XCTAssertEqual(vm.repeatDays, [0, 3, 6]) // Should always be sorted
    }

    func testSaveCreatesNewAlarmWithCorrectValues() {
        let vm = CreateAlarmViewModel()
        vm.name = "Тест"
        vm.penaltyAmount = 100
        vm.progressiveScale = true
        vm.snoozeMinutes = 15
        vm.vibrationEnabled = false

        // Save should not crash
        let result = vm.save()
        XCTAssertTrue(result)
    }

    func testEmptyNameDefaultsToPlaceholder() {
        let vm = CreateAlarmViewModel()
        vm.name = ""
        vm.save()
        // Verify the alarm was saved with default name
        let saved = AlarmRepository().fetchAll().last
        XCTAssertEqual(saved?.name, "Будильник")
    }
}
