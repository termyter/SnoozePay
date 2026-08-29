import XCTest
@testable import SnoozePay

/// The wallet's currency: where it comes from, that it is written once, and
/// what happens to a wallet that predates the whole idea (#563).
final class WalletCurrencyTests: XCTestCase {

    /// Fresh suite per test — the wallet currency is a once-only write, so a
    /// leaked value from a previous test would make the next one pass or fail
    /// for the wrong reason.
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!

    override func setUp() {
        super.setUp()
        suiteName = "test_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Isolated `NotificationCenter` so balance broadcasts don't reach the
    /// observers the host app has attached to `.default`.
    private func makeService(balance: Double = 0) -> BalanceService {
        testDefaults.set(balance, forKey: "user_balance")
        return BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())
    }

    private var storedCurrencyCode: String? {
        testDefaults.string(forKey: WalletCurrencyStore.storageKey)
    }

    // MARK: - First paid top-up establishes the currency

    func testFirstPaidTopUp_establishesWalletCurrency() {
        let service = makeService()
        XCTAssertNil(storedCurrencyCode, "a fresh wallet has no currency yet")

        XCTAssertEqual(service.topUpFromPurchase(amount: 299, currency: usd), .credited)

        XCTAssertEqual(service.walletCurrency, usd)
        XCTAssertEqual(storedCurrencyCode, "USD")
        XCTAssertEqual(service.balance, 299)
        XCTAssertEqual(
            service.balanceMoney.currency,
            usd,
            "the typed balance must report the wallet's currency, not the legacy rouble"
        )
    }

