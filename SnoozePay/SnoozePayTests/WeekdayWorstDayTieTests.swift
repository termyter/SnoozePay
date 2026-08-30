import XCTest
@testable import SnoozePay

/// Tie resolution for the "По дням недели" chart's worst day.
///
/// The highlight used to come from `firstIndex(of: maxValue)`, so when two
/// weekdays shared the highest average the pain tint went to whichever the
/// array reached first — the screenshot in #636 shows Чт and Сб both at 0,5
/// with only Чт red. The chart was showing the user a difference that did not
/// exist in the data.
///
/// The rule chosen is: highlight EVERY day at a non-zero maximum. Highlighting
/// none would hide a real finding; picking the earliest or latest would still
/// be an arbitrary rule the chart has no way to communicate.
final class WeekdayWorstDayTieTests: XCTestCase {

    // MARK: - The reported case

    /// Monday-first averages straight from the issue: Пн 0,2 · Чт 0,5 · Сб 0,5.
    func testTiedDaysAreBothHighlighted() {
        let averages = [0.2, 0, 0, 0.5, 0, 0.5, 0]

        XCTAssertEqual(StatisticsViewModel.worstIndices(of: averages), [3, 5],
                       "Both days at the maximum must be highlighted, not just the first")
    }

    func testASingleWorstDayIsStillTheOnlyOneHighlighted() {
        let averages = [0.2, 0, 0, 0.9, 0, 0.5, 0]

        XCTAssertEqual(StatisticsViewModel.worstIndices(of: averages), [3])
    }

    /// The acceptance criterion «случай „все дни нулевые" тоже покрыт»: a clean
    /// month has no worst day, so nothing is tinted.
    func testACleanMonthHighlightsNothing() {
        XCTAssertEqual(StatisticsViewModel.worstIndices(of: Array(repeating: 0, count: 7)), [])
    }

    /// Every day equal and non-zero is a tie of seven, not "no worst day" —
    /// the user really did snooze the same amount every day.
    func testAnEvenWeekHighlightsEveryDay() {
        let averages = Array(repeating: 0.25, count: 7)

        XCTAssertEqual(StatisticsViewModel.worstIndices(of: averages), Array(0..<7))
    }

    // MARK: - The headline above the chart

    /// The headline names the worst day. On a tie it has to name all of them:
    /// picking one would reintroduce the arbitrariness in words, and the
    /// "no snoozes" fallback would be false when snoozes did happen.
    func testHeadlineNamesEveryTiedDay() {
        let headline = StatisticsViewController.weekdayHeadline(
            worstDayNames: ["четверг", "суббота"]
        ).string

        XCTAssertTrue(headline.contains("четверг"), "headline was: \(headline)")
        XCTAssertTrue(headline.contains("суббота"), "headline was: \(headline)")
        XCTAssertFalse(headline.contains("Откладываний не было"),
                       "A tie is not an empty month")
    }

    func testHeadlineNamesASingleWorstDayPlainly() {
        let headline = StatisticsViewController.weekdayHeadline(
            worstDayNames: ["среда"]
        ).string

        XCTAssertEqual(headline, "Чаще всего — среда")
    }

    func testHeadlineFallsBackWhenThereWereNoSnoozes() {
        let headline = StatisticsViewController.weekdayHeadline(worstDayNames: []).string

        XCTAssertEqual(headline, "Откладываний не было")
    }

    // MARK: - What the chart is handed

    /// End of the chain: `weekdayStats` is what the bars actually read, so the
    /// tie has to survive all the way there and not just in the helper.
    func testTiedDaysArriveAtTheChartAsTwoHighlightedBars() {
        let stats = [0.2, 0, 0, 0.5, 0, 0.5, 0].enumerated().map { index, average in
            StatisticsViewModel.WeekdayStat(
                label: "d\(index)",
                average: average,
                isWorst: Set(StatisticsViewModel.worstIndices(of: [0.2, 0, 0, 0.5, 0, 0.5, 0]))
                    .contains(index)
            )
        }

        XCTAssertEqual(stats.filter(\.isWorst).map(\.label), ["d3", "d5"])
    }
}
