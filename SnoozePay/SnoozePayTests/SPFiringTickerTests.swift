import XCTest
@testable import SnoozePay

/// Tests for the firing history ticker model (#288). The ticker renders today's
/// snooze charges as coloured mini-pills — amber below 200 ₽, red at or above
/// 200 ₽ — so the amount → tint mapping is pure logic worth pinning.
final class SPFiringTickerTests: XCTestCase {

    func testEntries_roundPenaltiesToInt() {
        let entries = SPFiringTicker.entries(from: [50, 100.4, 199.6])
        XCTAssertEqual(entries.map(\.amount), [50, 100, 200])
    }

    func testEntries_emptyForNoHistory() {
        XCTAssertTrue(SPFiringTicker.entries(from: []).isEmpty)
    }

    func testEntry_isLightBelowTwoHundred() {
        let entry = SPFiringTicker.Entry(amount: 199)
        XCTAssertFalse(entry.isHeavy)
        XCTAssertEqual(entry.textColor, AppColors.warn300,
                       "Charges under 200 ₽ render amber")
    }

    func testEntry_isHeavyAtTwoHundred() {
        let entry = SPFiringTicker.Entry(amount: 200)
        XCTAssertTrue(entry.isHeavy, "200 ₽ is the heavy threshold (≥ 200)")
        XCTAssertEqual(entry.textColor, AppColors.pain300,
                       "Charges at or above 200 ₽ render red")
    }

    func testEntry_isHeavyAboveTwoHundred() {
        XCTAssertTrue(SPFiringTicker.Entry(amount: 400).isHeavy)
    }

    func testMakeRow_hiddenWhenEmpty() {
        let row = SPFiringTicker.makeRow(for: [])
        XCTAssertTrue(row.isHidden, "No history → the ticker row stays hidden")
    }

    func testMakeRow_visibleWithEntries() {
        let row = SPFiringTicker.makeRow(for: [SPFiringTicker.Entry(amount: 50)])
        XCTAssertFalse(row.isHidden)
        XCTAssertFalse(row.arrangedSubviews.isEmpty,
                       "A non-empty ticker mounts the «СЕГОДНЯ» eyebrow + chips")
    }
}
