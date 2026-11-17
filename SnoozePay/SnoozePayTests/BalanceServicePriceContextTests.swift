import os
import XCTest
@testable import SnoozePay

/// `BalanceService.priceContext` / `displayCurrency` (#1130): which snooze-price
/// scale a wallet resolves in, read synchronously from UserDefaults only.
final class BalanceServicePriceContextTests: XCTestCase {

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
        defaults = makeIsolatedDefaults()
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

    /// `.balance` lines emitted while `perform` runs. The once-per-process
    /// guard is shared across tests, so each log test uses tiers of its own.
    private func balanceLines(_ perform: () -> Void) -> [(level: OSLogType, message: String)] {
        var lines: [(level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ category, level, message in
            if category == .balance { lines.append((level, message)) }
        }, perform: perform)
        return lines
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

    func testMinorUnitDigits_followFoundationCurrencyData() {
        XCTAssertEqual(usd.minorUnitDigits, 2)
        XCTAssertEqual(Currency.rub.minorUnitDigits, 2)
        XCTAssertEqual(Currency(code: "JPY")!.minorUnitDigits, 0)
        XCTAssertEqual(Currency(code: "KWD")!.minorUnitDigits, 3)
    }

    /// #1136 item 3: CLDR, not ISO 4217 — ISO gives HUF and IDR 2 digits.
    func testMinorUnitDigits_areCLDRDigits_notISOMinorUnits() {
        XCTAssertEqual(Currency(code: "HUF")!.minorUnitDigits, 0)
        XCTAssertEqual(Currency(code: "IDR")!.minorUnitDigits, 0)
    }

    func testMinorUnitDigits_ofAnUnknownCode_isTheDefault_loggedOncePerCode() {
        let unknown = Currency(code: "XQQ")!
        let lines = balanceLines { for _ in 1...3 { XCTAssertEqual(unknown.minorUnitDigits, 2) } }

        XCTAssertEqual(lines.filter { $0.message.contains("currency XQQ") }.count, 1, "\(lines)")
        XCTAssertTrue(balanceLines { _ = usd.minorUnitDigits }.isEmpty, "a known code logs nothing")
    }

    // MARK: - Rounding logs (#1136 item 2)

    func testRoundingThatChangesATier_logsANoticeOncePerScale() {
        storeRawScale("USD", ["0.98999999917", "1.99", "2.99"])
        fundWallet(in: usd)

        let lines = balanceLines { for _ in 1...3 { XCTAssertEqual(balance.priceContext, .scale(usdScale)) } }

        let rounded = lines.filter { $0.message.contains("0.98999999917") }
        XCTAssertEqual(rounded.count, 1, "\(lines)")
        XCTAssertEqual(rounded.first?.level, .default)
        XCTAssertTrue(rounded.first?.message.contains("0.99/1.99/2.99") == true, "\(lines)")
    }

    func testRoundingThatLeavesTiersUntouched_logsNothing() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fundWallet(in: usd)

        XCTAssertTrue(balanceLines { _ = balance.priceContext }.isEmpty)
    }

    func testCollapsedTiers_ofAStoredCurrency_logAnErrorNamingUnavailable() {
        storeRawScale("USD", ["0.9917", "0.9944", "2.99"])
        fundWallet(in: usd)

        let lines = balanceLines { XCTAssertEqual(balance.priceContext, .unavailable(usd)) }

        XCTAssertEqual(lines.map(\.level), [.error], "\(lines)")
        XCTAssertTrue(lines.first?.message.contains("unavailable") == true, "\(lines)")
    }

    /// The docstring used to say collapsed tiers always give `.unavailable`; a
    /// pristine wallet falls back to roubles, and the log says so.
    func testCollapsedTiers_ofAPristineWalletsStorefront_fallBackToRoubles_andLogIt() {
        defaults.set("USD", forKey: SnoozePriceScaleStore.lastStorefrontCurrencyKey)
        storeRawScale("USD", ["0.9918", "0.9943", "2.99"])

        let lines = balanceLines { XCTAssertEqual(balance.priceContext, .scale(.rouble)) }

        XCTAssertEqual(lines.map(\.level), [.error], "\(lines)")
        XCTAssertTrue(lines.first?.message.contains("rouble fallback") == true, "\(lines)")
    }

    // MARK: - Injection

    func testConvenienceInit_readsScalesFromItsOwnSuite() {
        XCTAssertTrue(scaleStore.record(usdScale))
        let sameSuite = BalanceService(defaults: defaults, notificationCenter: center)

        XCTAssertEqual(sameSuite.priceContext, .scale(usdScale))
    }
}
