import XCTest
import AlarmKit
@testable import SnoozePay

private typealias AppAlarm = SnoozePay.Alarm

/// AlarmKit snooze labels quote the price from the snooze-price context (#1138):
/// which context a wallet quotes in, and what title each context bakes.
final class AlarmKitPriceQuoteTests: XCTestCase {

    private var defaults: UserDefaults!
    private var scaleStore: SnoozePriceScaleStore!
    private var balance: BalanceService!

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!
    private var usdScale: SnoozePriceScale { SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])! }

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        let center = NotificationCenter()
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

    private func title(_ alarm: AppAlarm, _ quote: SnoozePriceContext?, nextSnoozeCount: Int = 1) -> String? {
        AlarmKitScheduler.makePresentation(for: alarm, quote: quote, nextSnoozeCount: nextSnoozeCount)
            .alert.secondaryButton.map { String(localized: $0.text) }
    }

    private func priced(_ amount: String, _ currency: Currency) -> String {
        let money = MoneyFormatter.string(Decimal(string: amount)!, currency: currency)
        return Localized.format(AlarmKitCopy.pricedSnoozeKey, money)
    }

    private var unpriced: String { Localized.text(AlarmKitCopy.snoozeKey) }

    // MARK: - Which context a wallet quotes in

    func testPristineWalletWithoutAStorefrontScale_quotesNothing() {
        XCTAssertNil(balance.alarmQuoteContext)
        XCTAssertNil(balance.alarmQuoteCurrency)
    }

    func testPristineWalletWithACachedStorefrontScale_quotesThatScale() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(balance.alarmQuoteContext, .scale(usdScale))
        XCTAssertTrue(balance.walletIsPristine, "quoting must not freeze or touch the wallet")
    }

    /// A storefront is known but its cached scale is unreadable: `priceContext`
    /// falls back to roubles; the label must not bake ₽ into a wallet that may
    /// still adopt dollars.
    func testPristineWalletWithACorruptStorefrontScale_quotesNothing() {
        defaults.set("USD", forKey: SnoozePriceScaleStore.lastStorefrontCurrencyKey)
        defaults.set(["USD": [SnoozePriceScaleStore.tiersField: ["x"]]], forKey: SnoozePriceScaleStore.scalesKey)
        XCTAssertEqual(balance.priceContext, .scale(.rouble))
        XCTAssertNil(balance.alarmQuoteContext)
    }

    /// Intended change (#1138): a pristine wallet on a rouble storefront quotes
    /// «−50 ₽» (was unpriced before the first purchase).
    func testPristineWalletOnACachedRoubleStorefront_quotesRoubles() {
        XCTAssertTrue(scaleStore.record(.rouble))
        XCTAssertTrue(balance.walletIsPristine)
        XCTAssertEqual(balance.alarmQuoteContext, .scale(.rouble))
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 50), balance.alarmQuoteContext), priced("50", .rub))
    }

    func testLegacyRoubleWalletWithHistory_quotesRoubles() {
        balance.topUp(amount: 5)
        XCTAssertEqual(balance.alarmQuoteContext, .scale(.rouble))
        XCTAssertEqual(balance.alarmQuoteCurrency, .rub)
    }

    func testFrozenWalletWithoutItsScale_isUnavailable() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(balance.topUpFromPurchase(amount: 10, currency: eur), .credited)
        XCTAssertEqual(balance.alarmQuoteContext, .unavailable(eur))
        XCTAssertEqual(balance.alarmQuoteCurrency, eur)
    }

    func testFrozenUSDWalletWithItsScale_quotesIt() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(balance.topUpFromPurchase(amount: 10, currency: usd), .credited)
        XCTAssertEqual(balance.alarmQuoteContext, .scale(usdScale))
    }

    // MARK: - What each context bakes

    func testUSDScale_legacyFiftyQuotesTheLowTier() {
        let title = title(AppAlarm(penaltyAmount: 50), .scale(usdScale))
        XCTAssertEqual(title, priced("0.99", usd))
        XCTAssertFalse(title?.contains("50") ?? true, "a legacy rouble amount must never be shown as dollars")
    }

    func testUSDScale_tierAlarmQuotesItsTier() {
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 50, penaltyTier: .mid), .scale(usdScale)), priced("1.99", usd))
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 50, penaltyTier: .high), .scale(usdScale)), priced("2.99", usd))
    }

    func testUSDScale_progressiveCountDoublesTheResolvedBase() {
        let alarm = AppAlarm(penaltyAmount: 50, progressiveScale: true)
        let titles = (1...5).map { title(alarm, .scale(usdScale), nextSnoozeCount: $0) }
        XCTAssertEqual(titles, ["0.99", "1.98", "3.96", "7.92", "7.92"].map { priced($0, usd) })
    }

    func testUnavailableContext_bakesTheUnpricedTitle() {
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 50), .unavailable(usd)), unpriced)
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 50, penaltyTier: .low), .unavailable(eur)), unpriced)
    }

    func testNoQuote_bakesTheUnpricedTitle() {
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 50, penaltyTier: .mid), nil), unpriced)
    }

    /// Rouble wallets keep today's titles: the raw amount, today's ladder.
    func testRoubleScale_keepsTheRawAmountAndLadder() {
        let alarm = AppAlarm(penaltyAmount: 50, progressiveScale: true)
        let titles = (1...5).map { title(alarm, .scale(.rouble), nextSnoozeCount: $0) }
        let today = (1...5).map {
            AlarmKitCopy.pricedSnooze(penalty: alarm.penalty(forSnoozeCount: $0), currency: .rub)
        }
        XCTAssertEqual(titles, today)
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 20), .scale(.rouble)), AlarmKitCopy.pricedSnooze(penalty: 20))
    }

    // MARK: - Tracked snooze (token branch)

    private func trackedSnoozeTitle(_ quote: SnoozePriceContext?) throws -> String? {
        let alarm = AppAlarm(penaltyAmount: 50, progressiveScale: true)
        var title: String?
        _ = try AlarmKitScheduler.makeSnoozeConfiguration(
            for: alarm, fireDate: Date().addingTimeInterval(60), quote: quote,
            token: AlarmSnoozeToken(sessionID: UUID(), attemptID: UUID()), attemptCount: 1,
            construct: { schedule, attributes, stop, snooze, sound in
                title = attributes.presentation.alert.secondaryButton.map { String(localized: $0.text) }
                return .alarm(schedule: schedule, attributes: attributes,
                              stopIntent: stop, secondaryIntent: snooze, sound: sound)
            }
        )
        return title
    }

    func testTrackedSnooze_inAUSDScale_quotesTheNextProgressiveStep() throws {
        XCTAssertEqual(try trackedSnoozeTitle(.scale(usdScale)), priced("1.98", usd))
    }

    func testTrackedSnooze_withoutAQuote_isUnpriced() throws {
        XCTAssertEqual(try trackedSnoozeTitle(nil), unpriced)
    }

    func testFreeAlarm_staysFreeOutsideRoubles() {
        XCTAssertEqual(title(AppAlarm(penaltyAmount: 0), .scale(usdScale)), priced("0", usd))
    }
}
