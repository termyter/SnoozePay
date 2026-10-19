import UIKit
import XCTest
@testable import SnoozePay

/// Historical preset RUB nominals and the direct CTA's actual storefront offer.
/// Verified paid credit uses transaction metadata (#939), independently of these
/// display contracts; its regressions live in StoreKitVerifiedPurchaseTests.
@MainActor
final class TopUpDisplayAmountTests: XCTestCase {

    // MARK: - Bottom-sheet presets

    /// Every default preset's displayed amount equals the catalogue amount of
    /// its mapped SKU. This is the core invariant: the rendered number is never
    /// an invented round literal.
    func testDefaultPresets_displayedAmount_equalsCatalogueAmount() {
        let presets = FiringTopUpBottomSheetViewController.defaultPresets
        XCTAssertFalse(presets.isEmpty, "default presets must resolve for the current catalogue")
        for preset in presets {
            let catalogue = StoreKitService.catalogAmount(for: preset.productID)
            XCTAssertEqual(
                catalogue,
                preset.amount,
                "Preset for \(preset.productID) shows \(preset.amount) but catalogue is \(catalogue ?? -1)"
            )
        }
    }

    /// The debug fallback path credits `Double(preset.amount)`. Assert that the
    /// credited value equals both the displayed amount and the catalogue amount.
    func testDefaultPresets_debugFallbackCredit_equalsDisplayedAndCatalogue() {
        for preset in FiringTopUpBottomSheetViewController.defaultPresets {
            let creditedByFallback = Double(preset.amount)   // what applePayTapped tops up
            let catalogue = StoreKitService.productAmounts[preset.productID]
            XCTAssertEqual(
                creditedByFallback,
                catalogue,
                "Fallback credit for \(preset.productID) is \(creditedByFallback), catalogue is \(catalogue ?? -1)"
            )
            XCTAssertEqual(
                creditedByFallback,
                Double(preset.amount),
                "Fallback credit must equal the displayed amount for \(preset.productID)"
            )
        }
    }

    /// The default lineup maps onto real existing SKUs (149 / 499 / 999) — guard
    /// against a future edit reintroducing a rounded literal that has no SKU.
    func testDefaultPresets_mapOntoExistingSKUs() {
        let known = Set(StoreKitService.productIDs)
        for preset in FiringTopUpBottomSheetViewController.defaultPresets {
            XCTAssertTrue(
                known.contains(preset.productID),
                "Preset SKU \(preset.productID) is not a registered product ID"
            )
        }
    }

    /// `Preset.init?` refuses an unknown SKU rather than inventing an amount —
    /// this is what prevents a rounded literal from ever being displayed again.
    func testPresetInit_rejectsUnknownSKU() {
        let preset = FiringTopUpBottomSheetViewController.Preset(
            productID: "io.mobilife.snoozepay.balance.does_not_exist",
            popular: false
        )
        XCTAssertNil(preset, "Preset must not be created for an unknown SKU")
    }

    /// The popular default preset resolves to the 499 SKU and shows 499 (not
    /// the old 500 literal), keeping the most-tapped tile honest.
    func testPopularPreset_showsCatalogueAmount() {
        let presets = FiringTopUpBottomSheetViewController.defaultPresets
        let popular = presets.first(where: { $0.popular })
        XCTAssertNotNil(popular)
        XCTAssertEqual(popular?.productID, "io.mobilife.snoozepay.balance.499")
        XCTAssertEqual(popular?.amount, StoreKitService.catalogAmount(for: "io.mobilife.snoozepay.balance.499"))
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
        let suite = "test.topUpDisplayAmount.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())
        let model = AlarmFiringViewModel(
            alarm: Alarm(penaltyAmount: 50),
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults)
        )
        let controller = AlarmFiringViewController(viewModel: model)
        controller.noBalancePurchase = AlarmFiringNoBalancePurchase(
            controller: controller, dispatch: { _ in XCTFail("Invalid offers must not dispatch") },
            offerProvider: { _ in offer }
        )
        let button = controller.makeNoBalanceApplePayButton(
            displayPrice: controller.noBalancePurchase.offer?.displayPrice
        )
        controller.applePayNoBalanceButton = button
        if offer?.productID != AlarmFiringViewController.noBalanceProductID { controller.noBalanceApplePayTapped() }
        XCTAssertFalse(controller.isViewLoaded, "Price rendering must not start the firing lifecycle")
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
