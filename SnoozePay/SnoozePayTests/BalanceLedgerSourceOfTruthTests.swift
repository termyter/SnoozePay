import XCTest
@testable import SnoozePay

/// The ledger is the source of truth for the wallet (#483): the balance is
/// `openingBalance + Σ(rows)` and `user_balance` is only a cache of that sum.
/// This is money — every rule below is a way a user loses or invents some.
final class BalanceLedgerSourceOfTruthTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.balanceLedger.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService(balance: Double = 0) -> BalanceService {
        testDefaults.set(balance, forKey: "user_balance")
        return BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())
    }

    private func makeLedger() -> TransactionRepository {
        TransactionRepository(defaults: testDefaults)
    }

    private func cachedBalance() -> Double {
        testDefaults.double(forKey: "user_balance")
    }

    // MARK: - Recomputation

    func testNet_topupChargePromotion_sumsToTheWalletMovement() {
        let entries = [
            Transaction(type: .topup, amount: 500),
            Transaction(type: .charge, amount: 150),
            Transaction(type: .promotion, amount: 100),
            Transaction(type: .refund, amount: 50)
        ]

        XCTAssertEqual(BalanceLedger.net(of: entries, in: .legacyDefault), 500, accuracy: 0.0001)
    }

    /// The repository hands rows back newest-first, a CloudKit query would hand
    /// them back in whatever order it pleases. The sum must not care.
    func testNet_recordOrder_doesNotChangeTheResult() {
        let now = Date()
        let entries = [
            Transaction(type: .topup, amount: 300, createdAt: now.addingTimeInterval(-600)),
            Transaction(type: .charge, amount: 50, createdAt: now.addingTimeInterval(-300)),
            Transaction(type: .promotion, amount: 25, createdAt: now)
        ]

        XCTAssertEqual(BalanceLedger.net(of: entries, in: .legacyDefault), 275, accuracy: 0.0001)
        XCTAssertEqual(BalanceLedger.net(of: Array(entries.reversed()), in: .legacyDefault), 275, accuracy: 0.0001,
                       "Reversing the ledger must not change the balance")
    }

    func testNet_duplicateTransactionID_countedOnce() {
        let replayed = Transaction(id: UUID(), type: .topup, amount: 499)

        XCTAssertEqual(BalanceLedger.net(of: [replayed, replayed, replayed], in: .legacyDefault), 499, accuracy: 0.0001,
                       "A row replayed by a resync/Restore must credit exactly once")
    }

    func testNet_unrecognizedAndNonPositiveRows_areSkipped() {
        let entries = [
            Transaction(type: .topup, amount: 100),
            Transaction(type: .unknown("voucher"), amount: 70),
            Transaction(type: .topup, amount: 0),
            Transaction(type: .charge, amount: -25)
        ]

        XCTAssertEqual(BalanceLedger.net(of: entries, in: .legacyDefault), 100, accuracy: 0.0001,
                       "A row whose direction the build can't state must not move money")
    }

    // MARK: - Idempotent writes

    func testStoreAppend_sameTransactionTwice_reportsDuplicateAndWritesOneRow() {
        let ledger = makeLedger()
        let store = LocalBalanceLedgerStore(repository: ledger, defaults: testDefaults)
        let transaction = Transaction(type: .topup, amount: 149)

        XCTAssertEqual(store.append(transaction), .recorded)
        XCTAssertEqual(store.append(transaction), .duplicate,
                       "Replaying an id must be reported, not appended")
        XCTAssertEqual(ledger.fetchAllOrFail().count, 1)
    }

    /// The end-to-end shape of a resync: the ledger physically holds the same
    /// id twice (written behind the service's back), the wallet must not.
    func testBalance_duplicateRowInLedger_isNotCreditedTwice() {
        let service = makeService(balance: 100)
        let ledger = makeLedger()
        let replayed = Transaction(type: .topup, amount: 200)

        XCTAssertTrue(ledger.record(replayed))
        XCTAssertTrue(ledger.record(replayed))

        XCTAssertEqual(service.balance, 300, accuracy: 0.0001,
                       "Two rows sharing one id are one credit, not two")
    }

    // MARK: - Derived balance

    func testBalance_followsTheLedgerAcrossTopUpChargePromotion() {
        let service = makeService(balance: 0)

        XCTAssertTrue(service.topUp(amount: 300))
        XCTAssertTrue(service.charge(amount: 50, alarmID: nil))
        XCTAssertTrue(service.creditPromotion(amount: 25))

        XCTAssertEqual(service.balance, 275, accuracy: 0.0001)
        XCTAssertEqual(cachedBalance(), 275, accuracy: 0.0001,
                       "`user_balance` must stay a faithful cache of the ledger sum")
    }

    /// A cache written behind the ledger's back (concurrent write, downgrade)
    /// loses: the rows are the wallet.
    func testBalance_cacheDisagreesWithLedger_ledgerWinsAndCacheIsRepaired() {
        let service = makeService(balance: 100)
        XCTAssertTrue(service.topUp(amount: 50))

        testDefaults.set(9_999.0, forKey: "user_balance")

        XCTAssertEqual(service.balance, 150, accuracy: 0.0001)
        XCTAssertEqual(cachedBalance(), 150, accuracy: 0.0001)
    }

    // MARK: - Refund

    func testRefund_afterCharge_restoresTheExactBalance() {
        let service = makeService(balance: 200)
        let receipt = service.chargeWithReceipt(amount: 50, alarmID: nil)
        XCTAssertNotNil(receipt)
        XCTAssertEqual(service.balance, 150, accuracy: 0.0001)

        XCTAssertTrue(service.refund(amount: 50, refundsTransactionID: receipt?.id))

        XCTAssertEqual(service.balance, 200, accuracy: 0.0001,
                       "A reversal returns the penalty — it neither overshoots nor undershoots")
    }

    /// A refund is a credit, so it can never push the wallet below zero — and
    /// a ledger that sums below zero (damage, not a reachable API state) must
    /// route through the #119 corruption gate instead of reporting a negative.
    func testBalance_ledgerSummingBelowZero_clampsToZeroAndLatchesCorruption() {
        let service = makeService(balance: 100)
        let ledger = makeLedger()

        XCTAssertTrue(ledger.record(Transaction(type: .charge, amount: 500)))

        XCTAssertEqual(service.balance, 0, accuracy: 0.0001,
                       "A negative derived balance is reported as an empty wallet")
        XCTAssertTrue(service.balanceCorrupted, "…and gates further mutation")
        XCTAssertFalse(service.topUp(amount: 50), "Mutations stay blocked until acknowledged")
    }

    func testAcknowledgeCorruption_rebasesTheLedgerSoBalanceStaysZero() {
        let service = makeService(balance: 100)
        let ledger = makeLedger()
        XCTAssertTrue(ledger.record(Transaction(type: .charge, amount: 500)))
        XCTAssertEqual(service.balance, 0, accuracy: 0.0001)

        service.acknowledgeCorruption()

        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertEqual(service.balance, 0, accuracy: 0.0001,
                       "Without a re-pinned opening balance the old rows would resurrect the wallet")
        XCTAssertTrue(service.topUp(amount: 50))
        XCTAssertEqual(service.balance, 50, accuracy: 0.0001)
    }

    // MARK: - Existing installs

    /// The switch to a derived balance ships without a migration pass: the
    /// opening balance is adopted on first read so an install whose ledger
    /// doesn't reconcile with `user_balance` (rows pruned, pre-ledger money)
    /// sees exactly the number it saw yesterday.
    func testExistingLedger_isReadWithoutMigrationLoss() {
        let ledger = makeLedger()
        XCTAssertTrue(ledger.record(Transaction(type: .topup, amount: 500)))
        XCTAssertTrue(ledger.record(Transaction(type: .charge, amount: 100)))
        // The stored balance deliberately disagrees with Σ(ledger) = 400 —
        // that's what a real install looks like before #483.
        let service = makeService(balance: 250)

        XCTAssertEqual(service.balance, 250, accuracy: 0.0001,
                       "Adoption must preserve the user's money to the cent")

        XCTAssertTrue(service.topUp(amount: 50))
        XCTAssertEqual(service.balance, 300, accuracy: 0.0001,
                       "…and the ledger drives every movement from there on")
    }

    func testAdoptedOpeningBalance_isPersistedOnceAndNotReAdopted() {
        let service = makeService(balance: 80)
        XCTAssertEqual(testDefaults.object(forKey: LocalBalanceLedgerStore.openingBalanceKey) as? Double,
                       80, "First read adopts the pre-ledger money")

        XCTAssertTrue(service.charge(amount: 30, alarmID: nil))

        XCTAssertEqual(testDefaults.object(forKey: LocalBalanceLedgerStore.openingBalanceKey) as? Double,
                       80, "The opening balance is a one-time anchor, not a running total")
        XCTAssertEqual(service.balance, 50, accuracy: 0.0001)
    }

    // MARK: - Mixed currencies (#562)
    //
    // A ledger row states its own currency, and the app has no rate source
    // (#559). So `Σ` over mixed currencies is not a quantity: the cache is
    // defined as the sum of the rows denominated in the wallet's own currency,
    // and a foreign row is visible in history but invisible to the balance.
    // Today no writer produces one — these tests pin the rule before #563 makes
    // it reachable.

    func testNet_rowInAnotherCurrency_isSkippedLikeAnUnclassifiableOne() {
        let entries = [
            Transaction(type: .topup, amount: 500),
            Transaction(type: .topup, amount: 300, currency: Currency(code: "USD")!),
            Transaction(type: .charge, amount: 50)
        ]

        XCTAssertEqual(BalanceLedger.net(of: entries, in: .legacyDefault), 450, accuracy: 0.0001,
                       "300 dollars is not 300 roubles, and there is nothing to convert it with")
        XCTAssertEqual(BalanceLedger.net(of: entries, in: Currency(code: "USD")!), 300, accuracy: 0.0001,
                       "Asked about dollars, the same ledger answers with the dollar rows")
    }

    /// End-to-end: a foreign row planted straight into the ledger (the shape a
    /// future storefront or a resync would produce) must leave the wallet
    /// exactly where it was — not credited, not deducted, not converted.
    func testBalance_foreignRowInTheLedger_leavesTheWalletUntouched() {
        let service = makeService(balance: 100)
        let ledger = makeLedger()

        XCTAssertTrue(ledger.record(Transaction(type: .topup, amount: 1000,
                                                currency: Currency(code: "USD")!)))
        XCTAssertEqual(service.balance, 100, accuracy: 0.0001,
                       "A row in a currency the wallet does not hold must not move the balance")
        XCTAssertEqual(cachedBalance(), 100, accuracy: 0.0001,
                       "…and must not be written into the cache either")

        XCTAssertTrue(ledger.record(Transaction(type: .topup, amount: 200)))
        XCTAssertEqual(service.balance, 300, accuracy: 0.0001,
                       "A row in the wallet's own currency still moves it")
    }

    // MARK: - Provider flag

    func testProvider_defaultsToLocal() {
        XCTAssertEqual(BalanceLedgerStoreFactory.provider(defaults: testDefaults), .local)
    }

    /// The flag exists so phase 1 of #364 can switch the backend on separately.
    /// Until that provider is built, a device carrying the flag must degrade to
    /// the working local wallet rather than to no wallet at all.
    func testProvider_cloudKitFlag_stillYieldsAWorkingLocalStore() {
        testDefaults.set(BalanceLedgerProvider.cloudKit.rawValue,
                         forKey: BalanceLedgerStoreFactory.providerKey)

        XCTAssertEqual(BalanceLedgerStoreFactory.provider(defaults: testDefaults), .cloudKit)
        let store = BalanceLedgerStoreFactory.makeStore(repository: makeLedger(), defaults: testDefaults)
        XCTAssertTrue(store is LocalBalanceLedgerStore)
        XCTAssertEqual(store.append(Transaction(type: .topup, amount: 99)), .recorded)
    }
}