    /// The ledger row must be stamped with the *frozen* currency, not with the
    /// currency the wallet had a moment earlier — otherwise
    /// `BalanceLedger.net(of:in:)` drops it and the credit evaporates on the
    /// next read.
    func testFirstPaidTopUp_stampsLedgerRowWithTheNewCurrency() throws {
        let service = makeService()
        XCTAssertEqual(service.topUpFromPurchase(amount: 299, currency: usd), .credited)

        let rows = try TransactionRepository(defaults: testDefaults).fetchAllChecked()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.currency, usd)
        XCTAssertEqual(service.balance, 299, "the row must survive the currency-filtered sum")
    }

    func testSecondTopUpInSameCurrency_credits() {
        let service = makeService()
        XCTAssertEqual(service.topUpFromPurchase(amount: 299, currency: usd), .credited)

        XCTAssertEqual(service.topUpFromPurchase(amount: 149, currency: usd), .credited)

        XCTAssertEqual(service.balance, 448)
        XCTAssertEqual(service.walletCurrency, usd)
    }

    func testEstablishedCurrency_survivesRestart() {
        XCTAssertEqual(makeService().topUpFromPurchase(amount: 299, currency: usd), .credited)

        let afterRelaunch = BalanceService(
            defaults: testDefaults,
            notificationCenter: NotificationCenter()
        )
        XCTAssertEqual(afterRelaunch.walletCurrency, usd)
        XCTAssertEqual(afterRelaunch.balance, 299)
    }

    // MARK: - Foreign storefront

    /// The gate the top-up screens consult *before* `Product.purchase(_:)`.
    /// Refusing here is the whole point: after Apple has taken the money the
    /// only options left are crediting a number denominated in something else
    /// (#558) or keeping the money with nothing credited.
    func testForeignCurrency_isRefusedBeforePurchase() {
        let service = makeService()
        XCTAssertEqual(service.topUpFromPurchase(amount: 299, currency: usd), .credited)

        XCTAssertTrue(service.acceptsPurchase(in: usd))
        XCTAssertFalse(service.acceptsPurchase(in: eur))
        XCTAssertFalse(service.acceptsPurchase(in: .rub))
    }

    func testForeignCurrency_creditsNothingIfItSomehowReachesTheWallet() throws {
        let service = makeService()
        XCTAssertEqual(service.topUpFromPurchase(amount: 299, currency: usd), .credited)

        XCTAssertEqual(
            service.topUpFromPurchase(amount: 500, currency: eur),
            .refusedCurrency(wallet: usd, purchase: eur)
        )

        XCTAssertEqual(service.balance, 299, "a refused purchase must not move the balance")
        XCTAssertEqual(service.walletCurrency, usd, "and must not re-denominate the wallet")
        let rows = try TransactionRepository(defaults: testDefaults).fetchAllChecked()
        XCTAssertEqual(rows.count, 1)
    }

    /// StoreKit does not always report a currency. Crediting into the wallet's
    /// existing currency is right; *guessing* one for an unset wallet is not.
    func testPurchaseWithoutReportedCurrency_creditsButEstablishesNothing() {
        let service = makeService()

        XCTAssertEqual(service.topUpFromPurchase(amount: 149, currency: nil), .credited)

        XCTAssertEqual(service.balance, 149)
        XCTAssertNil(storedCurrencyCode)
        XCTAssertEqual(service.walletCurrency, .legacyDefault)
    }

    // MARK: - DEBUG fallback

    /// `topUp(amount:)` is what the top-up sheets fall back to under `#if DEBUG`
    /// when the StoreKit catalogue is empty (simulator, no `.storekit` file).
    /// If that path established a currency, a single debug top-up would
    /// permanently denominate the wallet.
    func testDebugFallbackTopUp_doesNotEstablishCurrency() {
        let service = makeService()

        XCTAssertTrue(service.topUp(amount: 100))

        XCTAssertNil(storedCurrencyCode)
        XCTAssertEqual(service.walletCurrency, .legacyDefault)
        XCTAssertFalse(
            service.acceptsPurchase(in: usd),
            "the 100 credited above is rouble-denominated, so the wallet is no longer free to adopt USD"
        )
        XCTAssertTrue(service.acceptsPurchase(in: .rub))
    }

    // MARK: - Legacy wallets (no record at all)

    func testLegacyWalletWithoutRecord_readsAsRoubles() {
        let service = makeService(balance: 500)

        XCTAssertEqual(service.walletCurrency, .rub)
        XCTAssertEqual(service.balanceMoney.currency, .rub)
        XCTAssertEqual(service.balanceMoney.amount, 500)
    }

    /// A legacy wallet holds roubles in its balance, its ledger rows and its
    /// configured penalties. It may record that fact, and nothing else.
    func testLegacyWalletWithBalance_acceptsRoublesOnlyAndRecordsThem() {
        let service = makeService(balance: 500)

        XCTAssertFalse(service.acceptsPurchase(in: usd))
        XCTAssertTrue(service.acceptsPurchase(in: .rub))

        XCTAssertEqual(service.topUpFromPurchase(amount: 149, currency: .rub), .credited)

        XCTAssertEqual(storedCurrencyCode, "RUB")
        XCTAssertEqual(service.balance, 649)
    }

    func testLegacyWalletWithBalance_refusesForeignPurchaseOutright() {
        let service = makeService(balance: 500)

        XCTAssertEqual(
            service.topUpFromPurchase(amount: 299, currency: usd),
            .refusedCurrency(wallet: .rub, purchase: usd)
        )
        XCTAssertEqual(service.balance, 500)
        XCTAssertNil(storedCurrencyCode)
    }

    // MARK: - Writing the currency is a once-only operation

    func testFreeze_isIdempotentForTheSameCurrencyAndRefusesAnyOther() {
        let store = WalletCurrencyStore(defaults: testDefaults)

        XCTAssertEqual(store.freeze(usd), .frozen(usd))
        XCTAssertEqual(store.freeze(usd), .unchanged(usd), "replayed freeze is a no-op, not a failure")
        XCTAssertEqual(
            store.freeze(.rub),
            .refused(existing: usd, attempted: .rub),
            "re-denominating a wallet must fail loudly, not silently succeed or silently do nothing"
        )
        XCTAssertEqual(store.currency, usd)
        XCTAssertEqual(storedCurrencyCode, "USD")
    }

    func testUnreadableRecord_readsAsUnsetRatherThanTrapping() {
        testDefaults.set("руб", forKey: WalletCurrencyStore.storageKey)
        let store = WalletCurrencyStore(defaults: testDefaults)

        XCTAssertNil(store.storedCurrency)
        XCTAssertEqual(store.currency, .legacyDefault)
    }

    // MARK: - User-facing copy

    func testForeignCurrencyNotice_namesBothCurrenciesAndKeepsTheBalanceSpendable() {
        let text = ForeignCurrencyNotice.message(
            wallet: .rub,
            storefront: usd,
            locale: Locale(identifier: "ru_RU")
        )

        XCTAssertTrue(text.contains("RUB"), text)
        XCTAssertTrue(text.contains("USD"), text)
        XCTAssertTrue(text.contains("Пополнение в другой валюте недоступно"), text)
        XCTAssertTrue(
            text.contains("тратить как обычно"),
            "the block is on topping up, not on spending — the copy has to say so"
        )
    }

    /// A code the OS has no name for still has to render as something a support
    /// ticket can quote.
    func testForeignCurrencyNotice_fallsBackToTheBareCodeWhenUnnamed() {
        let unnamed = Currency(code: "ZZZ")!
        let text = ForeignCurrencyNotice.message(
            wallet: .rub,
            storefront: unnamed,
            locale: Locale(identifier: "ru_RU")
        )

        XCTAssertTrue(text.contains("ZZZ"), text)
        XCTAssertFalse(
            text.contains("ZZZ (ZZZ)"),
            "when the OS hands back the code as its own name, don't print it twice"
        )
    }
}
