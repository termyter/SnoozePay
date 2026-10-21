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

    func testCheckedDecimalMathCannotOverflowOrNarrowToSnoozeCounts() {
        XCTAssertNil(FiringTopUpCopy.coversNextCharge(offer: offer(999, "9e127"), balance: 1, price: 200,
                                                     walletCurrency: usd))
        XCTAssertEqual(FiringTopUpCopy.coversNextCharge(offer: offer(149, "1"), balance: 18_446_744_073_709_551_616,
                                                       price: 18_446_744_073_709_551_616, walletCurrency: usd), true)
    }
}
