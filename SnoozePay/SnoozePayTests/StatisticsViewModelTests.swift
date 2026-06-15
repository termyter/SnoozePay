import XCTest
@testable import SnoozePay

/// Unit tests for the V3 behavioural StatisticsViewModel (#235) — heatmap
/// buckets, weekday distribution, 8-week trend, streak persistence and the
/// surfaced load errors.
///
/// Aggregation maths is exercised through the pure static functions with a
/// pinned `today` (2026-01-27, the Tuesday from the design artboard) so the
/// expectations never race the wall clock; the instance-level tests use
/// relative dates like the rest of the suite.
final class StatisticsViewModelDataTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var txRepo: TransactionRepository!
    private var wakeStore: WakeEventStore!

    /// Monday-first calendar shared by fixtures and the SUT.
    private let calendar = StatisticsViewModel.mondayFirstCalendar

    override func setUp() {
        super.setUp()
        suiteName = "test.statistics.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: testDefaults)
        // The repository now derives the streak from wake events too (#276),
        // so it must share the isolated wake store — otherwise it would read
        // the production singleton and leak real-device history into the test.
        txRepo = TransactionRepository(defaults: testDefaults, wakeStore: wakeStore)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeVM() -> StatisticsViewModel {
        StatisticsViewModel(
            repository: txRepo,
            wakeStore: wakeStore,
            defaults: testDefaults,
            calendar: calendar
        )
    }

    private func addCharge(amount: Double, daysAgo: Int = 0) {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        txRepo.record(Transaction(type: .charge, amount: amount, createdAt: date))
    }

    private func addTopup(amount: Double, daysAgo: Int = 0) {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        txRepo.record(Transaction(type: .topup, amount: amount, createdAt: date))
    }

    /// Pinned date helper — noon avoids any DST edge around midnight.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Records a charge + matching refund pair so tests can assert that a
    /// snooze refunded after a scheduler failure (#130) is excluded from the
    /// behavioural aggregations, mirroring what `AlarmFiringCoordinator` writes
    /// (issue #133).
    @discardableResult
    private func addRefundedCharge(amount: Double, daysAgo: Int = 0) -> Transaction {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let charge = Transaction(type: .charge, amount: amount, createdAt: date)
        let refund = Transaction(
            type: .topup,
            amount: amount,
            createdAt: date,
            refundsTransactionID: charge.id
        )
        txRepo.record(charge)
        txRepo.record(refund)
        return charge
    }

    private func charge(_ amount: Double, on date: Date) -> Transaction {
        Transaction(type: .charge, amount: amount, createdAt: date)
    }

    /// The artboard's reference day — Tuesday, 27 January 2026.
    private var referenceToday: Date { date(2026, 1, 27) }

    // MARK: - loadData

    func testLoadData_keepsOnlyCharges() {
        addCharge(amount: 50, daysAgo: 1)
        addCharge(amount: 100, daysAgo: 3)
        addTopup(amount: 500, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.charges.count, 2, "Topups must not leak into the behavioural aggregations")
        XCTAssertTrue(vm.charges.allSatisfy { $0.type == .charge })
    }

    // MARK: - Refunded snooze charges (issue #133)

    /// A snooze that was charged but refunded after a scheduler failure
    /// (revoked notification permission, pending-limit, etc.) must not appear
    /// in `charges` — the alarm never re-fired so the stats would lie about
    /// user behaviour. `realCharges` strips charges with a matching refund row.
    func testLoadData_refundedCharge_excludedFromCharges() {
        addRefundedCharge(amount: 50, daysAgo: 1)

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.charges.count, 0,
            "Refunded charge represents a snooze that didn't actually fire")
    }

    /// A real charge alongside a refunded one should be counted normally.
    /// Guards against the filter being too aggressive — only charges with a
    /// matching refund row are excluded.
    func testLoadData_realChargeAlongsideRefunded_keepsRealOnly() {
        addCharge(amount: 50, daysAgo: 0)
        addRefundedCharge(amount: 50, daysAgo: 1)

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.charges.count, 1)
        XCTAssertEqual(vm.charges.first?.amount, 50)
    }

    func testOnDataUpdated_calledOnLoad() {
        let vm = makeVM()
        var callbackFired = false
        vm.onDataUpdated = { callbackFired = true }

        vm.loadData()

        XCTAssertTrue(callbackFired, "onDataUpdated should fire when loadData completes")
    }

    /// Corrupt ledger must fire `onLoadError` instead of silently rendering
    /// an all-dark heatmap that looks identical to a brand-new user (#72).
    func testLoadData_corruptedJSON_firesOnLoadError() {
        testDefaults.set(Data("not json".utf8), forKey: "stored_transactions")

        let vm = makeVM()
        var receivedError: LocalizedError?
        vm.onLoadError = { receivedError = $0 }

        vm.loadData()

        XCTAssertNotNil(receivedError, "VM must propagate ledger decode failures to the VC")
        if let typed = receivedError as? TransactionRepository.RepositoryError,
           case .decodeFailure = typed {
            // expected
        } else {
            XCTFail("Expected decodeFailure, got \(String(describing: receivedError))")
        }
        XCTAssertTrue(vm.charges.isEmpty)
        XCTAssertEqual(vm.streak, 0)
    }

    // MARK: - Hero: last slip + best streak

    func testLastSlipText_noCharges_showsNoSlipsCaption() {
        let vm = makeVM()
        vm.loadData()
        XCTAssertEqual(vm.lastSlipText, "Срывов ещё не было")
    }

    func testLastSlipText_showsMostRecentChargeDate() {
        addCharge(amount: 50, daysAgo: 5)
        addCharge(amount: 50, daysAgo: 2)

        let vm = makeVM()
        vm.loadData()

        let expectedDate = calendar.date(byAdding: .day, value: -2, to: Date())!
        XCTAssertEqual(
            vm.lastSlipText,
            "Последний срыв: \(StatisticsViewModel.dayMonthText(expectedDate))"
        )
    }

    func testBestStreak_growsWhenCurrentExceedsStored() {
        testDefaults.set(2, forKey: "best_streak")
        addCharge(amount: 50, daysAgo: 5)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        XCTAssertGreaterThan(vm.streak, 2, "Test setup precondition: current streak should exceed stored")
        XCTAssertEqual(vm.bestStreak, vm.streak, "Best streak should bump up to new high")
        XCTAssertEqual(testDefaults.integer(forKey: "best_streak"), vm.streak)
    }

    func testBestStreak_doesNotResetWhenCurrentIsZero() {
        testDefaults.set(7, forKey: "best_streak")
        addCharge(amount: 50, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.streak, 0)
        XCTAssertEqual(vm.bestStreak, 7, "Stored best streak must survive a slip-up")
    }

    func testBestStreak_doesNotShrinkWhenCurrentIsLower() {
        testDefaults.set(10, forKey: "best_streak")
        addCharge(amount: 50, daysAgo: 3)
        addTopup(amount: 100, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        XCTAssertLessThan(vm.streak, 10, "Test setup precondition: current streak should be below stored")
        XCTAssertEqual(vm.bestStreak, 10, "Best streak should hold the previous high")
    }

    // MARK: - Heatmap buckets (dayStatus)

    func testDayStatus_zeroSnoozesWithWake_isWoke() {
        XCTAssertEqual(StatisticsViewModel.dayStatus(snoozes: 0, woke: true), .woke)
    }

    func testDayStatus_zeroSnoozesWithoutWake_isEmpty() {
        XCTAssertEqual(StatisticsViewModel.dayStatus(snoozes: 0, woke: false), .empty)
    }

    func testDayStatus_oneOrTwoSnoozes_isLight() {
        XCTAssertEqual(StatisticsViewModel.dayStatus(snoozes: 1, woke: false), .light)
        XCTAssertEqual(StatisticsViewModel.dayStatus(snoozes: 2, woke: true), .light)
    }

    func testDayStatus_threePlusSnoozes_isHeavy() {
        XCTAssertEqual(StatisticsViewModel.dayStatus(snoozes: 3, woke: false), .heavy)
        XCTAssertEqual(StatisticsViewModel.dayStatus(snoozes: 7, woke: true), .heavy)
    }

    // MARK: - Heatmap month grid

    /// January 2026 spans Mon Dec 29 → Sun Feb 1 in a Monday-first grid:
    /// exactly 5 full weeks (the artboard's 7×5 layout).
    func testMonthGrid_january2026_has35Cells() {
        let grid = StatisticsViewModel.monthGrid(
            today: referenceToday,
            snoozesByDay: [:],
            wakeDays: [],
            calendar: calendar
        )
        XCTAssertEqual(grid.count, 35)
        XCTAssertEqual(grid.first?.date, calendar.startOfDay(for: date(2025, 12, 29)))
        XCTAssertEqual(grid.last?.date, calendar.startOfDay(for: date(2026, 2, 1)))
    }

    func testMonthGrid_paddingDaysOfAdjacentMonths_areEmpty() {
        // Even with data on a padding day, it renders dark — the calendar
        // reads as the current month only.
        let paddingDay = calendar.startOfDay(for: date(2025, 12, 29))
        let grid = StatisticsViewModel.monthGrid(
            today: referenceToday,
            snoozesByDay: [paddingDay: (count: 5, spent: 500)],
            wakeDays: [],
            calendar: calendar
        )
        let cell = grid.first { $0.date == paddingDay }
        XCTAssertEqual(cell?.isInCurrentMonth, false)
        XCTAssertEqual(cell?.status, .empty)
        XCTAssertEqual(cell?.snoozes, 0)
    }

    func testMonthGrid_futureDays_areEmpty() {
        // Jan 30 is after the pinned "today" (Jan 27) — must stay dark even
        // if (impossible) data existed for it.
        let futureDay = calendar.startOfDay(for: date(2026, 1, 30))
        let grid = StatisticsViewModel.monthGrid(
            today: referenceToday,
            snoozesByDay: [futureDay: (count: 2, spent: 100)],
            wakeDays: [futureDay],
            calendar: calendar
        )
        let cell = grid.first { $0.date == futureDay }
        XCTAssertEqual(cell?.status, .empty)
    }

    func testMonthGrid_bucketsPastDaysBySnoozeCount() {
        let heavyDay = calendar.startOfDay(for: date(2026, 1, 5))
        let lightDay = calendar.startOfDay(for: date(2026, 1, 10))
        let wokeDay = calendar.startOfDay(for: date(2026, 1, 15))
        let quietDay = calendar.startOfDay(for: date(2026, 1, 20))

        let grid = StatisticsViewModel.monthGrid(
            today: referenceToday,
            snoozesByDay: [
                heavyDay: (count: 4, spent: 750),
                lightDay: (count: 2, spent: 100)
            ],
            wakeDays: [wokeDay],
            calendar: calendar
        )

        XCTAssertEqual(grid.first { $0.date == heavyDay }?.status, .heavy)
        XCTAssertEqual(grid.first { $0.date == lightDay }?.status, .light)
        XCTAssertEqual(grid.first { $0.date == wokeDay }?.status, .woke)
        XCTAssertEqual(grid.first { $0.date == quietDay }?.status, .empty)
    }

    func testSnoozesByDay_countsChargesAndSumsAmounts() {
        let day = date(2026, 1, 10)
        let byDay = StatisticsViewModel.snoozesByDay(
            charges: [
                charge(50, on: day),
                charge(100, on: calendar.date(byAdding: .hour, value: 1, to: day)!),
                Transaction(type: .topup, amount: 999, createdAt: day)
            ],
            calendar: calendar
        )
        let key = calendar.startOfDay(for: day)
        XCTAssertEqual(byDay[key]?.count, 2, "1 charge == 1 snooze; topups are ignored")
        XCTAssertEqual(byDay[key]?.spent, 150)
    }

    func testHeatmapDays_instance_todayChargeRendersLight() {
        addCharge(amount: 50, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        let todayStart = calendar.startOfDay(for: Date())
        let cell = vm.heatmapDays.first { $0.date == todayStart }
        XCTAssertEqual(cell?.status, .light)
        XCTAssertEqual(cell?.snoozes, 1)
    }

    func testHeatmapDays_instance_wakeWithoutChargesRendersWoke() {
        wakeStore.recordWake(on: Date(), calendar: calendar)

        let vm = makeVM()
        vm.loadData()

        let todayStart = calendar.startOfDay(for: Date())
        XCTAssertEqual(vm.heatmapDays.first { $0.date == todayStart }?.status, .woke)
    }

    // MARK: - Weekday distribution (4 weeks)

    func testWeekdayAverages_averagesOverFourOccurrences() {
        // Window for today=Jan 27 is Dec 31 … Jan 27. Wednesdays inside:
        // Dec 31, Jan 7, Jan 14, Jan 21. Total 4 snoozes → average 1.0.
        let byDay = StatisticsViewModel.snoozesByDay(
            charges: [
                charge(50, on: date(2026, 1, 7)),
                charge(50, on: date(2026, 1, 7, hour: 8)),
                charge(50, on: date(2026, 1, 14)),
                charge(50, on: date(2026, 1, 21))
            ],
            calendar: calendar
        )
        let averages = StatisticsViewModel.weekdayAverages(
            today: referenceToday,
            snoozesByDay: byDay,
            calendar: calendar
        )
        XCTAssertEqual(averages.count, 7)
        XCTAssertEqual(averages[2], 1.0, accuracy: 0.001, "index 2 = Среда in Monday-first order")
        XCTAssertEqual(averages[0], 0, "Mondays carried no snoozes")
    }

    func testWeekdayAverages_excludesChargesOutsideWindow() {
        // Dec 30 is 28 days before Jan 27 — just past the 28-day window.
        let byDay = StatisticsViewModel.snoozesByDay(
            charges: [charge(50, on: date(2025, 12, 30))],
            calendar: calendar
        )
        let averages = StatisticsViewModel.weekdayAverages(
            today: referenceToday,
            snoozesByDay: byDay,
            calendar: calendar
        )
        XCTAssertEqual(averages.reduce(0, +), 0, "Charges older than 4 weeks must not count")
    }

    func testWorstIndex_picksHighestAverage() {
        XCTAssertEqual(StatisticsViewModel.worstIndex(of: [1, 0.5, 1.75, 0, 1, 0.25, 0]), 2)
    }

    func testWorstIndex_allZero_returnsNil() {
        XCTAssertNil(StatisticsViewModel.worstIndex(of: [0, 0, 0, 0, 0, 0, 0]))
    }

    func testWeekdayStats_instance_marksWorstDay() {
        // 3 snoozes today → today's weekday is trivially the worst.
        addCharge(amount: 50, daysAgo: 0)
        addCharge(amount: 100, daysAgo: 0)
        addCharge(amount: 200, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        let stats = vm.weekdayStats
        XCTAssertEqual(stats.count, 7)
        XCTAssertEqual(stats.map(\.label), StatisticsViewModel.weekdayShortLabels)
        XCTAssertEqual(stats.filter(\.isWorst).count, 1)
        XCTAssertNotNil(vm.worstWeekdayName)
    }

    func testWorstWeekdayName_nilWhenNoSnoozes() {
        let vm = makeVM()
        vm.loadData()
        XCTAssertNil(vm.worstWeekdayName)
    }

    // MARK: - 8-week trend

    func testWeeklyCounts_returnsEightWeeksOldestToNewest() {
        // 5 snoozes last week (Jan 20), 2 this week (Jan 26).
        let byDay = StatisticsViewModel.snoozesByDay(
            charges: [
                charge(50, on: date(2026, 1, 20)),
                charge(50, on: date(2026, 1, 20, hour: 8)),
                charge(50, on: date(2026, 1, 20, hour: 9)),
                charge(50, on: date(2026, 1, 20, hour: 10)),
                charge(50, on: date(2026, 1, 20, hour: 11)),
                charge(50, on: date(2026, 1, 26)),
                charge(50, on: date(2026, 1, 26, hour: 8))
            ],
            calendar: calendar
        )
        let counts = StatisticsViewModel.weeklyCounts(
            today: referenceToday,
            snoozesByDay: byDay,
            calendar: calendar
        )
        XCTAssertEqual(counts.count, 8)
        XCTAssertEqual(counts[7], 2, "Last entry is the current week")
        XCTAssertEqual(counts[6], 5, "Previous calendar week (Mon Jan 19 – Sun Jan 25)")
        XCTAssertEqual(counts[0...5].reduce(0, +), 0)
    }

    func testTrend_improvingWeek_isBetter() {
        let diff = StatisticsViewModel.trendDiff(weeklyCounts: [0, 0, 0, 0, 0, 0, 5, 2])
        XCTAssertEqual(diff, -3)
        XCTAssertEqual(StatisticsViewModel.direction(forDiff: diff), .better)
        XCTAssertEqual(StatisticsViewModel.headline(for: .better), "Становится лучше")
        XCTAssertEqual(StatisticsViewModel.subtitle(forDiff: diff), "−3 к прошлой неделе")
    }

    func testTrend_worseWeek_isWorse() {
        let diff = StatisticsViewModel.trendDiff(weeklyCounts: [0, 0, 0, 0, 0, 0, 1, 4])
        XCTAssertEqual(diff, 3)
        XCTAssertEqual(StatisticsViewModel.direction(forDiff: diff), .worse)
        XCTAssertEqual(StatisticsViewModel.headline(for: .worse), "Чаще, чем неделю назад")
        XCTAssertEqual(StatisticsViewModel.subtitle(forDiff: diff), "+3 к прошлой неделе")
    }

    func testTrend_flatWeek_isSame() {
        let diff = StatisticsViewModel.trendDiff(weeklyCounts: [0, 0, 0, 0, 0, 0, 2, 2])
        XCTAssertEqual(diff, 0)
        XCTAssertEqual(StatisticsViewModel.direction(forDiff: diff), .same)
        XCTAssertEqual(StatisticsViewModel.headline(for: .same), "Стабильно")
        XCTAssertEqual(
            StatisticsViewModel.subtitle(forDiff: diff),
            "Столько же, сколько на прошлой неделе"
        )
    }

    func testWeeklyTrend_instance_marksOnlyCurrentWeek() {
        addCharge(amount: 50, daysAgo: 0)

        let vm = makeVM()
        vm.loadData()

        let trend = vm.weeklyTrend
        XCTAssertEqual(trend.count, 8)
        XCTAssertEqual(trend.filter(\.isCurrent).count, 1)
        XCTAssertTrue(trend.last?.isCurrent ?? false)
        XCTAssertEqual(vm.thisWeekCount, trend.last?.count)
    }
}
