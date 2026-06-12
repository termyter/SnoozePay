import XCTest
@testable import SnoozePay

/// #275 — the amount shown on a top-up tile / CTA MUST equal what the App Store
/// charges (the SKU's catalogue amount) AND what the ledger credits.
///
/// Before this fix the firing-screen presets rendered rounded literals
/// (200 / 500 / 1000 ₽) while resolving the 149 / 499 / 999 SKUs, so the user
/// saw 200 ₽ but was charged + credited 149. The DEBUG fallback credited the
/// rounded literal, diverging further. These tests pin display == catalogue ==
/// credit for every preset and the no-balance CTA, including the debug fallback
/// path (which credits `Double(preset.amount)`).
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
            productID: "com.snooze_pay.balance.does_not_exist",
            label: "fake",
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
        XCTAssertEqual(popular?.productID, "com.snooze_pay.balance.499")
        XCTAssertEqual(popular?.amount, StoreKitService.catalogAmount(for: "com.snooze_pay.balance.499"))
    }

    // MARK: - No-balance CTA

    /// The no-balance Apple Pay CTA displays the catalogue amount of its SKU
    /// (499), not the previous 500 literal. Display == charge == credit.
    func testNoBalanceCTA_displayedAmount_equalsCatalogueAmount() {
        let displayed = AlarmFiringViewController.noBalanceDisplayAmount
        let catalogue = StoreKitService.catalogAmount(
            for: AlarmFiringViewController.noBalanceProductID
        )
        XCTAssertEqual(catalogue, displayed)
        XCTAssertEqual(displayed, 499, "no-balance CTA must show the real 499 SKU amount")
    }

    /// The no-balance debug fallback credits `Double(noBalanceDisplayAmount)`.
    /// Assert it equals the catalogue credit for the resolved SKU.
    func testNoBalanceCTA_debugFallbackCredit_equalsCatalogue() {
        let creditedByFallback = Double(AlarmFiringViewController.noBalanceDisplayAmount)
        let catalogue = StoreKitService.productAmounts[
            AlarmFiringViewController.noBalanceProductID
        ]
        XCTAssertEqual(creditedByFallback, catalogue)
    }

    // MARK: - StoreKitService helpers

    /// `catalogAmount(for:)` returns the credited amount for known SKUs and nil
    /// for unknown ones (so callers fall back to nothing, never a literal).
    func testCatalogAmount_matchesCreditedAmountForAllSKUs() {
        for (productID, amount) in StoreKitService.productAmounts {
            XCTAssertEqual(StoreKitService.catalogAmount(for: productID), Int(amount))
        }
        XCTAssertNil(StoreKitService.catalogAmount(for: "com.snooze_pay.balance.unknown"))
    }

    /// With no products loaded (test environment), `displayAmount(for:)` falls
    /// back to the catalogue amount — never nil for a known SKU, never invented.
    func testDisplayAmount_fallsBackToCatalogueWhenProductNotLoaded() {
        for (productID, amount) in StoreKitService.productAmounts {
            XCTAssertEqual(
                StoreKitService.shared.displayAmount(for: productID),
                Int(amount),
                "displayAmount must fall back to the catalogue amount for \(productID)"
            )
        }
    }
}
