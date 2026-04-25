import XCTest
@testable import SnoozePay

/// Unit tests for AlarmsListViewModel helper methods — detail and penalty formatting.
final class AlarmsListViewModelTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmsList.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeViewModel() -> AlarmsListViewModel {
        AlarmsListViewModel(alarmRepository: repo, balanceService: .shared)
    }

    // MARK: - alarmDetail(at:)

    func testAlarmDetail_withNameAndDays() {
        // Weekdays Mon-Fri (0-4) should display as "Будни"
        let alarm = Alarm(
            repeatDays: [0, 1, 2, 3, 4],
            name: "Работа",
            penaltyAmount: 50
        )
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let detail = vm.alarmDetail(at: 0)
        XCTAssertEqual(detail, "Работа \u{2022} Будни")
    }

    func testAlarmDetail_withNameNoDays() {
        // No repeat days should display as "Единожды"
        let alarm = Alarm(
            repeatDays: [],
            name: "Утро",
            penaltyAmount: 100
        )
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let detail = vm.alarmDetail(at: 0)
        XCTAssertEqual(detail, "Утро \u{2022} Единожды")
    }

    // MARK: - alarmPenaltyString(at:)

    func testAlarmPenaltyString_format() {
        let alarm = Alarm(penaltyAmount: 50)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let penalty = vm.alarmPenaltyString(at: 0)
        XCTAssertEqual(penalty, "▲ ОТЛОЖИТЬ: 50 ₽")
    }

    func testAlarmPenaltyString_highPenalty() {
        let alarm = Alarm(penaltyAmount: 1000)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        let penalty = vm.alarmPenaltyString(at: 0)
        XCTAssertEqual(penalty, "▲ ОТЛОЖИТЬ: 1000 ₽")
    }

    // MARK: - Safe index handling

    func testAlarmTimeString_emptyAlarmsReturnsEmptyString() {
        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarmTimeString(at: 0), "")
        XCTAssertEqual(vm.alarmSubtitle(at: 0), "")
    }

    func testFormattedBalance_containsRubleSign() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.formattedBalance.contains("₽"))
    }

    // MARK: - toggleAlarm(at:enabled:)

    func testToggleAlarm_updatesInMemoryState() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertTrue(vm.alarms[0].enabled)

        vm.toggleAlarm(at: 0, enabled: false)
        XCTAssertFalse(vm.alarms[0].enabled, "In-memory alarm must reflect the new enabled state immediately")
    }

    func testToggleAlarm_persistsToRepository() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()

        vm.toggleAlarm(at: 0, enabled: false)
        let stored = repo.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertFalse(stored[0].enabled, "Toggle must persist through the repository")
    }
}
