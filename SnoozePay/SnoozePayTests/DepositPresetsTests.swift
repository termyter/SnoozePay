import XCTest
@testable import SnoozePay

/// Tests the Deposit bottom-sheet preset catalogue (issue #233) — SKU
/// mapping against the live StoreKit catalogue, default selection, and
/// the localized "≈ N откладываний" pluralisation.
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
            XCTAssertEqual(preset.productID, "com.snooze_pay.balance.\(preset.amount)")
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
        XCTAssertEqual(DepositPresets.preset(forAmount: 499)?.productID, "com.snooze_pay.balance.499")
        XCTAssertNil(DepositPresets.preset(forAmount: 500))
    }

    // MARK: - Labels

    func testSnoozeCountLabels_roundAndPluralizeCorrectly() {
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 49), "≈ 1 откладывание")
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 100), "≈ 2 откладывания")
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 149), "≈ 3 откладывания")
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 299), "≈ 6 откладываний")
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 499), "≈ 10 откладываний")
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 999), "≈ 20 откладываний")
    }

    func testSnoozeCountLabel_neverShowsZero() {
        XCTAssertEqual(DepositPresets.snoozeCountLabel(forAmount: 1), "≈ 1 откладывание")
    }

    func testSnoozeNoun_russianPluralRules() {
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 1), "откладывание")
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 2), "откладывания")
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 5), "откладываний")
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 11), "откладываний")
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 21), "откладывание")
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 22), "откладывания")
        XCTAssertEqual(DepositPresets.snoozeNoun(for: 112), "откладываний")
    }
}
