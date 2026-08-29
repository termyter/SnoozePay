import XCTest
@testable import SnoozePay

/// Unit tests for `Currency` — the validating wrapper that keeps a wallet's
/// currency comparable by equality (#561). The failure this type exists to
/// prevent is `"rub" != "RUB"` quietly deciding a purchase is foreign.
final class CurrencyTests: XCTestCase {

    // MARK: - Validation

    func testAcceptsThreeLetterCode() {
        XCTAssertEqual(Currency(code: "RUB")?.code, "RUB")
        XCTAssertEqual(Currency(code: "USD")?.code, "USD")
    }

    func testCanonicalisesCaseAndSurroundingWhitespace() {
        XCTAssertEqual(Currency(code: "rub"), Currency.rub)
        XCTAssertEqual(Currency(code: " Rub "), Currency.rub)
    }

    func testRejectsAnythingThatIsNotThreeAsciiLetters() {
        XCTAssertNil(Currency(code: ""))
        XCTAssertNil(Currency(code: "RU"))
        XCTAssertNil(Currency(code: "RUBL"))
        XCTAssertNil(Currency(code: "₽"))
        XCTAssertNil(Currency(code: "руб"))
        XCTAssertNil(Currency(code: "R1B"))
    }

    // MARK: - StoreKit bridge

    func testRoundTripsThroughLocaleCurrency() {
        // `StoreKit.Transaction.currency` is a `Locale.Currency`; #563 reads the
        // wallet currency out of it, so the bridge must be lossless both ways.
        let storeKitValue = Locale.Currency("USD")
        let currency = Currency(storeKitValue)
        XCTAssertEqual(currency?.code, "USD")
        XCTAssertEqual(currency?.localeCurrency, storeKitValue)
    }

    func testRejectsAnUnusableLocaleCurrency() {
        XCTAssertNil(Currency(Locale.Currency("")))
    }

    // MARK: - Legacy default

    func testLegacyDefaultIsRoubles() {
        // The single point where the app assumes a currency instead of knowing
        // it — data written before currencies existed is rouble data.
        XCTAssertEqual(Currency.legacyDefault, Currency.rub)
        XCTAssertEqual(Currency.legacyDefault.code, "RUB")
    }

    // MARK: - Codable

    // Wrapped in an array so the assertions are about the encoded shape and not
    // about whether top-level JSON fragments are allowed.

    func testEncodesAsBareString() throws {
        let data = try JSONEncoder().encode([Currency.rub])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["RUB"]"#)
    }

    func testDecodesFromBareString() throws {
        let decoded = try JSONDecoder().decode([Currency].self, from: Data(#"["USD"]"#.utf8))
        XCTAssertEqual(decoded.first?.code, "USD")
    }

    func testDecodingRejectsAJunkCode() {
        XCTAssertThrowsError(try JSONDecoder().decode([Currency].self, from: Data(#"["₽"]"#.utf8)))
    }

    func testDescriptionIsTheCode() {
        XCTAssertEqual("\(Currency.rub)", "RUB")
    }
}
