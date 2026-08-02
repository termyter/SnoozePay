import XCTest
@testable import SnoozePay

/// Unit tests for the "ЭТА НЕДЕЛЯ" money summary and the "ВРЕМЯ ПОДЪЁМА"
/// figures added in #348 (`SPMore4.jsx` `Stats()`, artboard `27-stats`).
///
/// The aggregation maths is exercised through the pure static functions with
/// a pinned `today` (2026-01-27 — the Tuesday from the design artboard) so
/// expectations never race the wall clock; the instance-level tests use
/// relative dates like the rest of the suite.
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

    /// Sunday, 1 February 2026 — the last day of that same week, used to
    /// prove the seventh column is reachable.
    private var referenceSunday: Date { date(2026, 2, 1) }

    private func charge(_ amount: Double, on day: Date) -> Transaction {
        Transaction(type: .charge, amount: amount, createdAt: day)
    }

    private func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    private func weekDays(
        today: Date,
        inputs: StatisticsViewModel.MoneyInputs
    ) -> [StatisticsViewModel.WeekMoneyDay] {
        StatisticsViewModel.weekMoneyDays(today: today, inputs: inputs, calendar: calendar)
    }

    private func makeDay(
        _ label: String,
        saved: Double? = nil,
        spent: Double = 0,
        isCleanWake: Bool = false,
        isPastOrToday: Bool = true
    ) -> StatisticsViewModel.WeekMoneyDay {
        StatisticsViewModel.WeekMoneyDay(
            label: label,
            saved: saved,
            spent: spent,
            isCleanWake: isCleanWake,
            isPastOrToday: isPastOrToday
        )
    }

    // MARK: - snoozePrice (canonical formula, PM decision 2026-07-30)

    func testSnoozePrice_averagesEnabledAlarmsOnly() {
        let alarms = [
            Alarm(time: Date(), penaltyAmount: 50),
            Alarm(time: Date(), penaltyAmount: 150),
            Alarm(time: Date(), penaltyAmount: 1_000, enabled: false)
        ]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms)!, 100, accuracy: 0.0001,
            "A disabled alarm's penalty is not a price the user is exposed to")
    }

    func testSnoozePrice_allAlarmsDisabled_fallsBackToFullPool() {
        let alarms = [
            Alarm(time: Date(), penaltyAmount: 50, enabled: false),
            Alarm(time: Date(), penaltyAmount: 150, enabled: false)
        ]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms)!, 100, accuracy: 0.0001,
            "An approximate price beats no price when every alarm is temporarily off")
    }

    func testSnoozePrice_noAlarms_isNilNotZero() {
        XCTAssertNil(StatisticsViewModel.snoozePrice(alarms: []),
            "No alarms means the price is unknown — not that a clean morning saved 0 ₽")
    }

    /// Regression for #348 review finding 4: zero-penalty alarms used to be
    /// filtered out of the mean, so a clean morning under a free alarm was
    /// valued at the price of the user's *other* alarm.
    func testSnoozePrice_freeAlarmsCountTowardsTheMean() {
        let alarms = [
            Alarm(time: Date(), penaltyAmount: 0),
            Alarm(time: Date(), penaltyAmount: 80)
        ]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms)!, 40, accuracy: 0.0001,
            "A free alarm's counterfactual is 0 ₽ and must drag the mean down")
    }

    func testSnoozePrice_allAlarmsFree_isZeroNotNil() {
        let alarms = [Alarm(time: Date(), penaltyAmount: 0)]

        XCTAssertEqual(StatisticsViewModel.snoozePrice(alarms: alarms), 0,
            "A known price of zero is a fact, distinct from an unknown price")
    }

    /// The shared entry point #347 will adopt for the streak banner + modal.
    func testSavingsEstimate_sharedEntryPoint() {
        let alarms = [Alarm(time: Date(), penaltyAmount: 50), Alarm(time: Date(), penaltyAmount: 150)]

        XCTAssertEqual(
            StatisticsViewModel.SavingsEstimate.saved(cleanDays: 3, alarms: alarms)!,
            300, accuracy: 0.0001
        )
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.saved(cleanDays: 3, alarms: []),
            "Unknown price must propagate, not collapse to 0 ₽")
        XCTAssertEqual(
            StatisticsViewModel.SavingsEstimate.saved(cleanDays: -2, price: 50), 0,
            accuracy: 0.0001, "Negative day counts can't produce negative savings"
        )
    }

    func testSavingsEstimateUsesEnabledAlarmPricesForEveryDisplaySurface() {
        let enabled = Alarm(time: Date(), penaltyAmount: 200, enabled: true)
        let disabled = Alarm(time: Date(), penaltyAmount: 20, enabled: false)

        XCTAssertEqual(
            StatisticsViewModel.SavingsEstimate.savedDisplayAmount(
                cleanDays: 7,
                alarms: [enabled, disabled]
            ),
            1400,
            "Every surface must price clean mornings from currently enabled alarms only"
        )
    }

    func testSavingsEstimateDisplayAmountHidesUnknownAndZeroSavings() {
        let free = Alarm(time: Date(), penaltyAmount: 0)

        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 7, alarms: []))
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 7, alarms: [free]))
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 0, price: 50))
    }

    // MARK: - weekMoneyDays

    func testWeekMoneyDays_returnsSevenMondayFirstColumns() {
        let days = weekDays(today: referenceToday, inputs: .init(snoozePrice: 50))

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.label), ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
    }

    func testWeekMoneyDays_futureDaysOfCurrentWeekCarryNoData() {
        let days = weekDays(today: referenceToday, inputs: .init(snoozePrice: 50))

        // Reference day is Tuesday — Monday + Tuesday happened, the rest hasn't.
        XCTAssertEqual(days.map(\.isPastOrToday), [true, true, false, false, false, false, false])
    }

    /// Sunday is the seventh Monday-first column; on the last day of the week
    /// every column must be in the past.
    func testWeekMoneyDays_onSunday_allSevenColumnsArePast() {
        let days = weekDays(today: referenceSunday, inputs: .init(snoozePrice: 50))

        XCTAssertEqual(days.filter(\.isPastOrToday).count, 7)
        XCTAssertEqual(days.last?.label, "Вс")
    }

    func testWeekMoneyDays_sundayWakeIsCredited() {
        let sunday = date(2026, 2, 1, 8, 0)
        let days = weekDays(
            today: referenceSunday,
            inputs: .init(wakeDays: [day(sunday)], snoozePrice: 60)
        )

        XCTAssertEqual(days[6].saved, 60)
        XCTAssertTrue(days[6].isCleanWake)
    }

    func testWeekMoneyDays_chargedDaySpendsAndSavesNothing() {
        let monday = date(2026, 1, 26, 7, 30)
        let days = weekDays(
            today: referenceToday,
            inputs: .init(
                charges: [charge(50, on: monday), charge(100, on: monday)],
                wakeDays: [day(monday)],
                attemptedSnoozeDays: [day(monday)],
                snoozePrice: 50
            )
        )

        XCTAssertEqual(days[0].spent, 150, accuracy: 0.0001)
        XCTAssertNil(days[0].saved, "A morning the user paid for cannot also count as saved")
        XCTAssertFalse(days[0].isCleanWake)
    }

    func testWeekMoneyDays_cleanWakeDayIsWorthOneSnoozePrice() {
        let tuesday = date(2026, 1, 27, 6, 40)
        let days = weekDays(
            today: referenceToday,
            inputs: .init(wakeDays: [day(tuesday)], snoozePrice: 75)
        )

        XCTAssertEqual(days[1].saved, 75)
        XCTAssertEqual(days[1].spent, 0, accuracy: 0.0001)
    }

    /// Regression for #348 review finding 3: the user pressed snooze, the
    /// scheduler refused (#130) and the charge was rolled back. `realCharges`
    /// rightly drops it, but the morning must not flip to "сэкономили".
    func testWeekMoneyDays_rolledBackSnoozeAttemptIsNotSaved() {
        let monday = date(2026, 1, 26, 7, 30)
        let days = weekDays(
            today: referenceToday,
            inputs: .init(
                // `charges` is post-`realCharges`, so the refunded row is gone …
                charges: [],
                wakeDays: [day(monday)],
                // … but the attempt is still on record.
                attemptedSnoozeDays: [day(monday)],
                snoozePrice: 100
            )
        )

        XCTAssertNil(days[0].saved, "The user pressed snooze — they didn't resist")
        XCTAssertFalse(days[0].isCleanWake)
        XCTAssertEqual(days[0].spent, 0, accuracy: 0.0001, "…but the refund means they paid nothing")
    }

    func testWeekMoneyDays_dayWithoutWakeEventClaimsNoSavings() {
        let days = weekDays(today: referenceToday, inputs: .init(snoozePrice: 75))

        XCTAssertTrue(days.allSatisfy { $0.saved == nil },
            "No wake event means no evidence an alarm rang — savings would be invented")
    }

    func testWeekMoneyDays_unknownPriceKeepsDayCleanButUnpriced() {
        let tuesday = date(2026, 1, 27, 6, 40)
        let days = weekDays(
            today: referenceToday,
            inputs: .init(wakeDays: [day(tuesday)], snoozePrice: nil)
        )

        XCTAssertTrue(days[1].isCleanWake, "The morning still happened…")
        XCTAssertNil(days[1].saved, "…we just can't put a number on it")
    }

    func testWeekMoneyDays_previousWeekChargesExcluded() {
        // Sunday 25 January belongs to the *previous* Monday-first week.
        let lastSunday = date(2026, 1, 25, 8, 0)
        let days = weekDays(
            today: referenceToday,
            inputs: .init(charges: [charge(500, on: lastSunday)], snoozePrice: 50)
        )

        XCTAssertEqual(days.reduce(0) { $0 + $1.spent }, 0, accuracy: 0.0001)
    }

    // MARK: - moneySummary

    func testMoneySummary_sumsColumnsAndDerivesNet() {
        let days = [
            makeDay("Пн", spent: 150),
            makeDay("Вт", saved: 50, isCleanWake: true),
            makeDay("Ср", saved: 50, isCleanWake: true)
        ]

        let summary = StatisticsViewModel.moneySummary(days: days)

        XCTAssertEqual(summary.saved!, 100, accuracy: 0.0001)
        XCTAssertEqual(summary.spent, 150, accuracy: 0.0001)
        XCTAssertEqual(summary.net!, -50, accuracy: 0.0001, "A bad week is allowed to go negative")
        XCTAssertFalse(summary.isEmpty)
        XCTAssertFalse(summary.savingsUnavailable)
    }

    func testMoneySummary_singleCleanDay() {
        let summary = StatisticsViewModel.moneySummary(
            days: [makeDay("Пн", saved: 50, isCleanWake: true)]
        )

        XCTAssertEqual(summary.saved!, 50, accuracy: 0.0001)
        XCTAssertEqual(summary.net!, 50, accuracy: 0.0001)
    }

    func testMoneySummary_noDataIsFlaggedEmpty() {
        let days = (0..<7).map {
            makeDay(StatisticsViewModel.weekdayShortLabels[$0], isPastOrToday: $0 < 2)
        }

        XCTAssertTrue(StatisticsViewModel.moneySummary(days: days).isEmpty,
            "An all-zero week must render its own copy, not a +0 ₽ triplet")
    }

    /// Regression for #348 review finding 4: seven confirmed wakes under free
    /// alarms are *data*, even though the money adds up to zero.
    func testMoneySummary_freeAlarmsCleanWeek_isNotEmpty() {
        let days = (0..<7).map {
            makeDay(StatisticsViewModel.weekdayShortLabels[$0], saved: 0, isCleanWake: true)
        }

        let summary = StatisticsViewModel.moneySummary(days: days)

        XCTAssertFalse(summary.isEmpty, "Seven confirmed wakes are not 'данных пока нет'")
        XCTAssertEqual(summary.saved!, 0, accuracy: 0.0001)
        XCTAssertEqual(summary.observedDays, 7)
    }

    /// Regression for #348 review finding 4: an unknown price must not read
    /// as "you saved nothing".
    func testMoneySummary_unknownPrice_reportsUnavailableNotZero() {
        let days = [
            makeDay("Пн", saved: nil, isCleanWake: true),
            makeDay("Вт", spent: 450)
        ]

        let summary = StatisticsViewModel.moneySummary(days: days)

        XCTAssertNil(summary.saved)
        XCTAssertNil(summary.net, "Net needs both halves")
        XCTAssertEqual(summary.spent, 450, accuracy: 0.0001, "Spending stays factual")
        XCTAssertTrue(summary.savingsUnavailable)
        XCTAssertFalse(summary.isEmpty)
    }

    func testMoneySummary_pastWeekWithNoCleanDays_savedIsZeroNotUnknown() {
        let summary = StatisticsViewModel.moneySummary(days: [makeDay("Пн", spent: 100)])

        XCTAssertEqual(summary.saved!, 0, accuracy: 0.0001,
            "No clean mornings is a known zero, not an unknown")
    }

    func testSignedMoneyText_carriesSignSeparatorAndCurrency() {
        XCTAssertEqual(
            StatisticsViewModel.signedMoneyText(800), "+800\(MoneyFormatter.narrowSpace)₽",
            "Plain text must match MoneyFormatter exactly — VoiceOver reads this string"
        )
        XCTAssertEqual(
            StatisticsViewModel.signedMoneyText(-400), "−400\(MoneyFormatter.narrowSpace)₽",
            "Design copy uses U+2212, not a hyphen"
        )
        XCTAssertEqual(StatisticsViewModel.signedMoneyText(0), "0\(MoneyFormatter.narrowSpace)₽")
        XCTAssertEqual(StatisticsViewModel.signedMoneyText(nil), "—")
    }

    /// Regression for #348 review finding 2: the mono money labels must go
    /// through `MoneyFormatter.attributed`, whose separator run is re-fonted
    /// with the proportional sans so "800 ₽" isn't rendered "800  ₽".
    func testSignedMoneyAttributed_reFontsTheSeparatorRun() {
        let mono = AppTypography.moneyMd
        let attributed = StatisticsViewModel.signedMoneyAttributed(
            800, digitsFont: mono, color: AppColors.money400
        )

        XCTAssertEqual(attributed.string, "+800\(MoneyFormatter.narrowSpace)₽")
        let separatorIndex = attributed.string.distance(
            from: attributed.string.startIndex,
            to: attributed.string.firstIndex(of: Character(MoneyFormatter.narrowSpace))!
        )
        let separatorFont = attributed.attribute(
            .font, at: separatorIndex, effectiveRange: nil
        ) as? UIFont
        let digitsFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont

        XCTAssertEqual(digitsFont, mono)
        XCTAssertNotEqual(separatorFont, mono, "The gap before ₽ must not take a full mono cell")
        XCTAssertEqual(separatorFont?.pointSize, mono.pointSize)
    }

    func testSignedMoneyAttributed_unknownAmountRendersDash() {
        let attributed = StatisticsViewModel.signedMoneyAttributed(
            nil, digitsFont: AppTypography.moneyMd, color: AppColors.fg1
        )

        XCTAssertEqual(attributed.string, "—")
    }

    // MARK: - Instance wiring

    func testLoadData_populatesSnoozePriceFromAlarms() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 120))

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.snoozePrice!, 120, accuracy: 0.0001)
        XCTAssertTrue(vm.ledgerReadable)
    }

    func testLoadData_readsWakeTimestamps() {
        wakeStore.recordWake(on: Date(), calendar: calendar)

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.wakeTimes.count, 1)
        XCTAssertNotNil(vm.wakeTimeStats, "One instant is enough for the card to appear…")
        XCTAssertNil(vm.wakeTimeStats?.medianMinutes, "…but not enough to publish a median")
    }

    func testWeekMoneySummary_excludesRefundedCharges() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        let refunded = Transaction(type: .charge, amount: 300, createdAt: Date())
        txRepo.record(refunded)
        // Production books the reversal as `.refund` since #453 — not `.topup`.
        txRepo.record(Transaction(
            type: .refund, amount: 300, createdAt: Date(), refundsTransactionID: refunded.id
        ))

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.weekMoneySummary.spent, 0, accuracy: 0.0001,
            "A snooze refunded after a scheduler failure never cost the user anything")
    }

    /// End-to-end guard for the rolled-back-snooze rule through `loadData`.
    ///
    /// The wake event is the whole point: without it `cleanDays` is empty and
    /// `saved` comes out 0 via the "no clean mornings" branch regardless of
    /// what `attemptedSnoozeDays` holds — which is exactly why the previous
    /// version of this assertion proved nothing. With a wake recorded, the
    /// morning is clean on every axis *except* the rolled-back attempt, so the
    /// 50 ₽ only stays off the total if `attemptedSnoozeDays` is populated and
    /// consulted.
    func testLoadData_rolledBackSnoozeOnAWokenMorning_isNotCountedAsSaved() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        let today = Date()
        wakeStore.recordWake(on: today, calendar: calendar)
        let refunded = Transaction(type: .charge, amount: 50, createdAt: today)
        txRepo.record(refunded)
        txRepo.record(Transaction(
            type: .refund, amount: 50, createdAt: today, refundsTransactionID: refunded.id
        ))

        let vm = makeVM()
        vm.loadData()

        XCTAssertTrue(vm.attemptedSnoozeDays.contains(day(today)),
            "loadData must record the attempt even though the charge was rolled back")
        XCTAssertEqual(vm.snoozePrice!, 50, accuracy: 0.0001)
        XCTAssertEqual(vm.weekMoneySummary.spent, 0, accuracy: 0.0001,
            "The refund means the morning cost nothing…")
        XCTAssertEqual(vm.weekMoneySummary.saved!, 0, accuracy: 0.0001,
            "…but the user pressed snooze, so it saved nothing either")
        XCTAssertEqual(vm.weekMoneySummary.observedDays, 0,
            "A rolled-back attempt is neither a clean morning nor a spend")
        let todayColumn = vm.weekMoneyDays.first { $0.isPastOrToday && $0.isCleanWake }
        XCTAssertNil(todayColumn, "No column may be marked clean on an attempted-snooze day")
    }

    /// Control for the test above: the identical fixture *without* the
    /// rolled-back attempt does credit the morning. Together the pair pins the
    /// attempt — not the wake event or the price — as the deciding input.
    func testLoadData_wokenMorningWithoutAnyAttempt_isCountedAsSaved() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        wakeStore.recordWake(on: Date(), calendar: calendar)

        let vm = makeVM()
        vm.loadData()

        XCTAssertTrue(vm.attemptedSnoozeDays.isEmpty)
        XCTAssertEqual(vm.weekMoneySummary.saved!, 50, accuracy: 0.0001)
        XCTAssertEqual(vm.weekMoneySummary.observedDays, 1)
    }

    func testWeekMoneySummary_topUpsNeverCountAsSpending() {
        txRepo.record(Transaction(type: .topup, amount: 1_000, createdAt: Date()))
        txRepo.record(Transaction(type: .promotion, amount: 200, createdAt: Date()))

        let vm = makeVM()
        vm.loadData()

        XCTAssertEqual(vm.weekMoneySummary.spent, 0, accuracy: 0.0001)
    }

    /// The bars and the totals must describe the same day.
    ///
    /// Asserting `moneySummary(days: vm.weekMoneyDays) == vm.weekMoneySummary`
    /// proves nothing — it's the same expression the production code runs, and
    /// it held on the old lazy implementation too. Instead this drives two
    /// *different* days through `recomputeSnapshots(today:)` and checks
    /// both outputs moved: a stale total left over from the previous day would
    /// keep `spent` at Monday's value while the bars had already flipped.
    func testRecompute_barsAndTotalsComeFromTheSameDay() {
        let monday = date(2026, 1, 26, 7, 30)
        let nextMonday = date(2026, 2, 2, 7, 30)
        txRepo.record(charge(150, on: monday))
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))

        let vm = makeVM()
        vm.loadData()

        vm.recomputeSnapshots(today: monday)
        let mondayBars = vm.weekMoneyDays
        let mondayTotals = vm.weekMoneySummary
        XCTAssertEqual(mondayBars[0].spent, 150, accuracy: 0.0001)
        XCTAssertEqual(mondayTotals.spent, 150, accuracy: 0.0001,
            "Totals must reflect the week the bars are drawn for")

        // A week later the charge belongs to the *previous* week, so both the
        // bars and the totals have to drop it — in lockstep.
        vm.recomputeSnapshots(today: nextMonday)
        XCTAssertEqual(vm.weekMoneyDays[0].spent, 0, accuracy: 0.0001,
            "New week — the old charge is out of range for the bars")
        XCTAssertEqual(vm.weekMoneySummary.spent, 0, accuracy: 0.0001,
            "…and must be out of range for the totals too, not left stale")
        XCTAssertNotEqual(vm.weekMoneyDays, mondayBars)
        XCTAssertNotEqual(vm.weekMoneySummary, mondayTotals)
    }
}
