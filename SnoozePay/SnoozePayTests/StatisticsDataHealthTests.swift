import XCTest
@testable import SnoozePay

/// Tests for the honesty gates on the "ЭТА НЕДЕЛЯ" card (#348 + its review
/// and verification rounds).
///
/// The screen makes a *money* claim, so every degraded input has to resolve
/// to one of three outcomes, never to a plausible-looking number:
///   1. Ledger unreadable / partially read → figures withheld, and the card
///      says which failure it hit (it must not silently disappear).
///   2. Snooze price unresolvable → "—" plus the reason, and the reason
///      distinguishes "no priced alarm" from "alarm store damaged".
///   3. A legitimate zero → printed, with a sentence so it doesn't read as a
///      rendering bug.
final class StatisticsDataHealthTests: XCTestCase {

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
        suiteName = "test.statsHealth.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: testDefaults)
        txRepo = TransactionRepository(defaults: testDefaults, wakeStore: wakeStore)
        alarmRepo = AlarmRepository(defaults: testDefaults, scheduler: StubScheduler())
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeVM() -> StatisticsViewModel {
        StatisticsViewModel(
            repository: txRepo,
            wakeStore: wakeStore,
            alarmRepository: alarmRepo,
            defaults: testDefaults,
            calendar: calendar
        )
    }

    // MARK: - Ledger health gating (#348 review, finding 1)

    /// A corrupt ledger surfaces an alert, but `wakeDays` survives it. Without
    /// the health gate every morning looked "clean" and the card invented
    /// savings out of a blob it never read.
    func testLoadData_corruptLedger_suppressesMoneySummary() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        for daysAgo in 0..<3 {
            wakeStore.recordWake(
                on: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!,
                calendar: calendar
            )
        }
        testDefaults.set(Data("not json".utf8), forKey: "stored_transactions")

        let viewModel = makeVM()
        var surfacedError = false
        viewModel.onLoadError = { _ in surfacedError = true }
        viewModel.loadData()

