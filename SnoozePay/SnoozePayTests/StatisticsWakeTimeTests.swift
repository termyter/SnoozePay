import XCTest
@testable import SnoozePay

/// Unit tests for the "ВРЕМЯ ПОДЪЁМА" figures (#348) and the wake-instant
/// storage that feeds them.
///
/// Two rules decided at review (PM, 2026-07-30) drive most of these:
///   1. **Median, not mean** — one 00:30 dismissal must not move the headline.
///   2. **At least five mornings per window** — below that no figure is
///      published at all; the card says it's still accumulating.
///
/// `today` is pinned to 2026-01-27 (the artboard's Tuesday) so the 14-day
/// windows never race the wall clock.
final class StatisticsWakeTimeTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var wakeStore: WakeEventStore!

    private let calendar = StatisticsViewModel.mondayFirstCalendar

    override func setUp() {
        super.setUp()
        suiteName = "test.statsWake.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private var referenceToday: Date { date(2026, 1, 27) }

    private func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Wake instants for `count` consecutive days, the most recent of them
    /// `endingDaysBefore` days before `referenceToday`, all at one wall time.
    private func wakes(
        count: Int,
        at hour: Int,
        minute: Int = 0,
        endingDaysBefore: Int
    ) -> [Date] {
        (0..<count).compactMap { offset in
            let dayStart = calendar.date(
                byAdding: .day, value: -(endingDaysBefore + offset), to: day(referenceToday)
            )
            return dayStart.flatMap {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: $0)
            }
        }
    }

    private func stats(for times: [Date]) -> StatisticsViewModel.WakeTimeStats? {
        StatisticsViewModel.wakeTimeStats(
            today: referenceToday, wakeTimes: times, calendar: calendar
        )
    }

    // MARK: - Card is omitted entirely

    func testWakeTimeStats_noWakeTimes_isNil() {
        XCTAssertNil(stats(for: []))
    }

    /// A pre-#348 install has day-granular history only, so `wakeTimes()`
    /// returns nothing at all and the card is omitted.
    func testWakeTimeStats_installWithoutRecordedInstants_isNil() {
        XCTAssertTrue(wakeStore.wakeTimes().isEmpty)
        XCTAssertNil(stats(for: wakeStore.wakeTimes()))
    }

    func testWakeTimeStats_wakesOlderThanBothWindows_isNil() {
        XCTAssertNil(stats(for: [date(2025, 11, 1, 7, 0), date(2025, 11, 2, 7, 0)]))
    }

    // MARK: - Sampling threshold

    /// Was `testWakeTimeStats_singleDayStillProducesAnAverage`, which pinned
    /// the very behaviour the review rejected: one morning is not a habit.
    func testWakeTimeStats_singleMorning_reportsNoMedianYet() {
        let result = stats(for: [date(2026, 1, 27, 5, 5)])

        XCTAssertNotNil(result, "The card still appears — it explains it's accumulating")
        XCTAssertNil(result?.medianMinutes, "One morning can't establish a typical wake time")
        XCTAssertEqual(result?.recentSampleCount, 1)
        XCTAssertEqual(result?.samplesUntilReady, 4)
    }

    func testWakeTimeStats_belowThreshold_reportsNoMedianYet() {
        let result = stats(for: wakes(count: 4, at: 7, endingDaysBefore: 0))

        XCTAssertNil(result?.medianMinutes, "Four mornings is still below the five-morning floor")
        XCTAssertEqual(result?.samplesUntilReady, 1)
    }

    func testWakeTimeStats_atThreshold_publishesMedian() {
        let result = stats(for: wakes(count: 5, at: 7, endingDaysBefore: 0))

        XCTAssertEqual(result?.medianMinutes, 7 * 60)
        XCTAssertEqual(result?.recentSampleCount, 5)
        XCTAssertEqual(result?.samplesUntilReady, 0)
    }

    func testWakeTimeStats_baselineBelowThreshold_dropsComparison() {
        // 5 recent mornings, only 2 in the baseline window.
        let times = wakes(count: 5, at: 7, endingDaysBefore: 0)
            + wakes(count: 2, at: 8, endingDaysBefore: 14)

        let result = stats(for: times)

        XCTAssertEqual(result?.medianMinutes, 7 * 60)
        XCTAssertNil(result?.baselineMedianMinutes, "Two mornings can't anchor a 'раньше было'")
        XCTAssertNil(result?.deltaMinutes)
    }

    // MARK: - Median semantics

    /// The headline reason for the median: one 00:30 dismissal among a dozen
    /// 07:00 mornings used to drag the mean by ~28 minutes.
    func testWakeTimeStats_medianResistsSingleOutlier() {
        let outlierDay = calendar.date(byAdding: .day, value: -12, to: day(referenceToday))!
        var times = wakes(count: 12, at: 7, endingDaysBefore: 0)
        times.append(calendar.date(bySettingHour: 0, minute: 30, second: 0, of: outlierDay)!)

        XCTAssertEqual(stats(for: times)?.medianMinutes, 7 * 60,
            "A single 00:30 morning must not move the typical wake time at all")
    }

    func testMedianMinuteOfDay_evenCount_averagesTheTwoMiddleValues() {
        let times = [
            date(2026, 1, 20, 6, 0), date(2026, 1, 21, 6, 30),
            date(2026, 1, 22, 7, 30), date(2026, 1, 23, 8, 0)
        ]

        XCTAssertEqual(
            StatisticsViewModel.medianMinuteOfDay(times, calendar: calendar), 7 * 60,
            "Median of 6:30 and 7:30 is 7:00"
        )
    }

    func testMedianMinuteOfDay_belowMinimum_isNil() {
        XCTAssertNil(StatisticsViewModel.medianMinuteOfDay(
            [date(2026, 1, 20, 6, 0)], calendar: calendar, minimumSamples: 5
        ))
    }

    // MARK: - Comparison against the previous window

    func testWakeTimeStats_gettingUpEarlier_positiveDelta() {
        let times = wakes(count: 6, at: 7, endingDaysBefore: 0)
            + wakes(count: 6, at: 7, minute: 30, endingDaysBefore: 14)

        let result = stats(for: times)

        XCTAssertEqual(result?.medianMinutes, 7 * 60)
        XCTAssertEqual(result?.baselineMedianMinutes, 7 * 60 + 30)
        XCTAssertEqual(result?.deltaMinutes, 30, "Positive delta = the user now gets up earlier")
    }

    func testWakeTimeStats_slippingLater_negativeDelta() {
        let times = wakes(count: 6, at: 6, minute: 45, endingDaysBefore: 0)
            + wakes(count: 6, at: 6, endingDaysBefore: 14)

        XCTAssertEqual(stats(for: times)?.deltaMinutes, -45)
    }

    func testWakeTimeStats_flatComparison_zeroDelta() {
        let times = wakes(count: 6, at: 6, minute: 30, endingDaysBefore: 0)
            + wakes(count: 6, at: 6, minute: 30, endingDaysBefore: 14)

        XCTAssertEqual(stats(for: times)?.deltaMinutes, 0)
    }

    func testWakeTimeStats_windowBoundaryIsInclusiveOfToday() {
        // 5 mornings ending exactly on the first recent day (2026-01-14),
        // 5 more entirely inside the baseline window.
        let times = wakes(count: 5, at: 8, endingDaysBefore: 9)
            + wakes(count: 5, at: 6, endingDaysBefore: 14)

        let result = stats(for: times)

        XCTAssertEqual(result?.medianMinutes, 8 * 60, "2026-01-14 belongs to the recent window")
        XCTAssertEqual(result?.baselineMedianMinutes, 6 * 60, "2026-01-13 belongs to the baseline")
    }

    func testFirstWakePerDay_keepsTheEarliestInstant() {
        let early = date(2026, 1, 27, 6, 10)
        let nap = date(2026, 1, 27, 9, 40)

        let first = StatisticsViewModel.firstWakePerDay(times: [nap, early], calendar: calendar)

        XCTAssertEqual(first[day(early)], early, "A later nap is not the morning's подъём")
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

    func testWakeSamplesPendingText_declinesTheRussianNoun() {
        XCTAssertEqual(
            StatisticsViewModel.wakeSamplesPendingText(1), "Копим историю: нужно ещё 1 утро"
        )
        XCTAssertEqual(
            StatisticsViewModel.wakeSamplesPendingText(3), "Копим историю: нужно ещё 3 утра"
        )
        XCTAssertEqual(
            StatisticsViewModel.wakeSamplesPendingText(5), "Копим историю: нужно ещё 5 утр"
        )
    }

    // MARK: - WakeEventStore timestamps

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

    func testLoadData_readsWakeTimestamps() {
        wakeStore.recordWake(on: Date(), calendar: calendar)
        let viewModel = StatisticsViewModel(
            repository: TransactionRepository(defaults: testDefaults, wakeStore: wakeStore),
            wakeStore: wakeStore,
            defaults: testDefaults,
            calendar: calendar
        )

        viewModel.loadData()

        XCTAssertEqual(viewModel.wakeTimes.count, 1)
        XCTAssertNotNil(viewModel.wakeTimeStats, "One instant is enough for the card to appear…")
        XCTAssertNil(viewModel.wakeTimeStats?.medianMinutes, "…but not enough to publish a median")
    }
}
