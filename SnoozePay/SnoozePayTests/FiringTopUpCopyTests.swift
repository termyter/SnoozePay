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

    func testCheckedDecimalMathCannotOverflowOrNarrowToSnoozeCounts() {
        XCTAssertNil(FiringTopUpCopy.coversNextCharge(offer: offer(999, "9e127"), balance: 1, price: 200,
                                                     walletCurrency: usd))
        XCTAssertEqual(FiringTopUpCopy.coversNextCharge(offer: offer(149, "1"), balance: 18_446_744_073_709_551_616,
                                                       price: 18_446_744_073_709_551_616, walletCurrency: usd), true)
    }
}
