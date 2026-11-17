import XCTest
@testable import SnoozePay

@MainActor
final class FiringTopUpCopyTests: XCTestCase {
    private let usd = Currency(code: "USD")!
    private func offer(_ sku: Int, _ price: String, currency: String = "USD") -> TopUpOffer {
        TopUpOffer(productID: "io.mobilife.snoozepay.balance.\(sku)", price: Decimal(string: price)!,
                   currencyCode: currency, displayPrice: price + " " + currency)!
    }

    func testRecommendationCoversOneActualNextChargeUsingExistingFractionalBalance() {
        let offers = [offer(149, "1.49"), offer(499, "4.99"), offer(999, "9.99")]
        XCTAssertEqual(FiringTopUpCopy.recommendedProductID(offers: offers, balance: 0, price: 2.99,
                                                          walletCurrency: usd), offers[1].productID)
        let reversed = Array(offers.reversed())
        XCTAssertEqual(FiringTopUpCopy.recommendedProductID(offers: reversed, balance: 1.50, price: 2.99,
                                                          walletCurrency: usd), offers[0].productID)
        XCTAssertEqual(FiringTopUpCopy.recommendedProductID(offers: offers, balance: 0, price: 99,
                                                          walletCurrency: usd), offers[2].productID)
        XCTAssertEqual(FiringTopUpCopy.coversNextCharge(offer: offers[0], balance: 1.50, price: 2.99,
                                                       walletCurrency: usd), true)
        XCTAssertEqual(FiringTopUpCopy.coversNextCharge(offer: offers[0], balance: 1.49, price: 2.99,
                                                       walletCurrency: usd), false)
    }

    func testUnknownArithmeticUsesCheapestWithoutInventingCoverageOrConvertingCurrencies() {
        let offers = [offer(999, "9.99"), offer(149, "1.49")]
        for price in [0, -1, Double.nan, .infinity, .leastNonzeroMagnitude] {
            XCTAssertNil(FiringTopUpCopy.coversNextCharge(offer: offers[0], balance: 0, price: price,
                                                         walletCurrency: usd))
            XCTAssertEqual(FiringTopUpCopy.recommendedProductID(offers: offers, balance: 0, price: price,
                                                              walletCurrency: usd), offers[1].productID)
        }
        for invalid in [Double.nan, .infinity, -1] {
            XCTAssertNil(FiringTopUpCopy.coversNextCharge(offer: offers[0], balance: invalid, price: 200,
                                                         walletCurrency: usd))
        }
        XCTAssertNil(FiringTopUpCopy.coversNextCharge(offer: offer(149, "1.49", currency: "EUR"),
                                                     balance: 0, price: 1, walletCurrency: usd))
        XCTAssertNil(FiringTopUpCopy.recommendedProductID(offers: [offers[0], offer(499, "4.99", currency: "EUR")],
                                                         balance: 0, price: 2, walletCurrency: usd))
        XCTAssertNil(FiringTopUpCopy.recommendedProductID(offers: [], balance: 0, price: 2, walletCurrency: usd))
    }

    /// #652: the one selection both firing entry points use.
    func testPreselectedOfferIsTheMinimalSufficientAcceptedPackAndFallsBackOnlyToExplainRefusal() {
        let offers = [offer(149, "1.49"), offer(499, "4.99"), offer(999, "9.99")]
        let accepts: (Currency) -> Bool = { $0.code == "USD" }
        for (balance, price, expected) in [(0.0, 1.0, 149), (0, 1.49, 149), (0, 1.50, 499), (3, 4.49, 149),
                                           (0, 9.99, 999), (0, 50, 999), (0.01, 9.99, 999)] {
            XCTAssertEqual(FiringTopUpCopy.preselectedOffer(offers: offers, balance: balance, price: price,
                                                            walletCurrency: usd, acceptsPurchase: accepts)?.productID,
                           offers.first { $0.productID.hasSuffix(".\(expected)") }?.productID, "\(balance)/\(price)")
        }
        let refused = [offer(499, "4.99", currency: "EUR"), offer(149, "1.49", currency: "EUR")]
        XCTAssertEqual(FiringTopUpCopy.preselectedOffer(offers: refused, balance: 0, price: 2,
                                                        walletCurrency: usd, acceptsPurchase: accepts)?.productID,
                       refused[0].productID, "A refused storefront still gets a CTA that explains the refusal")
        XCTAssertNil(FiringTopUpCopy.preselectedOffer(offers: [], balance: 0, price: 2, walletCurrency: usd,
                                                      acceptsPurchase: accepts))
    }

