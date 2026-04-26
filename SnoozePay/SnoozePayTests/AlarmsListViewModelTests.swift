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

    // MARK: - toggleAlarm(id:enabled:)

    /// Regression for issue #35: when the alarm exists in the VM's in-memory snapshot
    /// but has been deleted from the repository (e.g. via another tab/path), `setEnabled`
    /// must report failure and the VM must resync from the repo + trigger a re-bind so
    /// the optimistic switch flip in the cell rolls back.
    func testToggleAlarm_repoMissingTriggersResyncAndRebind() {
        let alarm = Alarm(penaltyAmount: 50, enabled: true)
        repo.save(alarm)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.count, 1)

        // Simulate a parallel delete that bypassed the VM (the VM still has the
        // alarm in its in-memory snapshot, but the repository no longer does).
        repo.delete(id: alarm.id)

        var rebindFired = false
        vm.onAlarmsUpdated = { rebindFired = true }

        vm.toggleAlarm(id: alarm.id, enabled: false)

        XCTAssertTrue(rebindFired, "VM must trigger a UI re-bind so the cell switch rolls back")
        XCTAssertTrue(vm.alarms.isEmpty, "VM must resync from the repository after a missing-id failure")
    }

    /// Regression for tag-based identity bug: when middle alarm is removed and the
    /// caller toggles the *first* alarm, only that alarm — resolved by id — must flip,
    /// not whichever alarm currently lives at the captured row index.
    func testToggleAlarmByID_correctAlarmTogglesAfterDelete() {
        // Three alarms with distinct times so sort order is stable: 06:00, 07:00, 08:00.
        let calendar = Calendar(identifier: .gregorian)
        let date6 = calendar.date(from: DateComponents(hour: 6, minute: 0))!
        let date7 = calendar.date(from: DateComponents(hour: 7, minute: 0))!
        let date8 = calendar.date(from: DateComponents(hour: 8, minute: 0))!

        let first = Alarm(time: date6, name: "Early", penaltyAmount: 50, enabled: true)
        let middle = Alarm(time: date7, name: "Mid", penaltyAmount: 50, enabled: true)
        let last = Alarm(time: date8, name: "Late", penaltyAmount: 50, enabled: true)
        repo.save(first)
        repo.save(middle)
        repo.save(last)

        let vm = makeViewModel()
        vm.loadData()
        XCTAssertEqual(vm.alarms.map(\.id), [first.id, middle.id, last.id])

        // Capture the first alarm's id BEFORE deletion — this is what an
        // already-configured cell would have closed over.
        let firstID = first.id

        vm.deleteAlarm(at: 1) // remove "Mid"
        XCTAssertEqual(vm.alarms.map(\.id), [first.id, last.id])

        vm.toggleAlarm(id: firstID, enabled: false)

        // Only "Early" should have flipped — "Late" stays enabled.
        let early = vm.alarms.first { $0.id == first.id }
        let late = vm.alarms.first { $0.id == last.id }
        XCTAssertEqual(early?.enabled, false, "The alarm matching the captured id must toggle")
        XCTAssertEqual(late?.enabled, true, "Sibling alarms must NOT be affected by an id-targeted toggle")
    }
}
