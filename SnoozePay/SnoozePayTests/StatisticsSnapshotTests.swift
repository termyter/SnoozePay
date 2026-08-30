import XCTest
@testable import SnoozePay

/// Regression tests for the single-clock snapshot that drives the statistics
/// screen. Keeping these separate from money-formatting tests prevents either
/// suite from crossing the project's type-body-length lint threshold.
final class StatisticsSnapshotTests: XCTestCase {

    private final class StubScheduler: AlarmScheduling {
        func schedule(
            _ alarm: Alarm,
            completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?
        ) {
            completion?(.success(()))
        }

        func cancel(_ alarmID: UUID) {}
    }

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var transactionRepository: TransactionRepository!
    private var wakeStore: WakeEventStore!
    private var alarmRepository: AlarmRepository!

    private let calendar = StatisticsViewModel.mondayFirstCalendar

    override func setUp() {
        super.setUp()
        suiteName = "test.statisticsSnapshot.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: defaults)
        transactionRepository = TransactionRepository(defaults: defaults, wakeStore: wakeStore)
        alarmRepository = AlarmRepository(defaults: defaults, scheduler: StubScheduler())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeViewModel() -> StatisticsViewModel {
        StatisticsViewModel(
            repository: transactionRepository,
            wakeStore: wakeStore,
            alarmRepository: alarmRepository,
            defaults: defaults,
            calendar: calendar
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 7, minute: 30))!
    }

    /// All behavioural blocks are stored in the same snapshot as money.
    /// Moving the snapshot far enough forward must retire the old charge from
    /// every range — a stale heatmap, weekday bar or trend would otherwise
    /// mix different calendar periods on one screen (#459).
    func testRecompute_allBehaviouralBlocksMoveWithSnapshotDate() {
        let monday = date(2026, 1, 26)
        let muchLaterMonday = date(2026, 5, 4)
        transactionRepository.record(Transaction(type: .charge, amount: 150, createdAt: monday))
        wakeStore.recordWake(on: monday, calendar: calendar)

        let viewModel = makeViewModel()
        viewModel.loadData()

        viewModel.recomputeSnapshots(today: monday)
        let mondayHeatmap = viewModel.heatmapDays
        let mondayWeekdayStats = viewModel.weekdayStats
        let mondayTrend = viewModel.weeklyTrend
        XCTAssertEqual(viewModel.worstWeekdayNames, ["понедельник"])
        XCTAssertEqual(viewModel.trendDiff, 1)

        viewModel.recomputeSnapshots(today: muchLaterMonday)
        XCTAssertNotEqual(viewModel.heatmapDays, mondayHeatmap)
        XCTAssertNotEqual(viewModel.weekdayStats, mondayWeekdayStats)
        XCTAssertNotEqual(viewModel.weeklyTrend, mondayTrend)
        XCTAssertTrue(viewModel.worstWeekdayNames.isEmpty)
        XCTAssertEqual(viewModel.trendDiff, 0)
    }
}
