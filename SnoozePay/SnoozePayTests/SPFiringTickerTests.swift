import XCTest
import UIKit
@testable import SnoozePay

/// Tests for the firing history ticker model (#288). The ticker renders today's
/// snooze charges as coloured mini-pills — amber below 200 ₽, red at or above
/// 200 ₽ — so the amount → tint mapping is pure logic worth pinning.
final class SPFiringTickerTests: XCTestCase {

    func testEntries_preserveActualPenaltiesAndCurrency() {
        let entries = SPFiringTicker.entries(from: [50, 100.4, 199.6], currency: .rub)
        XCTAssertEqual(entries.map(\.amount), [50, 100.4, 199.6])
        XCTAssertTrue(entries.allSatisfy { $0.currency == .rub })
        XCTAssertTrue(entries[2].isHeavy, "Retain the previous rounded threshold")
    }

    func testEntries_emptyForNoHistory() {
        XCTAssertTrue(SPFiringTicker.entries(from: [], currency: .rub).isEmpty)
    }

    func testEntry_isLightBelowTwoHundred() {
        let entry = SPFiringTicker.Entry(amount: 199, currency: .rub)
        XCTAssertFalse(entry.isHeavy)
        XCTAssertEqual(entry.textColor, AppColors.warn300,
                       "Charges under 200 ₽ render amber")
    }

    func testEntry_isHeavyAtTwoHundred() {
        let entry = SPFiringTicker.Entry(amount: 200, currency: .rub)
        XCTAssertTrue(entry.isHeavy, "200 ₽ is the heavy threshold (≥ 200)")
        XCTAssertEqual(entry.textColor, AppColors.pain300,
                       "Charges at or above 200 ₽ render red")
    }

    func testEntry_isHeavyAboveTwoHundred() {
        XCTAssertTrue(SPFiringTicker.Entry(amount: 400, currency: .rub).isHeavy)
    }

    func testMakeRow_hiddenWhenEmpty() {
        let row = SPFiringTicker.makeRow(for: [])
        XCTAssertTrue(row.isHidden, "No history → the ticker row stays hidden")
    }

    func testMakeRow_visibleWithEntries() {
        let row = SPFiringTicker.makeRow(for: [SPFiringTicker.Entry(amount: 50, currency: .rub)])
        XCTAssertFalse(row.isHidden)
        XCTAssertFalse(row.arrangedSubviews.isEmpty,
                       "A non-empty ticker mounts the «СЕГОДНЯ» eyebrow + chips")
    }

    func testActualChipsPreserveCurrencyFractionsAndVoiceOver() {
        for (code, amount) in [("USD", 2.99), ("EUR", 1.25), ("JPY", 299), ("KWD", 0.001), ("RUB", 49.5)] {
            let currency = Currency(code: code)!
            let entry = SPFiringTicker.Entry(amount: amount, currency: currency)
            let row = SPFiringTicker.makeRow(for: [entry])
            let labels = descendants(of: row).compactMap { $0 as? SPPaddedLabel }
            let expected = "−" + MoneyFormatter.string(amount, currency: currency)
            XCTAssertEqual(labels.map { $0.attributedText?.string }, [expected], code)
            XCTAssertEqual(labels.map { $0.accessibilityLabel }, [expected], code)
            XCTAssertEqual(entry.amount, amount)
            if code != "RUB" { XCTAssertFalse(expected.contains("₽")) }
        }
    }

    func testInvalidAndPositiveUnderflowChargesStayUnsignedUnknownWithoutNarrowing() {
        let usd = Currency(code: "USD")!
        let values = [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -1, 0.002]
        for value in values {
            let entries = SPFiringTicker.entries(from: [value], currency: usd)
            XCTAssertEqual(entries.count, 1, "Keep receipt position rather than drop it")
            let row = SPFiringTicker.makeRow(for: entries)
            let labels = descendants(of: row).compactMap { $0 as? SPPaddedLabel }
            XCTAssertEqual(labels.map { $0.attributedText?.string }, ["—"])
            XCTAssertEqual(labels.map { $0.accessibilityLabel }, ["—"])
        }
        XCTAssertEqual(SPFiringTicker.Entry(amount: 0, currency: usd).displayText,
                       "−" + MoneyFormatter.string(0.0, currency: usd))
    }

    func testLargeRepresentableChargesPreserveDigitsWithoutIntConversion() {
        let amount = Double(Int.max)
        let entry = SPFiringTicker.Entry(amount: amount, currency: .rub)
        XCTAssertEqual(entry.amount, amount)
        XCTAssertEqual(entry.displayText, "−" + MoneyFormatter.string(amount, currency: .rub))
        XCTAssertNotEqual(entry.displayText, "—")
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

}
