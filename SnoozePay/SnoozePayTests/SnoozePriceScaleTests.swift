import XCTest
@testable import SnoozePay

/// #1120: the three-tier scale built from storefront packs, the rouble constant
/// and the legacy amount → tier thresholds.
@MainActor
final class SnoozePriceScaleTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!

    private func offer(_ price: String, _ code: String = "USD") -> TopUpOffer {
        let id = "io.mobilife.snoozepay.balance.\(price)"
        return TopUpOffer(productID: id, price: Decimal(string: price)!,
                          currencyCode: code, displayPrice: "\(price) \(code)")!
    }

    private func decimals(_ values: [String]) -> [Decimal] {
        values.map { Decimal(string: $0)! }
    }

    // MARK: - Construction from offers

    func testScaleFromOffers() {
        struct Case {
            let name: String, prices: [String], codes: [String]?, expected: [String]?
            init(_ name: String, _ prices: [String], _ codes: [String]?, _ expected: [String]?) {
                (self.name, self.prices, self.codes, self.expected) = (name, prices, codes, expected)
            }
        }
        let cases: [Case] = [
            Case("sorted", ["0.99", "1.99", "2.99"], nil, ["0.99", "1.99", "2.99"]),
            Case("unsorted", ["2.99", "0.99", "1.99"], nil, ["0.99", "1.99", "2.99"]),
            Case("five offers -> three cheapest", ["9.99", "4.99", "0.99", "2.99", "1.99"], nil,
             ["0.99", "1.99", "2.99"]),
            Case("duplicates collapse", ["0.99", "0.99", "1.99", "1.99", "4.99"], nil, ["0.99", "1.99", "4.99"]),
            Case("duplicates leave < 3", ["0.99", "0.99", "1.99", "1.99"], nil, nil),
            Case("two offers", ["0.99", "1.99"], nil, nil),
            Case("no offers", [], nil, nil),
            Case("mixed currencies", ["0.99", "1.99", "2.99", "4.99"], ["USD", "USD", "USD", "EUR"], nil)
        ]
        for testCase in cases {
            let codes = testCase.codes ?? Array(repeating: "USD", count: testCase.prices.count)
            let offers = zip(testCase.prices, codes).map { offer($0, $1) }
            let scale = SnoozePriceScale(offers: offers)
            if let expected = testCase.expected {
                XCTAssertEqual(scale?.currency, usd, testCase.name)
                XCTAssertEqual(scale?.tiers, decimals(expected), testCase.name)
            } else {
                XCTAssertNil(scale, testCase.name)
            }
        }
    }

    func testScaleTakesTheOffersCurrency() {
        let scale = SnoozePriceScale(offers: [offer("1.09", "EUR"), offer("2.29", "EUR"), offer("3.49", "EUR")])
        XCTAssertEqual(scale?.currency, eur)
        XCTAssertEqual(scale?.tiers, decimals(["1.09", "2.29", "3.49"]))
    }

    func testRoubleOffersYieldTheConstantScaleNotPackPrices() {
        let scale = SnoozePriceScale(offers: [offer("49", "RUB"), offer("149", "RUB"), offer("299", "RUB")])
        XCTAssertEqual(scale, .rouble)
    }

    // MARK: - Rouble constant

    func testRoubleScaleIs50_100_200() {
        XCTAssertEqual(SnoozePriceScale.rouble.currency, .rub)
        XCTAssertEqual(SnoozePriceScale.rouble.tiers, [50, 100, 200])
        XCTAssertEqual(SnoozePriceScale.rouble.price(for: .low), Money(50, currency: .rub))
        XCTAssertEqual(SnoozePriceScale.rouble.price(for: .mid), Money(100, currency: .rub))
        XCTAssertEqual(SnoozePriceScale.rouble.price(for: .high), Money(200, currency: .rub))
    }

    func testDirectInitValidatesTiers() {
        XCTAssertNotNil(SnoozePriceScale(currency: usd, tiers: decimals(["0.99", "1.99", "2.99"])))
        XCTAssertNil(SnoozePriceScale(currency: usd, tiers: decimals(["0.99", "1.99"])), "two tiers")
        XCTAssertNil(SnoozePriceScale(currency: usd, tiers: decimals(["0.99", "1.99", "2.99", "4.99"])), "four")
        XCTAssertNil(SnoozePriceScale(currency: usd, tiers: decimals(["1.99", "0.99", "2.99"])), "descending")
        XCTAssertNil(SnoozePriceScale(currency: usd, tiers: decimals(["0.99", "0.99", "2.99"])), "equal")
        XCTAssertNil(SnoozePriceScale(currency: usd, tiers: decimals(["0", "1.99", "2.99"])), "zero")
        XCTAssertNil(SnoozePriceScale(currency: usd, tiers: [.nan, 1, 2]), "NaN")
        XCTAssertNil(SnoozePriceScale(currency: .rub, tiers: [49, 149, 299]), "rouble scale is constant")
        XCTAssertEqual(SnoozePriceScale(currency: .rub, tiers: [50, 100, 200]), .rouble)
    }

    // MARK: - Codable

    func testCodableRoundTripsExactDecimalStrings() throws {
        let scale = SnoozePriceScale(currency: usd, tiers: decimals(["0.99", "1.99", "2.99"]))!
        let data = try JSONEncoder().encode(scale)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["currency"] as? String, "USD")
        XCTAssertEqual(json["tiers"] as? [String], ["0.99", "1.99", "2.99"])
        XCTAssertEqual(try JSONDecoder().decode(SnoozePriceScale.self, from: data), scale)
    }

    func testDecodingRejectsInvalidScales() {
        let payloads = [
            #"{"currency":"USD","tiers":["0.99","1.99"]}"#,
            #"{"currency":"USD","tiers":["2.99","1.99","0.99"]}"#,
            #"{"currency":"USD","tiers":["0.99","abc","2.99"]}"#,
            #"{"currency":"RUB","tiers":["49","149","299"]}"#,
            #"{"currency":"rub!","tiers":["50","100","200"]}"#,
            // #1126: a prefix parse would read these as 1.99 and 1 — valid-looking scales.
            #"{"currency":"USD","tiers":["0.99","1.99x","2.99"]}"#,
            #"{"currency":"USD","tiers":["0.99","1,09","2.99"]}"#,
            #"{"currency":"USD","tiers":[" 0.99","1.99","2.99"]}"#
        ]
        for payload in payloads {
            XCTAssertThrowsError(try JSONDecoder().decode(SnoozePriceScale.self, from: Data(payload.utf8)), payload)
        }
    }

    // MARK: - Tier

    func testTierRawValuesArePersistedPositions() {
        XCTAssertEqual(SnoozePriceTier.allCases.map(\.rawValue), [1, 2, 3])
        XCTAssertEqual(SnoozePriceTier(rawValue: 2), .mid)
        XCTAssertNil(SnoozePriceTier(rawValue: 0))
    }

    func testLegacyAmountThresholds() {
        let cases: [(Double, SnoozePriceTier?)] = [
            (0, .low), (20, .low), (49.99, .low), (50, .low), (50.01, .mid),
            (100, .mid), (100.01, .high), (200, .high), (500, .high),
            (-1, nil), (.nan, nil), (.infinity, nil)
        ]
        for (amount, expected) in cases {
            XCTAssertEqual(SnoozePriceTier(legacyAmount: amount), expected, "\(amount)")
        }
    }
}
