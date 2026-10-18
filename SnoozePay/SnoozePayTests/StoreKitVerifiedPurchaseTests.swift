import XCTest
@testable import SnoozePay

@MainActor
final class StoreKitVerifiedPurchaseTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var balance: BalanceService!
    private var store: StoreKitService!
    private let usd = Currency(code: "USD")!
    private var rows: [Transaction] { TransactionRepository(defaults: defaults).fetchAll() }

    override func setUp() {
        super.setUp()
        suite = "StoreKitVerifiedPurchaseTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        balance = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        store = StoreKitService(notificationPoster: LocalNotificationPosterSpy(), defaults: defaults)
        store.beginObservingPurchaseFeedback()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func purchase(price: Decimal? = 2.99, currency: Currency? = nil) -> RestorableTopUp {
        RestorableTopUp(transactionID: 7, productID: "io.mobilife.snoozepay.balance.299",
                       currency: currency, transactionPrice: price,
                       purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testVerifiedPriceAndCurrencyAreCommittedBeforeFinish() async {
        var finishes = 0
        await store.applyVerifiedPurchase(purchase(currency: usd), balance: balance) {
            finishes += 1
            XCTAssertEqual(self.balance.balance, 2.99)
            XCTAssertEqual(self.rows.first?.amount, 2.99)
            XCTAssertEqual(self.rows.first?.currency, self.usd)
            XCTAssertEqual(self.defaults.stringArray(forKey: "storekit.processed_tx_ids"), ["7"])
        }
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(balance.walletCurrency, usd)
    }

    func testAbsentPriceWithExplicitRubUsesApprovedNominalFallback() async {
        var finishes = 0
        await store.applyVerifiedPurchase(purchase(price: nil, currency: .rub), balance: balance) { finishes += 1 }
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(balance.balance, 299)
        XCTAssertEqual(rows.first?.currency, .rub)
    }

    func testInvalidMetadataHasNoSideEffectsOrFinishAndValidRetryCredits() async {
        let before = defaults.persistentDomain(forName: suite) as NSDictionary?
        let inputs: [(Decimal?, Currency?)] = [(nil, usd), (2.99, nil), (nil, nil), (.nan, .rub), (0, .rub), (-1, .rub)]
        var finishes = 0
        for (price, currency) in inputs {
            await store.applyVerifiedPurchase(purchase(price: price, currency: currency), balance: balance) {
                finishes += 1
            }
            XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, before)
            XCTAssertTrue(balance.walletIsPristine)
        }
        XCTAssertEqual(finishes, 0)
        await store.applyVerifiedPurchase(purchase(currency: usd), balance: balance) { finishes += 1 }
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(balance.balance, 2.99)
    }

    func testForeignCurrencyAndLedgerFailureRollbackOnlyCurrentDedupMark() async {
        XCTAssertEqual(store.markProcessed(transactionID: 41), .recorded)
        _ = balance.freezeCurrency(.rub)
        var finishes = 0
        await store.applyVerifiedPurchase(purchase(currency: usd), balance: balance) { finishes += 1 }
        XCTAssertEqual(balance.balance, 0)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: "storekit.processed_tx_ids"), ["41"])

        let corrupt = Data("corrupt ledger".utf8)
        defaults.set(corrupt, forKey: "stored_transactions")
        balance = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        await store.applyVerifiedPurchase(purchase(currency: .rub), balance: balance) { finishes += 1 }
        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(balance.balance, 0)
        XCTAssertEqual(defaults.data(forKey: "stored_transactions"), corrupt)
        XCTAssertEqual(defaults.stringArray(forKey: "storekit.processed_tx_ids"), ["41"])
    }

    func testRestoreAndLiveReplayShareDedupAndFinishWithoutDoubleCredit() async {
        let candidate = purchase(currency: usd)
        let restore = TopUpRestoreService(balance: balance, storeKit: store)
        XCTAssertEqual(restore.restore([candidate])?.credited, 2.99)
        var finishes = 0
        await store.applyVerifiedPurchase(candidate, balance: balance) { finishes += 1 }
        await store.applyVerifiedPurchase(candidate, balance: balance) { finishes += 1 }
        XCTAssertEqual(finishes, 2)
        XCTAssertEqual(balance.balance, 2.99)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.createdAt, candidate.purchaseDate)
        XCTAssertNil(restore.restore([candidate]), "Existing wallet history still blocks a second restore")
    }

    func testAlreadyProcessedHistoricalCreditIsNotRecalculated() async {
        XCTAssertEqual(balance.topUpFromPurchase(amount: 299, currency: usd), .credited)
        XCTAssertEqual(store.markProcessed(transactionID: 7), .recorded)
        var finishes = 0
        await store.applyVerifiedPurchase(purchase(currency: usd), balance: balance) { finishes += 1 }
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(balance.balance, 299)
        XCTAssertEqual(rows.count, 1)
    }
}
