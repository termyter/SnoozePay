import XCTest
@testable import SnoozePay

/// Unit tests for the `Money` value type — invariants, arithmetic, formatting,
/// and Codable round-trip.
final class MoneyTests: XCTestCase {

    // MARK: - Construction & invariants

    func testZeroIsValidAndZero() {
        XCTAssertEqual(Money.zero.amount, 0)
        XCTAssertEqual(Money.zero, Money(Decimal(0))!)
    }

    func testValidPositiveDecimal() {
        let money = Money(Decimal(150))
        XCTAssertNotNil(money)
        XCTAssertEqual(money?.amount, 150)
    }

    func testNegativeDecimalRejected() {
        XCTAssertNil(Money(Decimal(-1)))
        XCTAssertNil(Money(Decimal(-0.01)))
    }

    func testNaNDecimalRejected() {
        XCTAssertNil(Money(Decimal.nan))
    }

    func testNegativeDoubleRejected() {
        XCTAssertNil(Money(-1.0))
        XCTAssertNil(Money(-0.0001))
    }

    func testNaNDoubleRejected() {
        XCTAssertNil(Money(Double.nan))
    }

    func testInfiniteDoubleRejected() {
        XCTAssertNil(Money(Double.infinity))
        XCTAssertNil(Money(-Double.infinity))
    }

    func testNegativeIntRejected() {
        XCTAssertNil(Money(-5))
    }

    // MARK: - Arithmetic

    func testAdditionExact() {
        // The classic 0.1 + 0.2 case — Decimal must be exact, unlike Double.
        let lhs = Money(Decimal(string: "0.1")!)!
        let rhs = Money(Decimal(string: "0.2")!)!
        let expected = Money(Decimal(string: "0.3")!)!
        XCTAssertEqual(lhs + rhs, expected)
    }

    func testSubtractionWithinRange() {
        let lhs = Money(100)!
        let rhs = Money(30)!
        XCTAssertEqual(lhs - rhs, Money(70)!)
    }

    func testSubtractionUnderflowReturnsNil() {
        let lhs = Money(50)!
        let rhs = Money(75)!
        XCTAssertNil(lhs - rhs, "Subtraction below zero must return nil, not a negative Money")
    }

    func testMultipliedByPositive() {
        let base = Money(50)!
        XCTAssertEqual(base.multiplied(by: 4)?.amount, 200)
    }

    func testMultipliedByNegativeRejected() {
        let base = Money(50)!
        XCTAssertNil(base.multiplied(by: -1))
    }

    // MARK: - Ordering

    func testOrdering() {
        let small = Money(10)!
        let large = Money(100)!
        XCTAssertTrue(small < large)
        XCTAssertTrue(large > small)
        XCTAssertTrue(small <= small)
        XCTAssertTrue(small >= small)
    }

    // MARK: - Equality

    func testEqualityFromDifferentSources() {
        // Constructed from Int and Decimal must compare equal when amounts match.
        XCTAssertEqual(Money(100)!, Money(Decimal(100))!)
    }

    // MARK: - Bridging to Double

    func testToDoubleRoundTrip() {
        let money = Money(149)!
        XCTAssertEqual(money.toDouble(), 149)
    }

    // MARK: - Formatting

    func testFormattedRussianRubles() {
        let formatted = Money(150)!.formatted()
        // The exact glyph for ruble + spacing is locale-specific; assert
        // on the parts that matter rather than the whole string.
        XCTAssertTrue(formatted.contains("150"), "Formatted output should contain the amount: \(formatted)")
        XCTAssertTrue(formatted.contains("₽"), "Formatted output should contain the ruble sign: \(formatted)")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = Money(Decimal(string: "12345.67")!)!
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Money.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
