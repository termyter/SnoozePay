import UIKit
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

    // MARK: - A median that is not a time of day (#657)

    /// Every oracle below is anchored on `lastMinuteOfDay`, **observed** from a
    /// healthy run of the real aggregation rather than written down as 1439.
    /// A hand-derived constant agrees with any mistake in the boundary it is
    /// meant to pin.
    private func lastMinuteOfDay() -> Int? {
        stats(for: wakes(count: 5, at: 23, minute: 59, endingDaysBefore: 0))?.medianMinutes
    }

    /// The clamp lives in the formatter and stays there — 1500 minutes must
    /// render as neither "25:00" nor next-day "1:00". This test exists to say
    /// so out loud, because the next one turns on it.
    func testClockText_stillClampsAnOutOfDayOffsetToTheLastMinute() {
        guard let lastMinute = lastMinuteOfDay() else {
            return XCTFail("Five 23:59 mornings should publish a median")
        }

        XCTAssertEqual(
            StatisticsViewModel.clockText(minutes: 25 * 60),
            StatisticsViewModel.clockText(minutes: lastMinute),
            "The formatter clamps — that is its job, and why the statistic must not lean on it"
        )
    }

    /// …and precisely because the clamped reading is indistinguishable from a
    /// genuine 23:59, the statistic refuses the value instead of borrowing it.
    func testWakeTimeStats_medianPastMidnightIsDropped_notClampedToAPlausibleTime() {
        guard let lastMinute = lastMinuteOfDay() else {
            return XCTFail("Five 23:59 mornings should publish a median")
        }

        let refused = StatisticsViewModel.WakeTimeStats(
            medianMinutes: lastMinute + 1,
            baselineMedianMinutes: nil,
            recentSampleCount: 5,
            minimumSamples: 5
        )

        XCTAssertNil(refused.medianMinutes, "One minute past the day is not a wake time")
        XCTAssertTrue(refused.hasNothingToShow, "…so the host drops the whole card")
        XCTAssertFalse(refused.isAccumulating, "The window is full — history is not what's missing")
    }

    func testWakeTimeStats_negativeMedianIsDropped() {
        let refused = StatisticsViewModel.WakeTimeStats(
            medianMinutes: -1, baselineMedianMinutes: nil, recentSampleCount: 5, minimumSamples: 5
        )

        XCTAssertNil(refused.medianMinutes)
    }

    /// The recent median survives an unusable baseline: only the comparison
    /// goes, exactly as it does when the baseline window is merely short.
    func testWakeTimeStats_outOfDayBaselineDropsOnlyTheComparison() {
        let healthy = stats(
            for: wakes(count: 5, at: 7, endingDaysBefore: 0)
                + wakes(count: 5, at: 6, endingDaysBefore: 14)
        )
        guard let healthy, let median = healthy.medianMinutes, let lastMinute = lastMinuteOfDay() else {
            return XCTFail("Two full windows should publish both figures")
        }
        XCTAssertNotNil(healthy.deltaMinutes, "Baseline: the comparison is there to lose")

        let refused = StatisticsViewModel.WakeTimeStats(
            medianMinutes: median,
            baselineMedianMinutes: lastMinute + 1,
            recentSampleCount: healthy.recentSampleCount,
            minimumSamples: healthy.minimumSamples
        )

        XCTAssertEqual(refused.medianMinutes, median, "The headline is unaffected")
        XCTAssertNil(refused.baselineMedianMinutes)
        XCTAssertNil(refused.deltaMinutes, "No baseline, no «раньше на»")
        XCTAssertFalse(refused.hasNothingToShow, "The card still has a median to show")
    }

    /// A genuinely short window keeps saying it is accumulating — the fix must
    /// not swallow state 2 along with the bad one.
    func testWakeTimeStats_shortWindowStillReadsAsAccumulating() {
        let result = stats(for: wakes(count: 4, at: 7, endingDaysBefore: 0))

        XCTAssertEqual(result?.isAccumulating, true)
        XCTAssertEqual(result?.hasNothingToShow, false)
    }

    /// The hole the first cut of #657 left open: a refused median in a
    /// window that is ALSO short.
    ///
    /// `isAccumulating` was `medianMinutes == nil && recentSampleCount <
    /// minimumSamples`, and a refused median satisfies both — so the card
    /// offered to keep counting mornings towards a figure it had already
    /// decided it would never print, which is the reclassification the whole
    /// issue is about, one window shorter. Unreachable today only because
    /// `medianMinuteOfDay` returns nil below the threshold; the guard exists
    /// for the CONTRACT, so the contract is what gets tested.
    func testWakeTimeStats_refusedMedianInAShortWindowIsNotAccumulating() {
        let honest = StatisticsViewModel.WakeTimeStats(
            medianMinutes: nil, baselineMedianMinutes: nil, recentSampleCount: 3, minimumSamples: 5
        )
        XCTAssertTrue(
            honest.isAccumulating,
            "Baseline: three mornings and no median really is short history"
        )

        let refused = StatisticsViewModel.WakeTimeStats(
            medianMinutes: 25 * 60,
            baselineMedianMinutes: nil,
            recentSampleCount: 3,
            minimumSamples: 5
        )
        XCTAssertFalse(
            refused.isAccumulating,
            "A refused median must not be re-told as «keep counting mornings»"
        )
        XCTAssertTrue(
            refused.hasNothingToShow,
            "Nothing to publish and nothing honest to promise — the host hides the card"
        )
    }

    /// Both sides share a `nil` median, and before `medianWasRefused` became
    /// a stored property they compared equal — so a snapshot or an equality
    /// assertion could not tell «we threw a value away» from «there was
    /// nothing».
    func testWakeTimeStats_aRefusedMedianIsNotEqualToAnHonestAbsence() {
        let refused = StatisticsViewModel.WakeTimeStats(
            medianMinutes: 25 * 60,
            baselineMedianMinutes: nil,
            recentSampleCount: 5,
            minimumSamples: 5
        )
        let absent = StatisticsViewModel.WakeTimeStats(
            medianMinutes: nil, baselineMedianMinutes: nil, recentSampleCount: 5, minimumSamples: 5
        )

        XCTAssertNil(refused.medianMinutes, "Precondition: the value really was dropped")
        XCTAssertNotEqual(refused, absent)
    }
    /// The card's copy, compared against the copy it shows in the healthy
    /// short-history case rather than against a string typed here.
    func testWakeTimeCard_refusedMedianShowsNoCopyRatherThanZeroMornings() {
        let card = SPWakeTimeCard()

        let accumulating = StatisticsViewModel.WakeTimeStats(
            medianMinutes: nil, baselineMedianMinutes: nil, recentSampleCount: 1, minimumSamples: 5
        )
        card.apply(accumulating)
        card.layoutIfNeeded()
        let accumulatingCopy = Self.visibleStrings(in: card)
        XCTAssertTrue(
            accumulatingCopy.contains(StatisticsViewModel.wakeSamplesPendingText(4)),
            "Baseline: a short window explains itself — «\(accumulatingCopy)»"
        )

        let refused = StatisticsViewModel.WakeTimeStats(
            medianMinutes: 25 * 60,
            baselineMedianMinutes: nil,
            recentSampleCount: 5,
            minimumSamples: 5
        )
        card.apply(refused)
        card.layoutIfNeeded()
        let refusedCopy = Self.visibleStrings(in: card)

        XCTAssertFalse(
            refusedCopy.contains(StatisticsViewModel.wakeSamplesPendingText(0)),
            "«нужно ещё 0 утр» is the copy this state would have invented"
        )
        let clamped = StatisticsViewModel.clockText(minutes: 25 * 60)
        XCTAssertFalse(
            refusedCopy.contains(clamped), "A clamped «\(clamped)» must not reach the screen"
        )
    }

    /// Text a reader would actually see: hidden branches are skipped, because
    /// `UILabel.text` outlives the state that set it.
    private static func visibleStrings(in view: UIView) -> [String] {
        guard !view.isHidden else { return [] }
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        return found + view.subviews.flatMap { visibleStrings(in: $0) }
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
