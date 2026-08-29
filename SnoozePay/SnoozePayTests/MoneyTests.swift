import XCTest
@testable import SnoozePay

/// Unit tests for the `Money` value type — invariants, currency safety,
/// arithmetic, formatting, and Codable round-trip (issues #31, #561).
final class MoneyTests: XCTestCase {

    private let rub = Currency.rub
    private let usd = Currency(code: "USD")!

    // MARK: - Construction & invariants

    func testZeroIsValidAndZero() {
        XCTAssertEqual(Money.zero(rub).amount, 0)
        XCTAssertEqual(Money.zero(rub), Money(Decimal(0), currency: rub)!)
    }

    func testZeroCarriesTheCurrencyItWasAskedFor() {
        XCTAssertEqual(Money.zero(usd).currency, usd)
        XCTAssertNotEqual(Money.zero(usd), Money.zero(rub),
                          "Zero dollars and zero roubles are not the same value")
    }

    func testValidPositiveDecimal() {
        let money = Money(Decimal(150), currency: rub)
        XCTAssertNotNil(money)
        XCTAssertEqual(money?.amount, 150)
        XCTAssertEqual(money?.currency, rub)
    }

    func testNegativeDecimalRejected() {
        XCTAssertNil(Money(Decimal(-1), currency: rub))
        XCTAssertNil(Money(Decimal(-0.01), currency: rub))
    }

    func testNaNDecimalRejected() {
        XCTAssertNil(Money(Decimal.nan, currency: rub))
    }

    func testNegativeDoubleRejected() {
        XCTAssertNil(Money(-1.0, currency: rub))
        XCTAssertNil(Money(-0.0001, currency: rub))
    }

    func testNaNDoubleRejected() {
        XCTAssertNil(Money(Double.nan, currency: rub))
    }

    func testInfiniteDoubleRejected() {
        XCTAssertNil(Money(Double.infinity, currency: rub))
        XCTAssertNil(Money(-Double.infinity, currency: rub))
    }

    func testNegativeIntRejected() {
        XCTAssertNil(Money(-5, currency: rub))
    }

    // MARK: - Legacy bridge

    func testLegacyBridgeDenominatesInRoubles() {
        // Everything the app persisted before #561 was roubles, and that
        // assumption must live in exactly one place.
        XCTAssertEqual(Money.legacy(150)?.currency, Currency.rub)
        XCTAssertEqual(Money.legacy(150.0)?.currency, Currency.rub)
        XCTAssertEqual(Currency.legacyDefault, .rub)
    }

    func testLegacyBridgeStillValidatesTheAmount() {
        XCTAssertNil(Money.legacy(-1))
        XCTAssertNil(Money.legacy(Double.nan))
    }

    // MARK: - Arithmetic

    func testAdditionExact() {
        // The classic 0.1 + 0.2 case — Decimal must be exact, unlike Double.
        let lhs = Money(Decimal(string: "0.1")!, currency: rub)!
        let rhs = Money(Decimal(string: "0.2")!, currency: rub)!
        let expected = Money(Decimal(string: "0.3")!, currency: rub)!
        XCTAssertEqual(lhs + rhs, expected)
    }

    func testSubtractionWithinRange() {
        let lhs = Money(100, currency: rub)!
        let rhs = Money(30, currency: rub)!
        XCTAssertEqual(lhs - rhs, Money(70, currency: rub)!)
    }

    func testSubtractionUnderflowReturnsNil() {
        let lhs = Money(50, currency: rub)!
        let rhs = Money(75, currency: rub)!
        XCTAssertNil(lhs - rhs, "Subtraction below zero must return nil, not a negative Money")
    }

    func testMultipliedByPositiveKeepsCurrency() {
        let base = Money(50, currency: usd)!
        XCTAssertEqual(base.multiplied(by: 4)?.amount, 200)
        XCTAssertEqual(base.multiplied(by: 4)?.currency, usd,
                       "A scalar has no currency of its own; the result keeps the operand's")
    }

    func testMultipliedByNegativeRejected() {
        let base = Money(50, currency: rub)!
        XCTAssertNil(base.multiplied(by: -1))
    }

    /// `Money.+` previously force-unwrapped its result with a comment claiming
    /// "non-negative + non-negative is safe". `Decimal.greatestFiniteMagnitude
    /// + Decimal.greatestFiniteMagnitude` can produce a non-finite value and
    /// trap the release build. The overflow path now returns `nil` with a fault
    /// log instead of crashing — this test pins that no real wallet path can
    /// crash the app via overflow (audit-finding #198).
    func testAdditionDoesNotCrashOnExtremeOverflow() {
        let huge = Money(Decimal.greatestFiniteMagnitude, currency: rub)!
        // What matters is that we don't trap: either Decimal absorbed it and
        // we got a valid finite result, or we got the documented `nil`.
        if let result = huge + huge {
            XCTAssertTrue(result.amount.isFinite,
                          "Overflow must not produce non-finite Money")
        }
    }

    // MARK: - Currency safety (#561)
    //
    // There is no conversion in this app — no network, no rate source (#559).
    // So every operation that could mix currencies must refuse, and refusing
    // has to be visible at the call site: a wrong number here is money.

