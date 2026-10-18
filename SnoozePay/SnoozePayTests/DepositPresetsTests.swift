import XCTest
@testable import SnoozePay

/// Tests the Deposit bottom-sheet preset catalogue (issue #233) — SKU
/// mapping against the live StoreKit catalogue and default selection.
final class DepositPresetsTests: XCTestCase {

    // MARK: - Catalogue

    func testPresets_matchLiveStoreKitCatalogue() {
        // Issue #233 item 8: until PM approves the designed 50…1000 ₽
        // line-up, the sheet must use the existing SKUs.
        XCTAssertEqual(DepositPresets.presets.map(\.amount), [49, 149, 299, 499, 999])
        for preset in DepositPresets.presets {
            XCTAssertTrue(
                StoreKitService.productIDs.contains(preset.productID),
                "Preset \(preset.amount) ₽ points at unknown SKU \(preset.productID)"
            )
            XCTAssertEqual(preset.productID, "io.mobilife.snoozepay.balance.\(preset.amount)")
        }
    }

    func testPresets_exactlyOnePopular_andItIs149() {
        let popular = DepositPresets.presets.filter(\.popular)
        XCTAssertEqual(popular.count, 1)
        XCTAssertEqual(popular.first?.amount, 149)
    }

    func testDefaultAmount_isPopularPreset() {
        XCTAssertEqual(DepositPresets.defaultAmount, 149)
    }

    func testPresetForAmount_returnsMatchingPreset() {
        XCTAssertEqual(DepositPresets.preset(forAmount: 499)?.productID, "io.mobilife.snoozepay.balance.499")
        XCTAssertNil(DepositPresets.preset(forAmount: 500))
    }

}