        XCTAssertTrue(surfacedError)
        XCTAssertEqual(viewModel.moneyUnavailableReason, .ledgerUnreadable)
        XCTAssertTrue(viewModel.weekMoneySummary.isEmpty,
            "No money statement may be built on a ledger we couldn't read")
        XCTAssertNil(viewModel.weekMoneySummary.saved)
        XCTAssertTrue(viewModel.weekMoneyDays.allSatisfy { $0.saved == nil })
    }

    /// A readable wake store must not turn a broken transaction ledger into a
    /// plausible behavioural success story. This test would fail if the
    /// `guard ledgerReadable` in `recomputeSnapshots(today:)` were removed:
    /// the recorded wake would otherwise yield a `.woke` heatmap cell.
    func testLoadData_corruptLedger_withWakeHistory_withholdsAllBehaviouralAggregates() {
        let today = Date()
        wakeStore.recordWake(on: today, calendar: calendar)
        testDefaults.set(Data("not json".utf8), forKey: "stored_transactions")

        let viewModel = makeVM()
        viewModel.loadData()

        XCTAssertFalse(viewModel.ledgerReadable)
        XCTAssertTrue(viewModel.heatmapDays.isEmpty)
        XCTAssertTrue(viewModel.weekdayStats.isEmpty)
        XCTAssertNil(viewModel.worstWeekdayName)
        XCTAssertTrue(viewModel.weeklyTrend.isEmpty)
        XCTAssertEqual(viewModel.trendDiff, 0)
        XCTAssertEqual(viewModel.thisWeekCount, 0)
    }

    /// Since #453 an unrecognised `type` token decodes to `.unknown` instead
    /// of throwing: no alert fires, rows silently drop out of every aggregate,
    /// and "Сэкономили" grows by exactly the days whose charges vanished.
    func testLoadData_unrecognizedTransactionType_suppressesMoneySummary() throws {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        wakeStore.recordWake(on: Date(), calendar: calendar)
        let ledger = [Transaction(type: .unknown("teleport"), amount: 50, createdAt: Date())]
        testDefaults.set(try JSONEncoder().encode(ledger), forKey: "stored_transactions")

        let viewModel = makeVM()
        var surfacedError = false
        viewModel.onLoadError = { _ in surfacedError = true }
        viewModel.loadData()

        XCTAssertFalse(surfacedError, "A tolerated token doesn't throw — that's the danger")
        XCTAssertEqual(viewModel.moneyUnavailableReason, .ledgerPartiallyRead)
        XCTAssertTrue(viewModel.weekMoneySummary.isEmpty)
        XCTAssertTrue(viewModel.weekMoneyDays.isEmpty)
        XCTAssertTrue(viewModel.heatmapDays.isEmpty,
            "A partial ledger must not turn the surviving wake into a clean heatmap cell")
        XCTAssertTrue(viewModel.weekdayStats.isEmpty)
        XCTAssertNil(viewModel.worstWeekdayName)
        XCTAssertTrue(viewModel.weeklyTrend.isEmpty)
        XCTAssertEqual(viewModel.trendDiff, 0)
    }

    /// The two ledger failures must stay distinguishable: the card prints a
    /// different sentence for each, and for the partial read that sentence is
    /// the only signal the user gets at all (#348 verification, finding 3).
    func testMoneyUnavailableReason_carriesDistinctUserFacingCopy() {
        let unreadable = StatisticsViewModel.MoneyUnavailableReason.ledgerUnreadable.message
        let partial = StatisticsViewModel.MoneyUnavailableReason.ledgerPartiallyRead.message

        XCTAssertFalse(unreadable.isEmpty)
        XCTAssertFalse(partial.isEmpty)
        XCTAssertNotEqual(unreadable, partial,
            "A partial read and a dead blob are different problems")
    }

    func testLoadData_healthyLedger_keepsMoneySummary() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 50))
        wakeStore.recordWake(on: Date(), calendar: calendar)

        let viewModel = makeVM()
        viewModel.loadData()

        XCTAssertNil(viewModel.moneyUnavailableReason)
        XCTAssertFalse(viewModel.weekMoneySummary.isEmpty)
        XCTAssertEqual(viewModel.weekMoneySummary.saved!, 50, accuracy: 0.0001)
        XCTAssertNil(viewModel.savingsNote, "A priced, readable week needs no explanation")
    }

    // MARK: - Snooze-price diagnosis (#348 verification, finding 4)

    /// Regression for #348 review finding 5: `stored_alarms` and
    /// `stored_transactions` are independent blobs, so a broken alarm store
    /// raises no ledger banner — the price must degrade to "unknown", not to
    /// a silent zero.
    func testLoadData_corruptAlarmStore_leavesPriceUnknown() {
        wakeStore.recordWake(on: Date(), calendar: calendar)
        testDefaults.set(Data("not json".utf8), forKey: "stored_alarms")

        let viewModel = makeVM()
        viewModel.loadData()

        XCTAssertNil(viewModel.snoozePrice, "An unreadable alarm store gives no honest price")
        XCTAssertTrue(viewModel.weekMoneySummary.savingsUnavailable)
        XCTAssertNil(viewModel.weekMoneySummary.saved)
    }

    /// "Your alarm store is damaged" and "you have no priced alarm" need
    /// different captions: telling the first user to go set a price sends them
    /// to edit an alarm that is already priced.
    func testLoadData_corruptAlarmStore_isDiagnosedSeparatelyFromNoAlarms() {
        wakeStore.recordWake(on: Date(), calendar: calendar)
        testDefaults.set(Data("not json".utf8), forKey: "stored_alarms")

        let corrupt = makeVM()
        corrupt.loadData()

        XCTAssertEqual(corrupt.snoozePriceState, .alarmStoreUnreadable)
        let corruptNote = corrupt.savingsNote
        XCTAssertNotNil(corruptNote)

        // Same screen state, different cause: no alarms at all.
        testDefaults.removeObject(forKey: "stored_alarms")
        let empty = makeVM()
        empty.loadData()

        XCTAssertEqual(empty.snoozePriceState, .noPricedAlarms)
        XCTAssertNotNil(empty.savingsNote)
        XCTAssertNotEqual(corruptNote, empty.savingsNote,
            "A damaged store must not be reported as 'set a snooze price'")
    }

    /// A legitimate zero still prints, but with a sentence explaining it —
    /// otherwise "Сэкономили 0 ₽ · Потратили 0 ₽ · Чистый 0 ₽" on a week of
    /// confirmed wakes reads as a broken screen
    /// (#348 verification, finding 5).
    func testLoadData_freeAlarms_publishZeroWithAnExplanation() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 0))
        wakeStore.recordWake(on: Date(), calendar: calendar)

        let viewModel = makeVM()
        viewModel.loadData()

        XCTAssertEqual(viewModel.snoozePriceState, .known(0))
        XCTAssertEqual(viewModel.weekMoneySummary.saved!, 0, accuracy: 0.0001)
        XCTAssertFalse(viewModel.weekMoneySummary.isEmpty, "A confirmed wake is data")
        XCTAssertNotNil(viewModel.savingsNote,
            "A zero triplet without a reason is indistinguishable from a bug")
    }

    /// …but a week with nothing in it shows the empty copy, not the
    /// free-alarm explanation.
    func testLoadData_freeAlarmsButNoWakes_staysEmptyWithoutANote() {
        alarmRepo.save(Alarm(time: Date(), penaltyAmount: 0))

        let viewModel = makeVM()
        viewModel.loadData()

        XCTAssertTrue(viewModel.weekMoneySummary.isEmpty)
        XCTAssertNil(viewModel.savingsNote)
    }
}
