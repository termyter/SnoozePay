import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class DepositCatalogCurrencyTests: XCTestCase {
    func testActualTileAndCheckoutUseLocalizedOfferAndDispatchSkuWithoutCreditingNominal() throws {
        for (code, price, display) in [("USD", "1.79", "$1.79"), ("EUR", "1.99", "1,99 €"),
                                       ("RUB", "149.49", "149,49 ₽")] {
            let fixture = try Fixture()
            defer { fixture.clear() }
            let usdPrices = ["0.49", "1.79", "2.99", "4.99", "9.99"]
            if code == "USD" {
                for (preset, price) in zip(DepositPresets.presets, usdPrices) {
                    fixture.offer(amount: preset.amount, price: price, display: "$" + price)
                }
            }
            fixture.offer(price: price, code: code, display: display)
            let sheet = fixture.sheet()
            sheet.loadViewIfNeeded()
            let tiles = descendants(sheet.view).compactMap { $0 as? SPAmountPreset }
            XCTAssertEqual(tiles.count, 5)
            if code == "USD" {
                for (tile, price) in zip(tiles, usdPrices) {
                    XCTAssertTrue(strings(tile).contains("$" + price))
                }
            }
            XCTAssertEqual(tiles.map(\.popular), [false, true, false, false, false])
            XCTAssertEqual(tiles.map(\.isSelected), [false, true, false, false, false])
            XCTAssertTrue(strings(tiles[1]).contains(display))
            XCTAssertEqual(tiles[1].value, Decimal(string: price))
            let button = try purchaseButton(sheet)
            XCTAssertTrue(strings(button).contains(display))
            XCTAssertFalse(strings(tiles[1]).contains { $0.contains("≈") })
            XCTAssertTrue(button.isEnabled, "Pristine wallets accept the first foreign purchase")
            let before = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(fixture.requested, [Fixture.productID(149)])
            XCTAssertFalse(button.isEnabled)
            XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, before)
        }
    }

    func testEmptyLoadedChangedAndRemovedOffersRefreshActualControlsAndRetainSelection() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        let sheet = fixture.sheet()
        sheet.loadViewIfNeeded()
        XCTAssertTrue(strings(sheet.view).contains(Localized.text("deposit.error.products_unavailable")))
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertTrue(fixture.requested.isEmpty)
        let tiles = descendants(sheet.view).compactMap { $0 as? SPAmountPreset }
        tiles[4].sendActions(for: .touchUpInside)
        for display in ["$2.99", "$3.49"] {
            fixture.offer(amount: 999, price: display == "$2.99" ? "2.99" : "3.49", display: display)
            fixture.reload()
            XCTAssertTrue(strings(tiles[4]).contains(display))
            XCTAssertTrue(strings(try purchaseButton(sheet)).contains(display))
            XCTAssertTrue(tiles[4].isSelected)
            XCTAssertTrue(tiles[1].popular)
            XCTAssertTrue(try purchaseButton(sheet).isEnabled)
        }
        fixture.offers.removeAll()
        fixture.reload()
        XCTAssertTrue(strings(tiles[4]).contains("—"))
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertTrue(fixture.requested.isEmpty)
        XCTAssertEqual(fixture.balance.balance, 0)
    }

    func testCatalogRefreshCannotReenableBusyPendingOrSuccessfulCheckoutAndCancelRequiresOffer() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        fixture.offer()
        let sheet = fixture.sheet()
        sheet.loadViewIfNeeded()
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        fixture.reload()
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        fixture.center.post(name: StoreKitService.purchasePendingNotification, object: nil)
        fixture.reload()
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        XCTAssertEqual(fixture.requested.count, 1)
        fixture.offers.removeAll()
        fixture.center.post(name: StoreKitService.purchaseCancelledNotification, object: nil)
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        fixture.offer()
        fixture.reload()
        XCTAssertTrue(try purchaseButton(sheet).isEnabled)
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.balance.topUpFromPurchase(amount: 0.49, currency: try XCTUnwrap(Currency(code: "USD"))),
                       .credited)
        fixture.center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                            userInfo: [StoreKitService.amountUserInfoKey: 0.49])
        fixture.reload()
        fixture.center.post(name: StoreKitService.purchaseCancelledNotification, object: nil)
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        XCTAssertEqual(fixture.requested.count, 2)
        XCTAssertEqual(fixture.balance.balance, 0.49)
    }

    func testEstablishedCurrencyMismatchStopsActualCheckoutBeforeDispatch() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        XCTAssertEqual(fixture.balance.topUpFromPurchase(amount: 10, currency: .rub), .credited)
        fixture.offer()
        let sheet = fixture.sheet()
        sheet.loadViewIfNeeded()
        let before = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertTrue(fixture.requested.isEmpty)
        XCTAssertTrue(try purchaseButton(sheet).isEnabled)
        XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, before)
    }

    func testInvalidOfferMetadataIsUnavailableInsteadOfBecomingNominalRubles() throws {
        let fixture = try Fixture()
        defer { fixture.clear() }
        let sheet = fixture.sheet()
        sheet.loadViewIfNeeded()
        for (price, code, display) in [(Decimal.nan, "USD", "$1.79"), (0, "USD", "$0.00"),
                                       (-1, "USD", "-$1.00"), (1, "", "$1.00"), (1, "USD", "  ")] {
            fixture.offers[Fixture.productID(149)] = TopUpOffer(productID: Fixture.productID(149), price: price,
                                                              currencyCode: code, displayPrice: display)
            fixture.reload()
            XCTAssertNil(fixture.offers[Fixture.productID(149)])
            XCTAssertFalse(try purchaseButton(sheet).isEnabled)
            try purchaseButton(sheet).sendActions(for: .touchUpInside)
        }
        fixture.offers[Fixture.productID(149)] = TopUpOffer(productID: Fixture.productID(999), price: 1,
                                                          currencyCode: "USD", displayPrice: "$1.00")
        fixture.reload()
        XCTAssertFalse(try purchaseButton(sheet).isEnabled, "A different SKU's offer cannot enable checkout")
        XCTAssertTrue(fixture.requested.isEmpty)
        XCTAssertEqual(fixture.balance.balance, 0)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func strings(_ view: UIView) -> [String] {
        ([view] + descendants(view)).compactMap { ($0 as? UILabel).flatMap { $0.attributedText?.string ?? $0.text } }
    }

    private func purchaseButton(_ sheet: UIViewController) throws -> SPButton {
        try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? SPButton }.first {
            $0.accessibilityIdentifier == "deposit.purchaseButton"
        })
    }

    @MainActor
    private final class Fixture {
        let suite = "DepositCatalogCurrencyTests.\(UUID())"
        let defaults: UserDefaults
        let center = NotificationCenter()
        let balance: BalanceService
        var offers: [String: TopUpOffer] = [:]
        var requested: [String] = []

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            balance = BalanceService(defaults: defaults, notificationCenter: center)
        }

        static func productID(_ amount: Int) -> String { "io.mobilife.snoozepay.balance.\(amount)" }
        func clear() { defaults.removePersistentDomain(forName: suite) }
        func reload() { center.post(name: StoreKitService.productsLoadedNotification, object: nil) }
        func offer(amount: Int = 149, price: String = "1.79", code: String = "USD", display: String = "$1.79") {
            let productID = Self.productID(amount)
            offers[productID] = TopUpOffer(productID: productID, price: Decimal(string: price)!,
                                            currencyCode: code, displayPrice: display)
        }
        func sheet() -> DepositBottomSheetViewController {
            DepositBottomSheetViewController(
                balance: balance, notificationCenter: center, scheduleSuccessDismissal: { _, _ in },
                purchaseProduct: { [weak self] in self?.requested.append($0) },
                offerProvider: { [weak self] in self?.offers[$0] }
            )
        }
    }
}
