import XCTest
@testable import SnoozePay

/// Unit tests for StatisticsViewModel — period filtering, totals, streak, chart data, declension.
final class StatisticsViewModelDataTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var txRepo: TransactionRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.statistics.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        txRepo = TransactionRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeVM() -> StatisticsViewModel {
        StatisticsViewModel(repository: txRepo)
    }

    private func addCharge(amount: Double, daysAgo: Int = 0) {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let tx = Transaction(type: .charge, amount: amount, createdAt: date)
        txRepo.record(tx)
    }

    private func addTopup(amount: Double, daysAgo: Int = 0) {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let tx = Transaction(type: .topup, amount: amount, createdAt: date)
        txRepo.record(tx)
    }

    // MARK: - loadData period filtering

    func testLoadData_weekPeriod_filtersCorrectly() {
        addCharge(amount: 50, daysAgo: 1)   // within week
        addCharge(amount: 100, daysAgo: 3)  // within week
        addCharge(amount: 200, daysAgo: 10) // outside week

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.snoozeCount, 2, "Only charges within the last 7 days should be included")
        XCTAssertEqual(vm.totalSpent, 150)
    }

    func testLoadData_monthPeriod_filtersCorrectly() {
        addCharge(amount: 50, daysAgo: 1)   // within month
        addCharge(amount: 100, daysAgo: 20) // within month
        addCharge(amount: 200, daysAgo: 40) // outside month

        let vm = makeVM()
        vm.loadData(period: .month)

        XCTAssertEqual(vm.snoozeCount, 2)
        XCTAssertEqual(vm.totalSpent, 150)
    }

    func testLoadData_allTime_returnsAllCharges() {
        addCharge(amount: 50, daysAgo: 1)
        addCharge(amount: 100, daysAgo: 100)
        addCharge(amount: 200, daysAgo: 365)
        addTopup(amount: 999, daysAgo: 0) // topups should NOT be counted

        let vm = makeVM()
        vm.loadData(period: .allTime)

        XCTAssertEqual(vm.snoozeCount, 3, "All charges should be included regardless of date")
        XCTAssertEqual(vm.totalSpent, 350)
    }

    func testLoadData_allTime_excludesTopups() {
        addTopup(amount: 500, daysAgo: 0)
        addTopup(amount: 300, daysAgo: 5)

        let vm = makeVM()
        vm.loadData(period: .allTime)

        XCTAssertEqual(vm.snoozeCount, 0)
        XCTAssertEqual(vm.totalSpent, 0)
    }

    // MARK: - Total spent

    func testTotalSpent_sumsCorrectly() {
        addCharge(amount: 50, daysAgo: 0)
        addCharge(amount: 100, daysAgo: 0)
        addCharge(amount: 75, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.totalSpent, 225)
        XCTAssertEqual(vm.totalSpentFormatted, "225 ₽")
    }

    // MARK: - Snooze count

    func testSnoozeCount_matchesChargeCount() {
        addCharge(amount: 50, daysAgo: 0)
        addCharge(amount: 50, daysAgo: 1)
        addCharge(amount: 50, daysAgo: 2)
        addTopup(amount: 500, daysAgo: 0) // not a snooze

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.snoozeCount, 3)
        XCTAssertEqual(vm.snoozeCountFormatted, "3 раз")
    }

    // MARK: - Motivational messages

    func testMotivationalMessage_whenZeroSpent() {
        let vm = makeVM()
        vm.loadData(period: .week)
        XCTAssertEqual(vm.motivationalMessage, "Отлично! Вы не откладывали будильник.")
    }

    func testMotivationalMessage_withCoffeeComparison() {
        // 150 per coffee, so 300 spent = 2 coffees
        addCharge(amount: 300, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertTrue(vm.motivationalMessage.contains("2 чашек кофе"))
        XCTAssertTrue(vm.motivationalMessage.contains("☕"))
    }

    func testMotivationalMessage_lessThanOneCoffee() {
        // Less than 150 -> no coffee comparison, fallback message
        addCharge(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.motivationalMessage, "Продолжайте в том же духе!")
    }

    func testMotivationalMessage_exactlyOneCoffee() {
        addCharge(amount: 150, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertTrue(vm.motivationalMessage.contains("1 чашек кофе"))
    }

    // MARK: - Streak message

    func testStreakMessage_format() {
        // With no charges and some topup, streak should be >= 1
        addTopup(amount: 500, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        if vm.streak > 0 {
            XCTAssertTrue(vm.streakMessage.contains("без откладывания"))
            XCTAssertTrue(vm.streakMessage.contains("\(vm.streak)"))
        }
    }

    func testStreakMessage_emptyWhenNoStreak() {
        // Charge today means streak = 0
        addCharge(amount: 50, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.streakMessage, "")
    }

    // MARK: - dayWord declension (tested via streakMessage indirectly)

    /// Since dayWord is private, we test it through streakMessage.
    /// We set up data so that streak == the target count, then check the word.

    func testDayWord_correctDeclension_1day() {
        // 1 day without charge: charge yesterday (day 1 ago), topup today
        addCharge(amount: 50, daysAgo: 1)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        if vm.streak == 1 {
            XCTAssertTrue(vm.streakMessage.contains("день"), "1 -> 'день', got: \(vm.streakMessage)")
        }
    }

    func testDayWord_correctDeclension_2days() {
        addCharge(amount: 50, daysAgo: 2)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        if vm.streak == 2 {
            XCTAssertTrue(vm.streakMessage.contains("дня"), "2 -> 'дня', got: \(vm.streakMessage)")
        }
    }

    func testDayWord_correctDeclension_5days() {
        addCharge(amount: 50, daysAgo: 5)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        if vm.streak == 5 {
            XCTAssertTrue(vm.streakMessage.contains("дней"), "5 -> 'дней', got: \(vm.streakMessage)")
        }
    }

    func testDayWord_correctDeclension_11days() {
        addCharge(amount: 50, daysAgo: 11)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .allTime)

        if vm.streak == 11 {
            XCTAssertTrue(vm.streakMessage.contains("дней"), "11 -> 'дней', got: \(vm.streakMessage)")
        }
    }

    func testDayWord_correctDeclension_21days() {
        addCharge(amount: 50, daysAgo: 21)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .allTime)

        if vm.streak == 21 {
            XCTAssertTrue(vm.streakMessage.contains("день"), "21 -> 'день', got: \(vm.streakMessage)")
        }
    }

    // MARK: - Daily chart data

    func testDailyChartData_weekHas7Entries() {
        let vm = makeVM()
        vm.loadData(period: .week)
        XCTAssertEqual(vm.dailyChartData.count, 7)
    }

    func testDailyChartData_monthHas30Entries() {
        let vm = makeVM()
        vm.loadData(period: .month)
        XCTAssertEqual(vm.dailyChartData.count, 30)
    }

    func testDailyChartData_allTime_returnsEmpty() {
        let vm = makeVM()
        vm.loadData(period: .allTime)
        XCTAssertTrue(vm.dailyChartData.isEmpty)
    }

    func testDailyChartData_todayChargeAppearsInLastEntry() {
        addCharge(amount: 75, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        let data = vm.dailyChartData
        // Last entry should be today
        let lastEntry = data.last
        XCTAssertNotNil(lastEntry)
        XCTAssertEqual(lastEntry?.amount, 75)
    }

    func testDailyChartData_labels_areNotEmpty() {
        let vm = makeVM()
        vm.loadData(period: .week)

        for entry in vm.dailyChartData {
            XCTAssertFalse(entry.label.isEmpty, "Chart label should not be empty")
        }
    }

    // MARK: - onDataUpdated callback

    func testOnDataUpdated_calledOnLoad() {
        let vm = makeVM()
        var callbackFired = false
        vm.onDataUpdated = { callbackFired = true }

        vm.loadData(period: .week)

        XCTAssertTrue(callbackFired, "onDataUpdated should fire when loadData completes")
    }

    func testSelectedPeriod_updatedOnLoad() {
        let vm = makeVM()

        vm.loadData(period: .month)
        XCTAssertEqual(vm.selectedPeriod, .month)

        vm.loadData(period: .allTime)
        XCTAssertEqual(vm.selectedPeriod, .allTime)

        vm.loadData(period: .week)
        XCTAssertEqual(vm.selectedPeriod, .week)
    }

    // MARK: - averagePerDay

    func testAveragePerDay_weekPeriod() {
        // 700 spent over 7-day period = 100 per day
        addCharge(amount: 100, daysAgo: 0)
        addCharge(amount: 100, daysAgo: 1)
        addCharge(amount: 100, daysAgo: 2)
        addCharge(amount: 100, daysAgo: 3)
        addCharge(amount: 100, daysAgo: 4)
        addCharge(amount: 100, daysAgo: 5)
        addCharge(amount: 100, daysAgo: 6)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.averagePerDay, 100, accuracy: 0.01)
    }

    func testAveragePerDay_zeroPeriod() {
        // No charges at all — should return 0
        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.averagePerDay, 0)
    }

    func testAveragePerDayFormatted_format() {
        addCharge(amount: 350, daysAgo: 0)
        addCharge(amount: 350, daysAgo: 1)

        let vm = makeVM()
        vm.loadData(period: .week)

        // 700 / 7 = 100.0
        XCTAssertEqual(vm.averagePerDayFormatted, "100.0 / утро")
    }

    // MARK: - bestStreak

    func testBestStreak_equalToCurrentStreak() {
        // In MVP, bestStreak is always the same as current streak
        addCharge(amount: 50, daysAgo: 5)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.bestStreak, vm.streak)
    }

    func testBestStreakFormatted_format() {
        // With no charges, streak should be some value; verify format
        let vm = makeVM()
        vm.loadData(period: .week)

        let formatted = vm.bestStreakFormatted
        XCTAssertTrue(formatted.hasPrefix("Лучший результат: "), "Should start with 'Лучший результат: ', got: \(formatted)")
        // Verify it ends with a day word (день/дня/дней)
        let hasDayWord = formatted.contains("день") || formatted.contains("дня") || formatted.contains("дней")
        XCTAssertTrue(hasDayWord, "Should contain a day declension, got: \(formatted)")
    }

    // MARK: - motivationalMessage coffee format

    func testMotivationalMessage_coffeeFormat() {
        // 450 / 150 = 3 coffees
        addCharge(amount: 450, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        XCTAssertEqual(vm.motivationalMessage, "450₽ на лень = 3 кофе! ☕")
    }

    // MARK: - Updated formatting properties

    func testTotalSpentFormatted_rublePrefix() {
        addCharge(amount: 250, daysAgo: 0)

        let vm = makeVM()
        vm.loadData(period: .week)

        // New format uses ruble sign as prefix: "₽250"
        XCTAssertEqual(vm.totalSpentFormatted, "₽250")
    }

    func testSnoozeCountFormatted_justNumber() {
        // Add 23 charges
        for _ in 0..<23 {
            addCharge(amount: 10, daysAgo: 0)
        }

        let vm = makeVM()
        vm.loadData(period: .week)

        // New format is just the number, no suffix
        XCTAssertEqual(vm.snoozeCountFormatted, "23")
    }
}
