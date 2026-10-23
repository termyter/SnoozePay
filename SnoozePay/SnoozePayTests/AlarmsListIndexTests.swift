import XCTest
@testable import SnoozePay

final class AlarmsListIndexTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private var repository: AlarmRepository!
    private var scheduler: AlarmsListViewModelTests.StubScheduler!

    override func setUp() {
        super.setUp()
        suite = "test.alarmsListIndices.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        scheduler = AlarmsListViewModelTests.StubScheduler()
        repository = AlarmRepository(defaults: defaults, scheduler: scheduler)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        repository = nil
        scheduler = nil
        defaults = nil
        super.tearDown()
    }

    func testDisplayHelpersRejectInvalidIndicesInEmptyAndPopulatedSnapshots() {
        for alarms in [[], fixtureAlarms()] {
            let viewModel = makeViewModel(alarms: alarms)
            XCTAssertEqual(viewModel.alarms.count, alarms.count)
            for index in [Int.min, -1, alarms.count, Int.max] {
                XCTAssertEqual(viewModel.alarmTimeString(at: index), "", "index=\(index)")
                XCTAssertEqual(viewModel.alarmDetail(at: index), "", "index=\(index)")
                XCTAssertEqual(viewModel.alarmPenaltyString(at: index), "", "index=\(index)")
                XCTAssertEqual(viewModel.alarmDaysCaps(at: index), "", "index=\(index)")
                XCTAssertEqual(viewModel.alarmPriceText(at: index), "", "index=\(index)")
                XCTAssertNil(viewModel.alarmMultiplierText(at: index), "index=\(index)")
                XCTAssertNil(viewModel.alarmSoundName(at: index), "index=\(index)")
            }
        }
    }

    func testFirstAndLastRowsRemainReadable() {
        let alarms = fixtureAlarms()
        let viewModel = makeViewModel(alarms: alarms)
        for index in [0, alarms.count - 1] {
            XCTAssertFalse(viewModel.alarmTimeString(at: index).isEmpty)
            XCTAssertEqual(
                viewModel.alarmDetail(at: index),
                "\(alarms[index].name) \u{2022} \(alarms[index].repeatDaysDescription)"
            )
            XCTAssertFalse(viewModel.alarmPenaltyString(at: index).isEmpty)
            XCTAssertFalse(viewModel.alarmDaysCaps(at: index).isEmpty)
            XCTAssertFalse(viewModel.alarmPriceText(at: index).isEmpty)
            XCTAssertEqual(viewModel.alarmSoundName(at: index), alarms[index].soundID)
        }
        XCTAssertEqual(viewModel.alarmMultiplierText(at: 0), "×2")
        XCTAssertNil(viewModel.alarmMultiplierText(at: alarms.count - 1))
    }

    func testInvalidDeleteDoesNotChangeSnapshotStorageOrScheduling() {
        for alarms in [[], fixtureAlarms()] {
            let viewModel = makeViewModel(alarms: alarms)
            let cancelledBefore = scheduler.cancelledIDs
            for index in [Int.min, -1, alarms.count, Int.max] {
                viewModel.deleteAlarm(at: index)
                XCTAssertEqual(viewModel.alarms, alarms)
                XCTAssertEqual(repository.fetchAllOrFail(), alarms)
                XCTAssertEqual(scheduler.cancelledIDs, cancelledBefore)
            }
        }
    }

    func testDeletingLastThenFirstRemovesTheIntendedAlarms() {
        let alarms = fixtureAlarms()
        let viewModel = makeViewModel(alarms: alarms)
        let cancelledBefore = scheduler.cancelledIDs
        viewModel.deleteAlarm(at: alarms.count - 1)
        XCTAssertEqual(viewModel.alarms, [alarms[0]])
        XCTAssertEqual(repository.fetchAllOrFail(), [alarms[0]])

        viewModel.deleteAlarm(at: 0)
        XCTAssertTrue(viewModel.alarms.isEmpty)
        XCTAssertTrue(repository.fetchAllOrFail().isEmpty)
        XCTAssertEqual(scheduler.cancelledIDs, cancelledBefore + [alarms[1].id, alarms[0].id])
    }

    private func fixtureAlarms() -> [Alarm] {
        [
            Alarm(name: "First", soundID: "unknown-first", progressiveScale: true, enabled: false),
            Alarm(name: "Last", soundID: "unknown-last", progressiveScale: false, enabled: false)
        ]
    }

    private func makeViewModel(alarms: [Alarm]) -> AlarmsListViewModel {
        for alarm in alarms {
            XCTAssertTrue(repository.save(alarm))
        }
        let center = NotificationCenter()
        let transactions = TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
        let balance = BalanceService(
            defaults: defaults, transactionRepository: transactions, notificationCenter: center
        )
        let viewModel = AlarmsListViewModel(
            alarmRepository: repository, balanceService: balance,
            transactionRepository: transactions, notificationCenter: center,
            alarmDefaults: AlarmDefaults(defaults: defaults)
        )
        viewModel.loadData()
        return viewModel
    }
}
