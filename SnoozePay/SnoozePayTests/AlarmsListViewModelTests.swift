import XCTest
@testable import SnoozePay

/// Unit tests for AlarmsListViewModel helper methods — detail and penalty formatting.
final class AlarmsListViewModelTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test.alarmsList.\(UUID().uuidString)")!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        if let name = testDefaults.suiteName {
            UserDefaults.removePersistentDomain(forName: name)
        }
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
}
