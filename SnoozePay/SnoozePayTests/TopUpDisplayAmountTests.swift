import UIKit
import XCTest
@testable import SnoozePay

/// Historical preset RUB nominals and the direct CTA's actual storefront offer.
/// Verified paid credit uses transaction metadata (#939), independently of these
/// display contracts; its regressions live in StoreKitVerifiedPurchaseTests.
@MainActor
final class TopUpDisplayAmountTests: XCTestCase {

    // MARK: - Bottom-sheet SKU identities, independent of paid prices

    func testFiringPresetsKeepSKUOrderAndPopularIdentity() {
        let presets = FiringTopUpBottomSheetViewController.defaultPresets
        XCTAssertEqual(presets.map(\.productID), [149, 499, 999].map { "io.mobilife.snoozepay.balance.\($0)" })
        XCTAssertEqual(presets.first(where: \.popular)?.productID, "io.mobilife.snoozepay.balance.499")
        XCTAssertNil(FiringTopUpBottomSheetViewController.Preset(productID: "unknown", popular: false))
    }

    // MARK: - No-balance CTA

    func testNoBalanceCTA_rendersActualOfferSuffixAndExplicitButtonAccessibilityLabel() {
        for (code, price, display) in [("USD", "4.99", "$4.99"), ("EUR", "4.99", "4,99 €"),
                                       ("RUB", "499.49", "499,49 ₽")] {
            let offer = TopUpOffer(productID: AlarmFiringViewController.noBalanceProductID,
                                   price: Decimal(string: price)!, currencyCode: code, displayPrice: display)
            let button = directButton(offer: offer)
            XCTAssertTrue(button.isEnabled)
            XCTAssertTrue(labels(button).contains(display))
            XCTAssertEqual(button.accessibilityLabel, Localized.text("common.button.top_up") + ", " + display)
            XCTAssertEqual(button.accessibilityIdentifier, "firing.noBalance.topUpButton")
        }
    }

    func testNoBalanceCTA_disablesMissingInvalidAndMismatchedOffersIncludingDirectAction() {
        let invalid = TopUpOffer(productID: AlarmFiringViewController.noBalanceProductID, price: 0,
                                 currencyCode: "USD", displayPrice: "$0.00")
        let mismatched = TopUpOffer(productID: "io.mobilife.snoozepay.balance.149", price: 1.49,
                                    currencyCode: "USD", displayPrice: "$1.49")
        for offer in [nil, invalid, mismatched] {
            let button = directButton(offer: offer)
            XCTAssertFalse(button.isEnabled)
            XCTAssertTrue(labels(button).contains("—"))
        }
    }

    private func directButton(offer: TopUpOffer?) -> SPButton {
        let controller = AlarmFiringViewController(alarm: Alarm(penaltyAmount: 50))
        controller.noBalancePurchase = AlarmFiringNoBalancePurchase(
            controller: controller, dispatch: { _ in XCTFail("Invalid offers must not dispatch") },
            offerProvider: { _ in offer }
        )
        let button = controller.makeNoBalanceApplePayButton(
            displayPrice: controller.noBalancePurchase.offer?.displayPrice
        )
        controller.applePayNoBalanceButton = button
        if offer?.productID != AlarmFiringViewController.noBalanceProductID { controller.noBalanceApplePayTapped() }
        return button
    }

    private func labels(_ view: UIView) -> [String] {
        [(view as? UILabel)?.text].compactMap { $0 } + view.subviews.flatMap(labels)
    }

    // MARK: - StoreKitService helpers

    /// `catalogAmount(for:)` returns the RUB nominal for known SKUs and nil
    /// for unknown ones (so callers fall back to nothing, never a literal).
    func testCatalogAmount_matchesRubNominalForAllSKUs() {
        for (productID, amount) in StoreKitService.productAmounts {
            XCTAssertEqual(StoreKitService.catalogAmount(for: productID), Int(amount))
        }
        XCTAssertNil(StoreKitService.catalogAmount(for: "io.mobilife.snoozepay.balance.unknown"))
    }

    /// The static catalogue remains the RUB fallback. A verified paid price
    /// may differ; it must never be overwritten by this nominal table (#939).
    func testCatalogAmount_matchesOnlyTheExplicitRubMissingPriceFallback() {
        for (productID, amount) in StoreKitService.productAmounts {
            XCTAssertEqual(StoreKitService.creditAmount(for: productID, transactionPrice: nil, currency: .rub), amount)
            XCTAssertNil(StoreKitService.creditAmount(for: productID, transactionPrice: nil,
                                                      currency: Currency(code: "USD")))
        }
    }
}
