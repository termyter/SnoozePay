import XCTest
@testable import SnoozePay

/// Unit tests for the "ЭТА НЕДЕЛЯ" money summary and the "ВРЕМЯ ПОДЪЁМА"
/// averages added in #348 (`SPMore4.jsx` `Stats()`, artboard `27-stats`).
///
/// The aggregation maths is exercised through the pure static functions with
/// a pinned `today` (2026-01-27 — the Tuesday from the design artboard) so
/// expectations never race the wall clock; the handful of instance-level
/// tests use relative dates like the rest of the suite.
final class StatisticsMoneyAndWakeTimeTests: XCTestCase {

    /// Synchronous scheduler stub — the alarm repository only feeds the
    /// snooze price here, so scheduling outcomes are irrelevant.
    private final class StubScheduler: AlarmScheduling {
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
    private var txRepo: TransactionRepository!
    private var wakeStore: WakeEventStore!
    private var alarmRepo: AlarmRepository!

    private let calendar = StatisticsViewModel.mondayFirstCalendar

    override func setUp() {
        super.setUp()
        suiteName = "test.statsMoney.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: testDefaults)
        txRepo = TransactionRepository(defaults: testDefaults, wakeStore: wakeStore)
        alarmRepo = AlarmRepository(defaults: testDefaults, scheduler: StubScheduler())
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
            alarmRepository: alarmRepo,
            defaults: testDefaults,
            calendar: calendar
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    /// Tuesday, 27 January 2026 — the artboard's reference day. The
    /// Monday-first week it belongs to starts on 26 January.
    private var referenceToday: Date { date(2026, 1, 27) }

    private func charge(_ amount: Double, on day: Date) -> Transaction {
        Transaction(type: .charge, amount: amount, createdAt: day)
    }

    private func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    // MARK: - snoozePrice

    func testSnoozePrice_averagesEnabledAlarmsOnly() {
        let alarms = [
            Alarm(time: Date(), penaltyAmount: 50),
            Alarm(time: Date(), penaltyAmount: 150),
            Alarm(time: Date(), penaltyAmount: 1_000, enabled: false)
        ]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms), 100, accuracy: 0.0001,
            "A disabled alarm's penalty is not a price the user is exposed to")
    }

