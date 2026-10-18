import XCTest
@testable import SnoozePay

/// Rebuilding a wallet's paid history from Apple on a clean install (#364).
///
/// The money-critical property is that a transaction is credited **at most
/// once** — Apple keeps handing us the same history on every launch, and the
/// `Transaction.updates` listener sees some of the same rows. Everything else
/// here (currency, unknown SKUs, an empty history) exists so the restore can't
/// buy that property by simply never crediting anything.
@MainActor
final class TopUpRestoreServiceTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var balance: BalanceService!
    private var storeKit: StoreKitService!
    private var service: TopUpRestoreService!

    private let usd = Currency(code: "USD")!
    private let rub = Currency.rub

    override func setUp() {
        super.setUp()
        suiteName = "test_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        balance = BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())
        storeKit = StoreKitService(notificationPoster: LocalNotificationPosterSpy(), defaults: testDefaults)
        service = TopUpRestoreService(balance: balance, storeKit: storeKit)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func candidate(
        id: UInt64,
        amount: Int = 499,
        currency: Currency? = Currency.rub,
        price: Decimal? = nil,
        daysAgo: Double = 1
    ) -> RestorableTopUp {
        RestorableTopUp(
            transactionID: id,
            productID: "io.mobilife.snoozepay.balance.\(amount)",
            currency: currency,
            transactionPrice: price,
            purchaseDate: Date(timeIntervalSinceNow: -daysAgo * 86_400)
        )
    }

    private var ledgerRows: [Transaction] {
        TransactionRepository(defaults: testDefaults).fetchAll()
    }

    // MARK: - The happy path

    func testRestore_creditsEveryPaidTopUp_onACleanInstall() {
        let report = service.restore([
            candidate(id: 1, amount: 499, daysAgo: 30),
            candidate(id: 2, amount: 149, daysAgo: 2)
        ])

        XCTAssertEqual(report?.creditedCount, 2)
        XCTAssertEqual(report?.credited, 648)
        XCTAssertEqual(balance.balance, 648)
        XCTAssertEqual(ledgerRows.count, 2)
        XCTAssertTrue(
            ledgerRows.allSatisfy { $0.type == .topup },
            "restored money is paid revenue, so it must be booked as .topup"
        )
    }

    /// A top-up bought in March is March's revenue. Stamping restored rows with
    /// "now" would move a year of purchases into today's Statistics.
    func testRestore_stampsRowsWithTheOriginalPurchaseDate() {
        let purchase = candidate(id: 1, currency: Currency(code: "EUR"), price: 1.79, daysAgo: 45)

        service.restore([purchase])

        XCTAssertEqual(ledgerRows.first?.amount, 1.79)
        XCTAssertEqual(ledgerRows.first?.currency, Currency(code: "EUR"))
        XCTAssertEqual(
            ledgerRows.first?.createdAt.timeIntervalSince1970 ?? 0,
            purchase.purchaseDate.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testRestore_usesAdjustedRubPriceInsteadOfSkuNominal() {
        XCTAssertEqual(service.restore([candidate(id: 1, amount: 299, price: 249)])?.credited, 249)
        XCTAssertEqual(balance.balance, 249)
        XCTAssertEqual(ledgerRows.first?.currency, rub)
    }

    // MARK: - Idempotency by Transaction.id

    /// The guarantee the whole feature rests on: a transaction already in the
    /// dedup table credits nothing, even on a wallet that otherwise qualifies
    /// for a restore. This is the shape the `Transaction.updates` listener
    /// creates when it gets to a transaction first.
    func testRestore_doesNotCreditATransactionAlreadyProcessed() {
        XCTAssertEqual(storeKit.markProcessed(transactionID: 1), .recorded)

        let report = service.restore([candidate(id: 1, amount: 499)])

        XCTAssertEqual(report?.alreadyCredited, 1)
        XCTAssertEqual(report?.creditedCount, 0)
        XCTAssertEqual(balance.balance, 0)
        XCTAssertTrue(ledgerRows.isEmpty)
    }

    /// Apple returns the same history on the next launch. The wallet is no
    /// longer pristine by then, so the pass does not even run — and if it did,
    /// the dedup table would stop it (asserted above).
    func testRestore_secondPassOverTheSameHistoryCreditsNothing() {
        let history = [candidate(id: 1, amount: 499), candidate(id: 2, amount: 149)]
        service.restore(history)

        let second = service.restore(history)

        XCTAssertNil(second, "a wallet with history is not restored again")
        XCTAssertEqual(balance.balance, 648)
        XCTAssertEqual(ledgerRows.count, 2)
    }

    /// Defensive: the same id twice inside one pass (a duplicated page from
    /// StoreKit, a retry appended to the list) must credit once.
    func testRestore_creditsARepeatedIDOnlyOnce() {
        let report = service.restore([candidate(id: 7), candidate(id: 7)])

        XCTAssertEqual(report?.creditedCount, 1)
        XCTAssertEqual(report?.alreadyCredited, 1)
        XCTAssertEqual(balance.balance, 499)
    }

    // MARK: - The wallet-level gate

    func testRestore_isSkippedWhenTheWalletAlreadyHasHistory() {
        XCTAssertTrue(balance.creditPromotion(amount: 100))

        let report = service.restore([candidate(id: 1, amount: 499)])

        XCTAssertNil(report)
        XCTAssertEqual(balance.balance, 100, "the wallet the user already has must not grow")
        XCTAssertEqual(ledgerRows.count, 1)
    }

    // MARK: - Currency

    /// The wallet is frozen by the first credit (#563), so the pass runs
    /// newest-first: the storefront the user is on now wins. An older purchase
    /// from a storefront they have left is dropped rather than credited as a
    /// number in the wrong currency (#558 — there is no conversion, #559).
    func testRestore_adoptsTheMostRecentCurrencyAndSkipsTheRest() {
        let report = service.restore([
            candidate(id: 1, amount: 999, currency: rub, daysAgo: 400),
            candidate(id: 2, amount: 299, currency: usd, price: 2.99, daysAgo: 3),
            candidate(id: 3, currency: Currency(code: "EUR"), daysAgo: 1)
        ])

        XCTAssertEqual(balance.walletCurrency, usd)
        XCTAssertEqual(report?.creditedCount, 1)
        XCTAssertEqual(report?.credited, 2.99)
        XCTAssertEqual(report?.foreignCurrency, 1)
        XCTAssertEqual(report?.notRecorded, 1, "Newest incomplete metadata must not freeze the wallet")
        XCTAssertEqual(balance.balance, 2.99)
        XCTAssertEqual(ledgerRows.count, 1, "a foreign purchase leaves no row it would be summed out of")
    }

    /// Same storefront throughout: every purchase counts and the wallet ends up
    /// denominated in it.
    func testRestore_creditsEveryPurchaseFromASingleForeignStorefront() {
        let report = service.restore([
            candidate(id: 1, amount: 499, currency: usd, price: 4.99, daysAgo: 60),
            candidate(id: 2, amount: 49, currency: usd, price: 0.49, daysAgo: 1)
        ])

        XCTAssertEqual(balance.walletCurrency, usd)
        XCTAssertEqual(report?.credited ?? 0, 5.48, accuracy: 0.000001)
        XCTAssertEqual(report?.foreignCurrency, 0)
        XCTAssertEqual(balance.balance, 5.48, accuracy: 0.000001)
    }

    func testRestore_withoutReportedCurrency_waitsForMetadataAndCanRetry() {
        let report = service.restore([candidate(id: 1, amount: 149, currency: nil, price: 1.49)])

        XCTAssertEqual(report?.creditedCount, 0)
        XCTAssertEqual(report?.notRecorded, 1)
        XCTAssertEqual(balance.balance, 0)
        XCTAssertTrue(balance.walletIsPristine)
        XCTAssertTrue(ledgerRows.isEmpty)
        XCTAssertNil(testDefaults.object(forKey: "storekit.processed_tx_ids"))
        XCTAssertNil(testDefaults.string(forKey: WalletCurrencyStore.storageKey))
        XCTAssertEqual(service.restore([candidate(id: 1, amount: 149)])?.credited, 149)
    }

    func testRestore_invalidMetadataDoesNotMutateWalletOrDedup() {
        let before = testDefaults.persistentDomain(forName: suiteName) as NSDictionary?
        let report = service.restore([
            candidate(id: 1, currency: usd),
            candidate(id: 2, currency: usd, price: .nan),
            candidate(id: 3, price: 0),
            candidate(id: 4, price: -1)
        ])

        XCTAssertEqual(report?.notRecorded, 4)
        XCTAssertTrue(balance.walletIsPristine)
        XCTAssertEqual(testDefaults.persistentDomain(forName: suiteName) as NSDictionary?, before)
    }

    // MARK: - Nothing to restore

    func testRestore_withNoTransactions_leavesThePristineWalletAlone() {
        let report = service.restore([])

        XCTAssertEqual(report, TopUpRestoreReport())
        XCTAssertEqual(balance.balance, 0)
        XCTAssertTrue(ledgerRows.isEmpty)
        XCTAssertNil(testDefaults.string(forKey: WalletCurrencyStore.storageKey))
        XCTAssertTrue(balance.walletIsPristine, "an empty history must leave the wallet restorable later")
    }

    /// A SKU that is not one of ours — a package from a future build, or one
    /// this build was rolled back past. It has no amount here, and inventing
    /// one from the storefront price is how display and credit diverge (#557).
    func testRestore_ignoresAProductWeDoNotSell() {
        let report = service.restore([
            RestorableTopUp(
                transactionID: 1,
                productID: "io.mobilife.snoozepay.balance.1999",
                currency: rub,
                transactionPrice: 19.99,
                purchaseDate: Date()
            ),
            candidate(id: 2, amount: 49)
        ])

        XCTAssertEqual(report?.unknownProduct, 1)
        XCTAssertEqual(report?.creditedCount, 1)
        XCTAssertEqual(balance.balance, 49)
    }

    // MARK: - Degraded dedup table

    /// With the dedup table's plist type drifted (#209) there is no answer to
    /// "was this already credited?". The pass stops instead of guessing, and
    /// the wallet stays pristine so a later launch can retry.
    func testRestore_abortsWhenTheDedupTableIsDegraded() {
        testDefaults.set(["not": "an array of strings"], forKey: "storekit.processed_tx_ids")

        let report = service.restore([candidate(id: 1, amount: 499)])

        XCTAssertEqual(report?.creditedCount, 0)
        XCTAssertEqual(balance.balance, 0)
        XCTAssertTrue(balance.walletIsPristine)
    }
}