    /// #1112: the whole catalogue's minimal sufficient pack is always an offered row.
    func testOfferedRowsAlwaysIncludeTheCataloguesMinimalSufficientPack() {
        let catalogue = [offer(49, "0.49"), offer(149, "1.49"), offer(299, "2.99"), offer(499, "4.99"),
                         offer(999, "9.99")]
        let defaults = [149, 499, 999]
        let cases: [(Double, Double, [Int])] = [
            (0, 2.00, [299, 499, 999]),      // the issue: 149 is short, 299 is the minimal pack
            (0, 2.99, [299, 499, 999]),
            (0, 0.30, [49, 499, 999]),       // nothing below 49: the cheapest non-popular row makes room
            (0.50, 0.99, [49, 499, 999]),    // banked money counts
            (0, 1.00, defaults),             // 149 is already minimal: nothing changes
            (1.00, 2.00, defaults),
            (0, 4.00, defaults), (0, 9.99, defaults),
            (0, 50, defaults),               // nothing covers
            (0, 0, defaults), (0, .nan, defaults), (.infinity, 2, defaults)  // unknown coverage
        ]
        for (balance, price, expected) in cases {
            XCTAssertEqual(rows(defaults, catalogue: catalogue, balance: balance, price: price), expected,
                           "\(balance)/\(price)")
        }
        let unpricedDefault = catalogue.filter { !$0.productID.hasSuffix(".999") }
        XCTAssertEqual(rows(defaults, catalogue: unpricedDefault, balance: 0, price: 2), defaults)
        let euro = [offer(49, "0.49", currency: "EUR"), offer(149, "1.49", currency: "EUR"),
                    offer(299, "2.99", currency: "EUR"), offer(499, "4.99", currency: "EUR"),
                    offer(999, "9.99", currency: "EUR")]
        XCTAssertEqual(rows(defaults, catalogue: euro, balance: 0, price: 2, accepts: true), defaults,
                       "A storefront in another currency than the wallet stays unknown (#1109)")
        XCTAssertEqual(rows(defaults, catalogue: catalogue.filter { !$0.productID.hasSuffix(".299") }
                            + [offer(299, "2.99", currency: "EUR")], balance: 0, price: 2, accepts: true),
                       defaults, "Mixed accepted currencies stay unknown")
        XCTAssertEqual(rows(defaults, catalogue: catalogue.filter { !$0.productID.hasSuffix(".299") }
                            + [offer(299, "2.99", currency: "EUR")], balance: 0, price: 2),
                       defaults, "A refused 299 is never offered; 499 is then minimal and already a row")
        XCTAssertEqual(rows(defaults, catalogue: catalogue + [offer(699, "6.99")], balance: 0, price: 6),
                       [499, 699, 999], "The popular 499 row is never the one replaced")
    }

    private func rows(_ defaults: [Int], catalogue: [TopUpOffer], balance: Double, price: Double,
                      accepts all: Bool = false) -> [Int] {
        let sku = { (nominal: Int) in "io.mobilife.snoozepay.balance.\(nominal)" }
        return FiringTopUpCopy.offeredProductIDs(
            defaults: defaults.map(sku), popular: [sku(499)], catalogue: catalogue, balance: balance, price: price,
            walletCurrency: usd, acceptsPurchase: { all || $0.code == "USD" }
        ).compactMap { Int($0.split(separator: ".").last ?? "") }
    }

    func testCheckedDecimalMathCannotOverflowOrNarrowToSnoozeCounts() {
        XCTAssertNil(FiringTopUpCopy.coversNextCharge(offer: offer(999, "9e127"), balance: 1, price: 200,
                                                     walletCurrency: usd))
        XCTAssertEqual(FiringTopUpCopy.coversNextCharge(offer: offer(149, "1"), balance: 18_446_744_073_709_551_616,
                                                       price: 18_446_744_073_709_551_616, walletCurrency: usd), true)
    }
}
