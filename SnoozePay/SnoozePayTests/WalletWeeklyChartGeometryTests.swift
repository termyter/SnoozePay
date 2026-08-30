import XCTest
@testable import SnoozePay

/// Bar geometry for the Wallet "Последние 7 дней" chart.
///
/// The chart used ONE floor for both cases: a day with no penalties and a day
/// whose penalty was small relative to the week both resolved to 4pt, leaving
/// red-against-grey as the only difference between "nothing happened" and "you
/// were charged". #635 split the floors; these tests pin the split so a later
/// tidy-up that merges the two constants back fails here instead of on screen.
final class WalletWeeklyChartGeometryTests: XCTestCase {

    /// The exact case from #635: a −50 ₽ Monday inside a week whose worst day
    /// is −650 ₽. Intensity is 50/650 ≈ 0.077, which the linear mapping puts at
    /// ~3pt — below the floor, and previously indistinguishable from an empty
    /// day.
    private let smallPenaltyIntensity = CGFloat(50.0 / 650.0)

    func testEmptyDayIsShorterThanTheSmallestChargedDay() {
        let empty = WalletWeeklyChartView.barHeight(forIntensity: 0)
        let charged = WalletWeeklyChartView.barHeight(forIntensity: smallPenaltyIntensity)

        XCTAssertLessThan(empty, charged,
                          "A day with no spending must not render at the same height as one with spending")
    }

    /// Not merely "different" — different enough to survive a glance. Anything
    /// under a couple of points reads as a rendering artefact, not a signal.
    func testEmptyAndChargedDaysDifferByAVisibleMargin() {
        let empty = WalletWeeklyChartView.barHeight(forIntensity: 0)
        let charged = WalletWeeklyChartView.barHeight(forIntensity: smallPenaltyIntensity)

        XCTAssertGreaterThanOrEqual(charged - empty, 4,
                                    "Height difference should be legible, not a hairline")
    }

    /// The fix moved the CLAMP, not the scale. Values tall enough to clear the
    /// floor must keep the height they had before #635 — this is the acceptance
    /// criterion "пропорции ненулевых значений не изменились".
    func testProportionsAboveTheFloorAreUnchanged() {
        let maxHeight = WalletWeeklyChartView.maxBarHeight

        for ratio in [CGFloat(0.5), 0.75, 1.0] {
            XCTAssertEqual(WalletWeeklyChartView.barHeight(forIntensity: ratio),
                           maxHeight * ratio,
                           accuracy: 0.001,
                           "Intensity \(ratio) must map linearly, untouched by the floor")
        }
    }

    func testFullIntensityFillsTheAvailableHeight() {
        XCTAssertEqual(WalletWeeklyChartView.barHeight(forIntensity: 1),
                       WalletWeeklyChartView.maxBarHeight,
                       accuracy: 0.001)
    }

    /// A week with no spending at all: every day is empty, and none of them may
    /// borrow the data floor and pretend a charge happened.
    func testAllZeroWeekRendersEveryDayAsAnEmptyTrack() {
        let empty = WalletWeeklyChartView.barHeight(forIntensity: 0)

        XCTAssertLessThan(empty, WalletWeeklyChartView.barHeight(forIntensity: 0.0001),
                          "Zero must be the only intensity that gets the empty track")
    }

    /// Guards against a caller handing in a ratio outside `0...1` (a stale max,
    /// a negative amount): the bar must stay inside the plot area rather than
    /// overflowing the card.
    func testIntensityIsClampedToThePlotArea() {
        XCTAssertEqual(WalletWeeklyChartView.barHeight(forIntensity: 4),
                       WalletWeeklyChartView.maxBarHeight,
                       accuracy: 0.001)
        XCTAssertEqual(WalletWeeklyChartView.barHeight(forIntensity: -2),
                       WalletWeeklyChartView.barHeight(forIntensity: 0),
                       accuracy: 0.001,
                       "A negative intensity is no data, not inverted data")
    }
}