    func testSnoozePrice_allAlarmsDisabled_fallsBackToFullPool() {
        let alarms = [
            Alarm(time: Date(), penaltyAmount: 50, enabled: false),
            Alarm(time: Date(), penaltyAmount: 150, enabled: false)
        ]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms), 100, accuracy: 0.0001,
            "An approximate price beats no price when every alarm is temporarily off")
    }

    func testSnoozePrice_noAlarms_isZero() {
        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: []), 0,
            "With no alarms there is no honest number to value a clean morning at")
    }

    func testSnoozePrice_zeroPenaltyAlarmsIgnored() {
        let alarms = [
            Alarm(time: Date(), penaltyAmount: 0),
            Alarm(time: Date(), penaltyAmount: 80)
        ]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms), 80, accuracy: 0.0001,
            "A free alarm shouldn't drag the price of a snooze towards zero")
    }

    // MARK: - weekMoneyDays

    func testWeekMoneyDays_returnsSevenMondayFirstColumns() {
        let days = StatisticsViewModel.weekMoneyDays(
            today: referenceToday, charges: [], wakeDays: [], snoozePrice: 50, calendar: calendar
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.label), ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
    }

    func testWeekMoneyDays_futureDaysOfCurrentWeekCarryNoData() {
        let days = StatisticsViewModel.weekMoneyDays(
            today: referenceToday, charges: [], wakeDays: [], snoozePrice: 50, calendar: calendar
        )

        // Reference day is Tuesday — Monday + Tuesday happened, the rest hasn't.
        XCTAssertEqual(days.map(\.isPastOrToday), [true, true, false, false, false, false, false])
    }

    func testWeekMoneyDays_chargedDaySpendsAndSavesNothing() {
        let monday = date(2026, 1, 26, 7, 30)
        let days = StatisticsViewModel.weekMoneyDays(
            today: referenceToday,
            charges: [charge(50, on: monday), charge(100, on: monday)],
            wakeDays: [day(monday)],
            snoozePrice: 50,
            calendar: calendar
        )

        XCTAssertEqual(days[0].spent, 150, accuracy: 0.0001)
        XCTAssertEqual(days[0].saved, 0, accuracy: 0.0001,
            "A morning the user paid for cannot also count as saved")
    }

    func testWeekMoneyDays_cleanWakeDayIsWorthOneSnoozePrice() {
        let tuesday = date(2026, 1, 27, 6, 40)
        let days = StatisticsViewModel.weekMoneyDays(
            today: referenceToday,
            charges: [],
            wakeDays: [day(tuesday)],
            snoozePrice: 75,
            calendar: calendar
        )

        XCTAssertEqual(days[1].saved, 75, accuracy: 0.0001)
        XCTAssertEqual(days[1].spent, 0, accuracy: 0.0001)
    }

    func testWeekMoneyDays_dayWithoutWakeEventClaimsNoSavings() {
        let days = StatisticsViewModel.weekMoneyDays(
            today: referenceToday, charges: [], wakeDays: [], snoozePrice: 75, calendar: calendar
        )

        XCTAssertTrue(days.allSatisfy { $0.saved == 0 },
            "No wake event means no evidence an alarm rang — savings would be invented")
    }

    func testWeekMoneyDays_previousWeekChargesExcluded() {
        // Sunday 25 January belongs to the *previous* Monday-first week.
        let lastSunday = date(2026, 1, 25, 8, 0)
        let days = StatisticsViewModel.weekMoneyDays(
            today: referenceToday,
            charges: [charge(500, on: lastSunday)],
            wakeDays: [],
            snoozePrice: 50,
            calendar: calendar
        )

        XCTAssertEqual(days.reduce(0) { $0 + $1.spent }, 0, accuracy: 0.0001)
    }

    // MARK: - moneySummary

    func testMoneySummary_sumsColumnsAndDerivesNet() {
        let days = [
            StatisticsViewModel.WeekMoneyDay(label: "Пн", saved: 0, spent: 150, isPastOrToday: true),
            StatisticsViewModel.WeekMoneyDay(label: "Вт", saved: 50, spent: 0, isPastOrToday: true),
            StatisticsViewModel.WeekMoneyDay(label: "Ср", saved: 50, spent: 0, isPastOrToday: true)
        ]

        let summary = StatisticsViewModel.moneySummary(days: days)

        XCTAssertEqual(summary.saved, 100, accuracy: 0.0001)
        XCTAssertEqual(summary.spent, 150, accuracy: 0.0001)
        XCTAssertEqual(summary.net, -50, accuracy: 0.0001, "A bad week is allowed to go negative")
        XCTAssertFalse(summary.isEmpty)
    }

    func testMoneySummary_singleCleanDay() {
        let days = [
            StatisticsViewModel.WeekMoneyDay(label: "Пн", saved: 50, spent: 0, isPastOrToday: true)
        ]

        let summary = StatisticsViewModel.moneySummary(days: days)

        XCTAssertEqual(summary.saved, 50, accuracy: 0.0001)
        XCTAssertEqual(summary.net, 50, accuracy: 0.0001)
    }

    func testMoneySummary_noDataIsFlaggedEmpty() {
        let days = (0..<7).map {
            StatisticsViewModel.WeekMoneyDay(
                label: StatisticsViewModel.weekdayShortLabels[$0],
                saved: 0, spent: 0, isPastOrToday: $0 < 2
            )
        }

        XCTAssertTrue(StatisticsViewModel.moneySummary(days: days).isEmpty,
            "An all-zero week must render its own copy, not a +0 ₽ triplet")
    }

    // MARK: - wakeTimeStats

    func testWakeTimeStats_noWakeTimes_isNil() {
        XCTAssertNil(StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: [], calendar: calendar
        ))
    }

    func testWakeTimeStats_legacyDayOnlyHistory_isNil() {
        // Wakes older than the recent window (the shape a pre-#348 install
        // ends up with once its day-granular history ages out).
        let times = [date(2025, 11, 1, 7, 0), date(2025, 11, 2, 7, 0)]

        XCTAssertNil(StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: times, calendar: calendar
        ))
    }

    func testWakeTimeStats_averagesRecentWindow() {
        let times = [
            date(2026, 1, 26, 7, 0),
            date(2026, 1, 27, 6, 30)
        ]

        let stats = StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: times, calendar: calendar
        )

        XCTAssertEqual(stats?.averageMinutes, 6 * 60 + 45, "Mean of 7:00 and 6:30 is 6:45")
        XCTAssertNil(stats?.baselineMinutes, "No wakes in the preceding window")
        XCTAssertNil(stats?.deltaMinutes)
    }

    func testWakeTimeStats_singleDayStillProducesAnAverage() {
        let stats = StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: [date(2026, 1, 27, 5, 5)], calendar: calendar
        )

        XCTAssertEqual(stats?.averageMinutes, 5 * 60 + 5)
    }

    func testWakeTimeStats_gettingUpEarlier_positiveDelta() {
        let times = [
            // Baseline window (2026-01-01 … 2026-01-13) — 7:30.
            date(2026, 1, 5, 7, 30),
            date(2026, 1, 6, 7, 30),
            // Recent window (2026-01-14 … 2026-01-27) — 7:00.
            date(2026, 1, 20, 7, 0),
            date(2026, 1, 21, 7, 0)
        ]

        let stats = StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: times, calendar: calendar
        )

        XCTAssertEqual(stats?.averageMinutes, 7 * 60)
        XCTAssertEqual(stats?.baselineMinutes, 7 * 60 + 30)
        XCTAssertEqual(stats?.deltaMinutes, 30, "Positive delta = the user now gets up earlier")
    }

    func testWakeTimeStats_slippingLater_negativeDelta() {
        let times = [
            date(2026, 1, 5, 6, 0),
            date(2026, 1, 20, 6, 45)
        ]

        let stats = StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: times, calendar: calendar
        )

        XCTAssertEqual(stats?.deltaMinutes, -45)
    }

    func testWakeTimeStats_flatComparison_zeroDelta() {
        let times = [date(2026, 1, 5, 6, 30), date(2026, 1, 20, 6, 30)]

        let stats = StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: times, calendar: calendar
        )

        XCTAssertEqual(stats?.deltaMinutes, 0)
    }

    func testFirstWakePerDay_keepsTheEarliestInstant() {
        let early = date(2026, 1, 27, 6, 10)
        let nap = date(2026, 1, 27, 9, 40)

        let first = StatisticsViewModel.firstWakePerDay(times: [nap, early], calendar: calendar)

        XCTAssertEqual(first[day(early)], early, "A later nap is not the morning's подъём")
    }

    func testWakeTimeStats_windowBoundaryIsInclusiveOfToday() {
        let stats = StatisticsViewModel.wakeTimeStats(
            today: referenceToday,
            // 14 days back inclusive → 2026-01-14 is the first recent day.
            wakeTimes: [date(2026, 1, 14, 8, 0), date(2026, 1, 13, 6, 0)],
            calendar: calendar
        )

        XCTAssertEqual(stats?.averageMinutes, 8 * 60, "2026-01-14 belongs to the recent window")
        XCTAssertEqual(stats?.baselineMinutes, 6 * 60, "2026-01-13 belongs to the baseline")
    }

    // MARK: - Presentation strings

    func testClockText_padsMinutes() {
        XCTAssertEqual(StatisticsViewModel.clockText(minutes: 7 * 60 + 4), "7:04")
        XCTAssertEqual(StatisticsViewModel.clockText(minutes: 0), "0:00")
        XCTAssertEqual(StatisticsViewModel.clockText(minutes: 23 * 60 + 59), "23:59")
    }

    func testWakeDeltaCopy_reflectsDirection() {
        XCTAssertEqual(StatisticsViewModel.wakeDeltaCaption(minutes: 34), "Раньше на")
        XCTAssertEqual(StatisticsViewModel.wakeDeltaCaption(minutes: -12), "Позже на")
        XCTAssertEqual(StatisticsViewModel.wakeDeltaCaption(minutes: 0), "Без изменений")
        XCTAssertEqual(StatisticsViewModel.wakeDeltaValueText(minutes: 34), "34 мин")
        XCTAssertEqual(StatisticsViewModel.wakeDeltaValueText(minutes: -12), "12 мин")
        XCTAssertEqual(StatisticsViewModel.wakeDeltaValueText(minutes: 0), "—")
    }

    func testSignedMoneyText_usesTypographicMinus() {
        XCTAssertTrue(StatisticsViewModel.signedMoneyText(800).hasPrefix("+800"))
        XCTAssertTrue(StatisticsViewModel.signedMoneyText(-400).hasPrefix("−400"),
            "Design copy uses U+2212, not a hyphen")
        XCTAssertFalse(StatisticsViewModel.signedMoneyText(0).contains("+"))
    }

    // MARK: - Instance wiring

    func testLoadData_populatesSnoozePriceFromAlarms() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 120))

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.snoozePrice, 120, accuracy: 0.0001)
    }

    func testLoadData_readsWakeTimestamps() {
        wakeStore.recordWake(on: Date(), calendar: calendar)

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.wakeTimes.count, 1)
        XCTAssertNotNil(vm.wakeTimeStats, "A recorded instant is enough for the average")
    }

    func testWeekMoneySummary_excludesRefundedCharges() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        let refunded = Transaction(type: .charge, amount: 300, createdAt: Date())
        txRepo.record(refunded)
        txRepo.record(Transaction(
            type: .topup, amount: 300, createdAt: Date(), refundsTransactionID: refunded.id
        ))

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.weekMoneySummary.spent, 0, accuracy: 0.0001,
            "A snooze refunded after a scheduler failure never cost the user anything")
    }

    func testWeekMoneySummary_topUpsNeverCountAsSpending() {
        txRepo.record(Transaction(type: .topup, amount: 1_000, createdAt: Date()))
        txRepo.record(Transaction(type: .promotion, amount: 200, createdAt: Date()))

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.weekMoneySummary.spent, 0, accuracy: 0.0001)
    }

    // MARK: - WakeEventStore timestamps (#348)

    func testWakeStore_recordsExactInstantAlongsideTheDay() {
        let instant = date(2026, 1, 27, 6, 42)
        wakeStore.recordWake(on: instant, calendar: calendar)

        XCTAssertEqual(wakeStore.wakeTimes(), [instant])
        XCTAssertEqual(wakeStore.wakeDays(), [day(instant)], "Legacy day granularity is preserved")
    }

    func testWakeStore_repeatDismissalSameDayKeepsFirstInstant() {
        let morning = date(2026, 1, 27, 6, 42)
        let nap = date(2026, 1, 27, 9, 10)
        wakeStore.recordWake(on: morning, calendar: calendar)
        wakeStore.recordWake(on: nap, calendar: calendar)

        XCTAssertEqual(wakeStore.wakeTimes(), [morning])
    }

    func testWakeStore_timesAreSortedAscending() {
        let later = date(2026, 1, 27, 6, 42)
        let earlier = date(2026, 1, 26, 7, 5)
        wakeStore.recordWake(on: later, calendar: calendar)
        wakeStore.recordWake(on: earlier, calendar: calendar)

        XCTAssertEqual(wakeStore.wakeTimes(), [earlier, later])
    }
}
