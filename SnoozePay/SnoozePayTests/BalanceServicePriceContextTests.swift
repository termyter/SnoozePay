import XCTest
@testable import SnoozePay

/// `BalanceService.priceContext` / `displayCurrency` (#1130): which snooze-price
/// scale a wallet resolves in, read synchronously from UserDefaults only.
final class BalanceServicePriceContextTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var scaleStore: SnoozePriceScaleStore!
    private var balance: BalanceService!

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!
    private var usdScale: SnoozePriceScale { SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])! }
    private var eurScale: SnoozePriceScale { SnoozePriceScale(currency: eur, tierStrings: ["1.09", "2.29", "3.49"])! }

    override func setUp() {
        super.setUp()
        suiteName = "test.priceContext.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        center = NotificationCenter()
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        balance = BalanceService(
            defaults: defaults,
            transactionRepository: TransactionRepository(defaults: defaults),
            notificationCenter: center,
            priceScaleStore: scaleStore
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        balance = nil
        scaleStore = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func fundWallet(in currency: Currency, amount: Double = 10) {
        XCTAssertEqual(balance.topUpFromPurchase(amount: amount, currency: currency), .credited)
    }

    private func storeRawScale(_ code: String, _ tiers: [String]) {
        defaults.set([code: [SnoozePriceScaleStore.tiersField: tiers]], forKey: SnoozePriceScaleStore.scalesKey)
    }

    // MARK: - 1. Stored wallet currency

    func testStoredRoubleWallet_resolvesRoubleScale_evenWithForeignStorefrontCached() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fundWallet(in: .rub, amount: 100)

        XCTAssertEqual(balance.priceContext, .scale(.rouble))
        XCTAssertEqual(balance.displayCurrency, .rub)
    }

    func testStoredDollarWallet_withCachedScale_resolvesThatScale() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fundWallet(in: usd)

        XCTAssertEqual(balance.priceContext, .scale(usdScale))
        XCTAssertEqual(balance.displayCurrency, usd)
    }

    func testStoredDollarWallet_withoutCachedScale_isUnavailable() {
        fundWallet(in: usd)

        XCTAssertEqual(balance.priceContext, .unavailable(usd))
        XCTAssertEqual(balance.displayCurrency, usd)
    }

    func testStoredDollarWallet_neverBorrowsAnotherCurrencysScale() {
        fundWallet(in: usd)
        XCTAssertTrue(scaleStore.record(eurScale))

        XCTAssertEqual(scaleStore.lastStorefrontCurrency, eur)
        XCTAssertEqual(balance.priceContext, .unavailable(usd))
    }

    // MARK: - 2. Legacy rouble wallet with history

    func testLegacyWalletWithHistory_resolvesRoubleScale_whateverTheStorefront() {
        XCTAssertTrue(balance.topUp(amount: 100))
        XCTAssertTrue(scaleStore.record(usdScale))

        XCTAssertFalse(balance.walletIsPristine)
        XCTAssertEqual(balance.priceContext, .scale(.rouble))
        XCTAssertEqual(balance.displayCurrency, .rub)
    }

    // MARK: - 3. Pristine wallet

    func testPristineWallet_withCachedStorefrontScale_resolvesIt() {
        XCTAssertTrue(scaleStore.record(usdScale))

        XCTAssertEqual(balance.priceContext, .scale(usdScale))
        XCTAssertEqual(balance.displayCurrency, usd)
    }

    func testPristineWallet_followsTheLastStorefront_notAnOlderOne() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertTrue(scaleStore.record(eurScale))

        XCTAssertEqual(balance.priceContext, .scale(eurScale))
    }

    func testPristineWallet_withoutAnyCatalogue_resolvesRoubleScale() {
        XCTAssertEqual(balance.priceContext, .scale(.rouble))
        XCTAssertEqual(balance.displayCurrency, .rub)
    }

    func testPristineWallet_lastStorefrontRouble_resolvesRoubleScale() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertTrue(scaleStore.record(.rouble))

        XCTAssertEqual(balance.priceContext, .scale(.rouble))
    }

    func testPristineWallet_lastStorefrontWithoutReadableScale_resolvesRoubleScale() {
        defaults.set("USD", forKey: SnoozePriceScaleStore.lastStorefrontCurrencyKey)
        storeRawScale("USD", ["junk"])

        XCTAssertEqual(balance.priceContext, .scale(.rouble))
    }

    func testReadingTheContext_leavesAPristineWalletPristineAndUnfrozen() {
        XCTAssertTrue(scaleStore.record(usdScale))

        _ = balance.priceContext
        _ = balance.displayCurrency

        XCTAssertTrue(balance.walletIsPristine)
        XCTAssertNil(defaults.object(forKey: WalletCurrencyStore.storageKey), "nothing is frozen before a purchase")
        XCTAssertEqual(balance.walletCurrency, .legacyDefault)
        XCTAssertTrue(balance.acceptsPurchase(in: eur), "the wallet may still adopt any currency")
    }

    /// Step 5b (#1138): AlarmKit labels of a pristine wallet quote the cached
    /// storefront currency (was `nil` under #1130).
    func testAlarmQuoteCurrency_ofAPristineWallet_isTheCachedStorefront() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(balance.alarmQuoteCurrency, usd)
    }

    // MARK: - Minor-unit rounding

    func testCachedTiers_areRoundedToTheCurrencysMinorUnit() {
        storeRawScale("USD", ["0.9899999999", "1.99", "2.99000001"])
        fundWallet(in: usd)

        XCTAssertEqual(balance.priceContext, .scale(usdScale))
    }

    func testCachedTiers_ofAZeroDigitCurrency_roundToWholeUnits() {
        let jpy = Currency(code: "JPY")!
        storeRawScale("JPY", ["160.4", "320", "479.6"])
        fundWallet(in: jpy, amount: 1000)

        XCTAssertEqual(balance.priceContext, .scale(SnoozePriceScale(currency: jpy, tiers: [160, 320, 480])!))
    }

    func testTiersThatCollapseWhenRounded_areUnavailable_notGuessed() {
        storeRawScale("USD", ["0.991", "0.994", "2.99"])
        fundWallet(in: usd)

        XCTAssertEqual(balance.priceContext, .unavailable(usd))
    }

    func testMinorUnitDigits_followISO4217() {
        XCTAssertEqual(usd.minorUnitDigits, 2)
        XCTAssertEqual(Currency.rub.minorUnitDigits, 2)
        XCTAssertEqual(Currency(code: "JPY")!.minorUnitDigits, 0)
        XCTAssertEqual(Currency(code: "KWD")!.minorUnitDigits, 3)
    }

    // MARK: - Injection

    func testConvenienceInit_readsScalesFromItsOwnSuite() {
        XCTAssertTrue(scaleStore.record(usdScale))
        let sameSuite = BalanceService(defaults: defaults, notificationCenter: center)

        XCTAssertEqual(sameSuite.priceContext, .scale(usdScale))
    }
}
