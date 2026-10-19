import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class FiringTopUpCatalogTests: XCTestCase {
    func testActualRowsAndCTAQuoteFractionalOffersVerbatimAndDispatchSelectedSKU() throws {
        for (code, price, display) in [("USD", "4.99", "$4.99"), ("EUR", "4.99", "4,99 €"),
                                       ("RUB", "499.49", "499,49 ₽")] {
            let fixture = Fixture()
            defer { fixture.clear() }
            fixture.put(499, price: price, code: code, display: display)
            let sheet = fixture.makeSheet()
            sheet.loadViewIfNeeded()
            let rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
            XCTAssertEqual(rows.count, 3)
            XCTAssertTrue(strings(rows[1]).contains(display))
            XCTAssertEqual(rows[1].accessibilityLabel, "Пополнить баланс, " + display)
            XCTAssertTrue(rows[1].isSelected)
            let button = try purchaseButton(sheet)
            XCTAssertTrue(button.isEnabled)
            XCTAssertTrue(strings(button).contains(display))
            XCTAssertEqual(button.accessibilityLabel, "Apple Pay, " + display)
            XCTAssertEqual(strings(sheet.view).filter { $0 == "Пополнить баланс" }.count, 4)
            let disclaimer = "Деньги попадают в баланс. Списываются только при откладывании."
            XCTAssertEqual(strings(sheet.view).filter { $0 == disclaimer }.count, 2)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(fixture.requested, [Fixture.sku(499)])
            XCTAssertEqual(fixture.wallet.balance, 0)
            XCTAssertTrue(TransactionRepository(defaults: fixture.defaults).fetchAll().isEmpty)
        }
    }

    func testMissingInvalidAndMismatchedOffersStayUnknownWithoutDispatchOrWalletWrites() throws {
        let unavailable: [TopUpOffer?] = [
            nil,
            TopUpOffer(productID: Fixture.sku(149), price: 0, currencyCode: "USD", displayPrice: "$0.00"),
            TopUpOffer(productID: Fixture.sku(149), price: .nan, currencyCode: "USD", displayPrice: "NaN"),
            TopUpOffer(productID: Fixture.sku(149), price: 1.49, currencyCode: "invalid", displayPrice: "$1.49"),
            TopUpOffer(productID: Fixture.sku(499), price: 4.99, currencyCode: "USD", displayPrice: "$4.99")
        ]
        for offer in unavailable {
            let fixture = Fixture()
            defer { fixture.clear() }
            fixture.offers[Fixture.sku(149)] = offer
            let before = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
            let sheet = fixture.makeSheet()
            sheet.loadViewIfNeeded()
            let rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
            XCTAssertTrue(rows.allSatisfy { !$0.isEnabled && strings($0).contains("—") })
            rows[0].sendActions(for: .touchUpInside)
            let button = try purchaseButton(sheet)
            XCTAssertFalse(button.isEnabled)
            XCTAssertTrue(strings(button).contains("—"))
            button.sendActions(for: .touchUpInside)
            _ = sheet.perform(NSSelectorFromString("applePayTapped"))
            XCTAssertTrue(fixture.requested.isEmpty)
            XCTAssertTrue(fixture.alerts.isEmpty)
            XCTAssertTrue(fixture.delays.isEmpty)
            XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, before)
        }
    }

    func testInitialRecommendationUsesTheInjectedWalletAndOneActualNextCharge() throws {
        let fixture = Fixture()
        defer { fixture.clear() }
        XCTAssertEqual(fixture.wallet.topUpFromPurchase(amount: 1.50, currency: Currency(code: "USD")!), .credited)
        for (sku, price) in [(149, "1.49"), (499, "4.99"), (999, "9.99")] {
            fixture.put(sku, price: price, code: "USD", display: "$" + price)
        }
        let sheet = fixture.makeSheet(snoozePrice: 2.99)
        sheet.loadViewIfNeeded()
        let rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
        XCTAssertTrue(rows[0].isSelected, "1.50 already banked plus actual1.49 covers the next2.99 charge")
        XCTAssertTrue(strings(try purchaseButton(sheet)).contains("$1.49"))
        XCTAssertEqual(fixture.wallet.balance, 1.50)
    }

    func testCatalogRefreshRetainsSelectedSKUAndHasOneCTAWithFourActiveAnchors() throws {
        let fixture = Fixture()
        defer { fixture.clear() }
        let sheet = fixture.makeSheet()
        sheet.loadViewIfNeeded()
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        fixture.put(149, price: "1.49", code: "USD", display: "$1.49")
        fixture.put(499, price: "4.99", code: "USD", display: "$4.99")
        fixture.refresh()
        var rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
        XCTAssertTrue(rows[0].isSelected)
        rows[1].sendActions(for: .touchUpInside)
        for display in ["USD 4.25", "Store price $4.50", "Final $4.99"] {
            fixture.put(499, price: "4.99", code: "USD", display: display)
            fixture.refresh()
            let button = try purchaseButton(sheet)
            XCTAssertTrue(strings(button).contains(display))
            XCTAssertEqual(descendants(sheet.view).compactMap { $0 as? SPButton }.count, 1)
            XCTAssertEqual(sheet.view.constraints.filter {
                $0.isActive && (($0.firstItem as? UIView) === button || ($0.secondItem as? UIView) === button)
            }.count, 4)
            rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
            XCTAssertEqual(rows.count, 3)
            XCTAssertTrue(rows[1].isSelected)
        }
        fixture.offers[Fixture.sku(499)] = nil
        fixture.refresh()
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        XCTAssertTrue(strings(try purchaseButton(sheet)).contains("—"))
        // A mismatched response must stay unavailable.
        fixture.offers[Fixture.sku(499)] = fixture.offers[Fixture.sku(149)]
        fixture.refresh()
        _ = sheet.perform(NSSelectorFromString("applePayTapped"))
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        XCTAssertTrue(fixture.requested.isEmpty)
        XCTAssertEqual(fixture.wallet.balance, 0)
    }

    func testPendingSelectionSurvivesCatalogChangesAndCancellationRetriesThatSKU() throws {
        let fixture = Fixture()
        defer { fixture.clear() }
        fixture.put(149, price: "1.49", code: "USD", display: "$1.49")
        let sheet = fixture.makeSheet()
        sheet.loadViewIfNeeded()
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchasePendingNotification)
        fixture.put(999, price: "0.49", code: "USD", display: "$0.49")
        fixture.refresh()
        let rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
        XCTAssertTrue(rows[0].isSelected, "Catalog refresh cannot silently replace the pending SKU")
        XCTAssertTrue(rows[2].isEnabled, "Selection is allowed while purchase dispatch stays locked")
        rows[2].sendActions(for: .touchUpInside)
        XCTAssertTrue(rows[2].isSelected)
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        fixture.put(999, price: "0.99", code: "USD", display: "$0.99")
        fixture.refresh()
        XCTAssertTrue(rows[2].isSelected)
        XCTAssertTrue(strings(try purchaseButton(sheet)).contains("$0.99"))
        _ = sheet.perform(NSSelectorFromString("applePayTapped"))
        XCTAssertEqual(fixture.requested, [Fixture.sku(149)], "A new selection cannot start a concurrent purchase")
        fixture.offers[Fixture.sku(999)] = nil
        fixture.refresh()
        XCTAssertTrue(rows[2].isSelected)
        XCTAssertFalse(rows[2].isEnabled)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertFalse(try purchaseButton(sheet).isEnabled, "Cancellation cannot make a missing offer purchasable")
        fixture.put(999, price: "0.79", code: "USD", display: "$0.79")
        fixture.refresh()
        XCTAssertTrue(rows[2].isSelected)
        XCTAssertTrue(try purchaseButton(sheet).isEnabled)
        XCTAssertTrue(strings(try purchaseButton(sheet)).contains("$0.79"))
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.requested, [Fixture.sku(149), Fixture.sku(999)])
        XCTAssertEqual(fixture.wallet.balance, 0)
        XCTAssertTrue(TransactionRepository(defaults: fixture.defaults).fetchAll().isEmpty)
    }

    func testCatalogRefreshNeverClearsPendingAcknowledgementOrSuccessState() throws {
        let fixture = Fixture()
        defer { fixture.clear() }
        fixture.put(149, price: "1.49", code: "USD", display: "$1.49")
        let sheet = fixture.makeSheet()
        sheet.loadViewIfNeeded()
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchasePendingNotification)
        fixture.refresh()
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertTrue(try purchaseButton(sheet).isEnabled)
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchaseFailedNotification)
        fixture.refresh()
        XCTAssertEqual(fixture.alerts.count, 1)
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        sheet.acknowledgePurchaseFailure()
        XCTAssertTrue(try purchaseButton(sheet).isEnabled)
        try purchaseButton(sheet).sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.wallet.topUpFromPurchase(amount: 0.49, currency: Currency(code: "USD")!), .credited)
        fixture.post(StoreKitService.purchaseCompletedNotification,
                     info: [StoreKitService.amountUserInfoKey: 0.49])
        XCTAssertEqual(try purchaseButton(sheet).alpha, 0, "Ending the pause must retain the success UI")
        fixture.refresh()
        fixture.post(StoreKitService.purchaseCancelledNotification)
        sheet.acknowledgePurchaseFailure()
        XCTAssertEqual(fixture.delays, [2])
        XCTAssertFalse(try purchaseButton(sheet).isEnabled)
        XCTAssertEqual(try purchaseButton(sheet).alpha, 0)
        XCTAssertEqual(fixture.requested.count, 3)
        XCTAssertEqual(fixture.wallet.balance, 0.49)
    }

    func testRealWalletPolicyAllowsFirstForeignAndExplainsEstablishedRefusalBeforeInjectedDispatch() throws {
        for pristine in [true, false] {
            let fixture = Fixture()
            defer { fixture.clear() }
            if !pristine { XCTAssertEqual(fixture.wallet.topUpFromPurchase(amount: 10, currency: .rub), .credited) }
            fixture.put(499, price: "4.99", code: "USD", display: "$4.99")
            let sheet = fixture.makeSheet()
            sheet.loadViewIfNeeded()
            let before = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
            XCTAssertTrue(try purchaseButton(sheet).isEnabled, "A known foreign offer must explain refusal on tap")
            try purchaseButton(sheet).sendActions(for: .touchUpInside)
            XCTAssertEqual(fixture.requested, pristine ? [Fixture.sku(499)] : [])
            if !pristine {
                XCTAssertEqual(fixture.alerts.first?.title, ForeignCurrencyNotice.alertTitle)
                XCTAssertEqual(fixture.alerts.first?.message,
                               ForeignCurrencyNotice.message(wallet: .rub, storefront: Currency(code: "USD")!))
            }
            XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, before)
        }
    }

    func testUnavailableOrdinaryOfferCannotCreditAndOnlyExplicitProviderFreeDemoCan() throws {
        let fixture = Fixture()
        defer { fixture.clear() }
        for arguments in [[], ["-uitour-storekit-empty"]] {
            let sheet = fixture.makeSheet(arguments: arguments)
            sheet.loadViewIfNeeded()
            _ = sheet.perform(NSSelectorFromString("applePayTapped"))
            XCTAssertFalse(try purchaseButton(sheet).isEnabled)
            XCTAssertTrue(fixture.requested.isEmpty)
            XCTAssertEqual(fixture.wallet.balance, 0)
        }
        fixture.put(149, price: "1.49", code: "USD", display: "$1.49")
        let unverified = fixture.makeSheet(dispatch: false)
        unverified.loadViewIfNeeded()
        try purchaseButton(unverified).sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.wallet.balance, 0, "A valid quote without verified checkout cannot credit a nominal")
        XCTAssertEqual(fixture.alerts.last?.message, Localized.text("deposit.error.products_unavailable"))
        XCTAssertTrue(fixture.delays.isEmpty)
        #if DEBUG
        let demo = fixture.makeSheet(provider: false, dispatch: false, arguments: ["-uitour-storekit-empty"])
        demo.loadViewIfNeeded()
        let demoRow = try XCTUnwrap(descendants(demo.view).compactMap { $0 as? FiringTopUpPresetRow }.first {
            $0.accessibilityIdentifier == "firingTopUp.preset." + Fixture.sku(149)
        })
        demoRow.sendActions(for: .touchUpInside)
        XCTAssertTrue(demoRow.isSelected)
        XCTAssertTrue(strings(try purchaseButton(demo)).contains("149\u{202F}₽"))
        try purchaseButton(demo).sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.wallet.balance, 149)
        XCTAssertEqual(fixture.delays, [2])
        #endif
    }

    func testCatalogObserverDoesNotRetainTheSheet() {
        let fixture = Fixture()
        defer { fixture.clear() }
        weak var released: FiringTopUpBottomSheetViewController?
        autoreleasepool {
            let sheet = fixture.makeSheet()
            sheet.loadViewIfNeeded()
            released = sheet
        }
        XCTAssertNil(released)
        fixture.refresh()
    }

    private func purchaseButton(_ sheet: UIViewController) throws -> SPButton {
        try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? SPButton }.first {
            $0.accessibilityIdentifier == "firingTopUp.purchaseButton"
        })
    }
    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private func strings(_ view: UIView) -> [String] {
        [(view as? UILabel)?.text].compactMap { $0 } + view.subviews.flatMap(strings)
    }

    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let center: NotificationCenter
        let wallet: BalanceService
        var offers: [String: TopUpOffer] = [:]
        var requested: [String] = []
        var alerts: [UIAlertController] = []
        var delays: [TimeInterval] = []
        init() {
            let suite = "FiringTopUpCatalogTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            let center = NotificationCenter()
            self.suite = suite
            self.defaults = defaults
            self.center = center
            self.wallet = BalanceService(defaults: defaults, notificationCenter: center)
        }
        func clear() { defaults.removePersistentDomain(forName: suite) }
        static func sku(_ nominal: Int) -> String { "io.mobilife.snoozepay.balance.\(nominal)" }
        func put(_ nominal: Int, price: String, code: String, display: String) {
            offers[Self.sku(nominal)] = TopUpOffer(productID: Self.sku(nominal), price: Decimal(string: price)!,
                                                currencyCode: code, displayPrice: display)
        }
        func refresh() { post(StoreKitService.productsLoadedNotification) }
        func post(_ name: Notification.Name, info: [String: Any]? = nil) {
            center.post(name: name, object: nil, userInfo: info)
        }
        func makeSheet(snoozePrice: Double = 200, provider: Bool = true, dispatch: Bool = true,
                       arguments: [String] = [])
            -> FiringTopUpBottomSheetViewController {
            let purchase: ((String) -> Void)? = dispatch ? { [weak self] in self?.requested.append($0) } : nil
            let catalog: ((String) -> TopUpOffer?)? = provider ? { [weak self] in self?.offers[$0] } : nil
            return FiringTopUpBottomSheetViewController(
                snoozePrice: snoozePrice, balance: wallet, notificationCenter: center,
                scheduleSuccessDismissal: { [weak self] delay, _ in self?.delays.append(delay) },
                purchaseProduct: purchase,
                presentPurchaseFailure: { [weak self] in self?.alerts.append($0) }, pauseLifecycle: { _ in },
                preflightRefusal: { _ in nil },
                offerProvider: catalog, arguments: arguments
            )
        }
    }
}
