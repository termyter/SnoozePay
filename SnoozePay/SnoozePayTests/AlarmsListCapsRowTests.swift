import XCTest
@testable import SnoozePay

/// Caps-row matrix tests for the alarms-list day label (#289).
///
/// Covers `AlarmsListViewModel.weekdayPhrase(for:repeatMode:)` across the
/// weekly × never recurrence and empty × weekday-set axes — the key being
/// that a one-shot (`.never`) alarm with days set renders a distinct
/// "Единожды · …" phrase rather than the weekly grouping aliases
/// ("Будни · Пн–Пт" / "Выходные" / "Каждый день").
final class AlarmsListCapsRowTests: XCTestCase {

    /// No-op scheduler so `repo.save` never reaches `UNUserNotificationCenter`.
    private final class NoopScheduler: AlarmScheduling {
        func schedule(
            _ alarm: Alarm,
            completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?
        ) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.capsRow.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: testDefaults, scheduler: NoopScheduler())
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - weekdayPhrase matrix (pure)

    func testWeekly_weekdaySet_groupsAsBudni() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: [0, 1, 2, 3, 4], repeatMode: .weekly),
            "Будни · Пн–Пт"
        )
    }

    func testWeekly_weekendSet_groupsAsVyhodnye() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: [5, 6], repeatMode: .weekly),
            "Выходные"
        )
    }

    func testWeekly_fullWeek_groupsAsEveryDay() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: Array(0...6), repeatMode: .weekly),
            "Каждый день"
        )
    }

    func testWeekly_arbitrarySet_listsDays() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: [1, 3], repeatMode: .weekly),
            "Вт, Чт"
        )
    }

    func testWeekly_emptyDays_isEdinozhdy() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: [], repeatMode: .weekly),
            "Единожды"
        )
    }

    func testNever_weekdaySet_prefixedEdinozhdy_notBudni() {
        // The crux of #289 — a one-shot with the Mon–Fri set must NOT collapse
        // into the weekly "Будни · Пн–Пт" alias.
        let phrase = AlarmsListViewModel.weekdayPhrase(for: [0, 1, 2, 3, 4], repeatMode: .never)
        XCTAssertEqual(phrase, "Единожды · Пн, Вт, Ср, Чт, Пт")
        XCTAssertFalse(phrase.contains("Будни"))
    }

    func testNever_weekendSet_prefixedEdinozhdy_notVyhodnye() {
        let phrase = AlarmsListViewModel.weekdayPhrase(for: [5, 6], repeatMode: .never)
        XCTAssertEqual(phrase, "Единожды · Сб, Вс")
        XCTAssertFalse(phrase.contains("Выходные"))
    }

    func testNever_fullWeek_prefixedEdinozhdy_notEveryDay() {
        let phrase = AlarmsListViewModel.weekdayPhrase(for: Array(0...6), repeatMode: .never)
        XCTAssertEqual(phrase, "Единожды · Пн, Вт, Ср, Чт, Пт, Сб, Вс")
        XCTAssertFalse(phrase.contains("Каждый день"))
    }

    func testNever_arbitrarySet_prefixedEdinozhdy() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: [1, 3], repeatMode: .never),
            "Единожды · Вт, Чт"
        )
    }

    func testNever_emptyDays_isEdinozhdy() {
        XCTAssertEqual(
            AlarmsListViewModel.weekdayPhrase(for: [], repeatMode: .never),
            "Единожды"
        )
    }

    // MARK: - alarmDaysCaps through the view model

    func testCapsRow_weeklyWeekdays_upperCased() {
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], penaltyAmount: 50, repeatMode: .weekly)
        repo.save(alarm)
        let vm = AlarmsListViewModel(alarmRepository: repo, balanceService: .shared)
        vm.loadData()
        XCTAssertEqual(vm.alarmDaysCaps(at: 0), "БУДНИ · ПН–ПТ")
    }

    func testCapsRow_oneShotWeekdays_distinctFromWeekly() {
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], penaltyAmount: 50, repeatMode: .never)
        repo.save(alarm)
        let vm = AlarmsListViewModel(alarmRepository: repo, balanceService: .shared)
        vm.loadData()
        let caps = vm.alarmDaysCaps(at: 0)
        XCTAssertEqual(caps, "ЕДИНОЖДЫ · ПН, ВТ, СР, ЧТ, ПТ")
        XCTAssertFalse(caps.contains("БУДНИ"))
    }

    func testCapsRow_oneShotNoDays_isEdinozhdy() {
        let alarm = Alarm(repeatDays: [], penaltyAmount: 50, repeatMode: .never)
        repo.save(alarm)
        let vm = AlarmsListViewModel(alarmRepository: repo, balanceService: .shared)
        vm.loadData()
        XCTAssertEqual(vm.alarmDaysCaps(at: 0), "ЕДИНОЖДЫ")
    }

    func testCapsRow_namedOneShot_prefixesName() {
        let alarm = Alarm(repeatDays: [1, 3], name: "Спорт", penaltyAmount: 50, repeatMode: .never)
        repo.save(alarm)
        let vm = AlarmsListViewModel(alarmRepository: repo, balanceService: .shared)
        vm.loadData()
        XCTAssertEqual(vm.alarmDaysCaps(at: 0), "СПОРТ · ЕДИНОЖДЫ · ВТ, ЧТ")
    }
}