    func testAdditionAcrossCurrenciesReturnsNil() {
        let roubles = Money(100, currency: rub)!
        let dollars = Money(100, currency: usd)!
        XCTAssertNil(roubles + dollars)
        XCTAssertNil(dollars + roubles)
    }

    func testSubtractionAcrossCurrenciesReturnsNil() {
        let roubles = Money(100, currency: rub)!
        let dollars = Money(1, currency: usd)!
        XCTAssertNil(roubles - dollars)
        XCTAssertNil(dollars - roubles)
    }

    func testOrderingAcrossCurrenciesReturnsNil() {
        let roubles = Money(100, currency: rub)!
        let dollars = Money(1, currency: usd)!
        XCTAssertNil(roubles < dollars)
        XCTAssertNil(roubles <= dollars)
        XCTAssertNil(roubles > dollars)
        XCTAssertNil(roubles >= dollars)
    }

    func testEqualityIsCurrencyAware() {
        XCTAssertNotEqual(Money(100, currency: rub)!, Money(100, currency: usd)!,
                          "Same number, different currency — not the same amount of money")
    }

    // MARK: - Ordering

    func testOrderingWithinOneCurrency() {
        let small = Money(10, currency: rub)!
        let large = Money(100, currency: rub)!
        XCTAssertEqual(small < large, true)
        XCTAssertEqual(large > small, true)
        XCTAssertEqual(small <= small, true)
        XCTAssertEqual(small >= small, true)
        XCTAssertEqual(large < small, false)
    }

    // MARK: - Equality

    func testEqualityFromDifferentSources() {
        // Constructed from Int and Decimal must compare equal when amounts match.
        XCTAssertEqual(Money(100, currency: rub)!, Money(Decimal(100), currency: rub)!)
    }

    // MARK: - Bridging to Double

    func testToDoubleRoundTrip() {
        let money = Money(149, currency: rub)!
        XCTAssertEqual(money.toDouble(), 149)
    }

    // MARK: - Formatting

    func testFormattedTakesCurrencyFromTheValueNotTheLocale() {
        let ruRU = Locale(identifier: "ru_RU")
        let roubles = Money(150, currency: rub)!.formatted(locale: ruRU)
        let dollars = Money(150, currency: usd)!.formatted(locale: ruRU)

        XCTAssertTrue(roubles.contains("150"), "Expected the amount in \(roubles)")
        XCTAssertTrue(roubles.contains("₽"), "Expected the rouble sign in \(roubles)")

        XCTAssertTrue(dollars.contains("150"), "Expected the amount in \(dollars)")
        XCTAssertFalse(dollars.contains("₽"),
                       "A dollar amount shown to a Russian-speaking user is still dollars: \(dollars)")
    }

    func testFormattedRespectsTheLocaleItIsGiven() {
        let dollarsUS = Money(150, currency: usd)!.formatted(locale: Locale(identifier: "en_US"))
        XCTAssertTrue(dollarsUS.contains("150"), "Expected the amount in \(dollarsUS)")
        XCTAssertTrue(dollarsUS.contains("$"), "Expected the dollar sign in \(dollarsUS)")
    }

    /// The money typography the user actually sees comes from `MoneyFormatter`,
    /// which this refactor deliberately did not touch. Pinned here so that a
    /// later step of #559 cannot quietly change what is on screen while
    /// claiming to be a type-level change.
    func testVisibleMoneyTypographyIsUnchanged() {
        XCTAssertEqual(MoneyFormatter.string(50), "50\u{202F}₽")
        XCTAssertEqual(MoneyFormatter.string(0), "0\u{202F}₽")
        XCTAssertEqual(MoneyFormatter.string(149), "149\u{202F}₽")
        XCTAssertEqual(MoneyFormatter.string(1234), "1\u{00A0}234\u{202F}₽")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = Money(Decimal(string: "12345.67")!, currency: usd)!
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Money.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.currency, usd)
    }

    func testEncodesCurrencyAsBareISOCode() throws {
        let data = try JSONEncoder().encode(Money(150, currency: rub)!)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"currency\":\"RUB\""),
                      "Currency should be a plain ISO code on disk, got \(json)")
    }

    /// Data written before #561 has no `currency` key. Rejecting it would not
    /// crash — `TransactionRepository` treats a decode failure as corruption and
    /// locks the whole ledger (#72) — it would silently take a user's history
    /// away. Old money is rouble money.
    func testLegacyFixtureWithoutCurrencyDecodesAsRoubles() throws {
        let legacy = Data(#"{"amount":150}"#.utf8)
        let decoded = try JSONDecoder().decode(Money.self, from: legacy)
        XCTAssertEqual(decoded.currency, Currency.rub)
        XCTAssertEqual(decoded.amount, 150)
        XCTAssertEqual(decoded, Money.legacy(150))
    }

    func testDecodingRejectsAmountsThatBreakTheInvariant() {
        let negative = Data(#"{"amount":-1,"currency":"RUB"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Money.self, from: negative))
    }

    func testDecodingRejectsAJunkCurrency() {
        let junk = Data(#"{"amount":150,"currency":"руб"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Money.self, from: junk))
    }
}
