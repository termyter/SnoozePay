import XCTest
@testable import SnoozePay

@MainActor
final class StoreKitVerifiedPurchaseTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var balance: BalanceService!
    private var store: StoreKitService!
    private var poster: LocalNotificationPosterSpy!
    private let usd = Currency(code: "USD")!
    private var rows: [Transaction] { TransactionRepository(defaults: defaults).fetchAll() }

    override func setUp() {
        super.setUp()
        suite = "StoreKitVerifiedPurchaseTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        balance = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        poster = LocalNotificationPosterSpy()
        store = StoreKitService(notificationPoster: poster, defaults: defaults)
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
        XCTAssertTrue(balance.canAfford(2.99), "The paid amount must cover an equal snooze price")
    }

    func testResolverPreservesNonCentFractionInRubAndUsd() throws {
        let price = try XCTUnwrap(Decimal(string: "1.2345", locale: Locale(identifier: "en_US_POSIX")))
        for currency in [Currency.rub, usd] {
            XCTAssertEqual(StoreKitService.creditAmount(for: "io.mobilife.snoozepay.balance.299",
                                                       transactionPrice: price, currency: currency), 1.2345)
        }
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

    func testDegradedDedupRefusesValidPaidPurchaseWithoutWalletMutationOrFinish() async {
        let corrupt = ["unexpected": 7]
        let previousBackup = Data("previous corrupt dedup blob".utf8)
        defaults.set(corrupt, forKey: "storekit.processed_tx_ids")
        defaults.set(previousBackup, forKey: StoreKitService.processedBackupCorruptKey)
        let previousLedger = defaults.data(forKey: "stored_transactions")
        var finishes = 0

        for _ in 0..<2 {
            await store.applyVerifiedPurchase(purchase(currency: usd), balance: balance) { finishes += 1 }
            XCTAssertEqual(finishes, 0)
            XCTAssertEqual(balance.balance, 0)
            XCTAssertTrue(rows.isEmpty)
            XCTAssertTrue(balance.walletIsPristine)
            XCTAssertNil(defaults.object(forKey: WalletCurrencyStore.storageKey))
            XCTAssertEqual(defaults.data(forKey: "stored_transactions"), previousLedger)
            XCTAssertEqual(defaults.object(forKey: "storekit.processed_tx_ids") as? [String: Int], corrupt)
            XCTAssertEqual(defaults.data(forKey: StoreKitService.processedBackupCorruptKey), previousBackup)
        }
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

    func testDeferredUsdCreditNotifiesOnceWithReceiptAmountAndCurrency() async {
        store.endObservingPurchaseFeedback()
        var finishes = 0
        let candidate = purchase(currency: usd)
        await store.applyVerifiedPurchase(candidate, balance: balance) { finishes += 1 }
        await store.applyVerifiedPurchase(candidate, balance: balance) { finishes += 1 }

        XCTAssertEqual(finishes, 2, "Replays finish without crediting or notifying twice")
        XCTAssertEqual(balance.balance, 2.99)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.amount, 2.99)
        XCTAssertEqual(rows.first?.currency, usd)
        XCTAssertEqual(poster.requests.count, 1)
        let request = poster.requests.first
        XCTAssertEqual(request?.content.title, "Баланс пополнен")
        XCTAssertEqual(request?.content.body, "Баланс пополнен на \(MoneyFormatter.string(2.99, currency: usd)).")
        XCTAssertFalse(request?.content.body.contains("₽") ?? true)
        XCTAssertNil(request?.trigger)
    }

    func testDeferredRubCreditPreservesPaidKopecks() async {
        store.endObservingPurchaseFeedback()
        var finishes = 0
        await store.applyVerifiedPurchase(purchase(price: 149.99, currency: .rub), balance: balance) {
            finishes += 1
            XCTAssertEqual(self.balance.balance, 149.99)
            XCTAssertTrue(self.poster.requests.isEmpty, "Feedback follows successful finish")
        }

        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(rows.first?.amount, 149.99)
        XCTAssertEqual(rows.first?.currency, .rub)
        XCTAssertEqual(poster.requests.count, 1)
        XCTAssertEqual(poster.requests.first?.content.body, "Баланс пополнен на 149,99\u{202F}₽.")
    }

    func testVerifiedCreditWithSubscriberBroadcastsActualAmountWithoutLocalNotification() async {
        let observedStore = store!
        var received: [Notification] = []
        let token = NotificationCenter.default.addObserver(
            forName: StoreKitService.purchaseCompletedNotification, object: nil, queue: nil
        ) { note in
            guard (note.object as? StoreKitService) === observedStore else { return }
            received.append(note)
        }
        defer { NotificationCenter.default.removeObserver(token) }

        var finishes = 0
        await store.applyVerifiedPurchase(purchase(currency: usd), balance: balance) { finishes += 1 }

        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(balance.balance, 2.99)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.userInfo?[StoreKitService.amountUserInfoKey] as? Double, 2.99)
        XCTAssertTrue(poster.requests.isEmpty)
    }
}
