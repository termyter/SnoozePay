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
        daysAgo: Double = 1
    ) -> RestorableTopUp {
        RestorableTopUp(
            transactionID: id,
            productID: "io.mobilife.snoozepay.balance.\(amount)",
            currency: currency,
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
        let purchase = candidate(id: 1, daysAgo: 45)

        service.restore([purchase])

        XCTAssertEqual(
            ledgerRows.first?.createdAt.timeIntervalSince1970 ?? 0,
            purchase.purchaseDate.timeIntervalSince1970,
            accuracy: 1
        )
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
            candidate(id: 2, amount: 299, currency: usd, daysAgo: 3)
        ])

        XCTAssertEqual(balance.walletCurrency, usd)
        XCTAssertEqual(report?.creditedCount, 1)
        XCTAssertEqual(report?.credited, 299)
        XCTAssertEqual(report?.foreignCurrency, 1)
        XCTAssertEqual(balance.balance, 299)
        XCTAssertEqual(ledgerRows.count, 1, "a foreign purchase leaves no row it would be summed out of")
    }

    /// Same storefront throughout: every purchase counts and the wallet ends up
    /// denominated in it.
    func testRestore_creditsEveryPurchaseFromASingleForeignStorefront() {
        let report = service.restore([
            candidate(id: 1, amount: 499, currency: usd, daysAgo: 60),
            candidate(id: 2, amount: 49, currency: usd, daysAgo: 1)
        ])

        XCTAssertEqual(balance.walletCurrency, usd)
        XCTAssertEqual(report?.credited, 548)
        XCTAssertEqual(report?.foreignCurrency, 0)
        XCTAssertEqual(balance.balance, 548)
    }

    /// StoreKit does not always report a currency. Such a transaction is
    /// credited into the wallet as it stands and freezes nothing — guessing is
    /// how a wallet would quietly acquire a currency nobody chose.
    func testRestore_withoutAReportedCurrency_freezesNothing() {
        let report = service.restore([candidate(id: 1, amount: 149, currency: nil)])

        XCTAssertEqual(report?.creditedCount, 1)
        XCTAssertEqual(balance.balance, 149)
        XCTAssertNil(
            testDefaults.string(forKey: WalletCurrencyStore.storageKey),
            "no currency was reported, so none may be recorded"
        )
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
