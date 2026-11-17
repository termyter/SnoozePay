import XCTest
@testable import SnoozePay

/// #1011: a paid purchase must end with exactly one credit row whatever
/// persistence boundary the process died at, and a legacy marker with no
/// linked row must stay as it is (PM decision 2026-11-17).
@MainActor
final class StoreKitPurchaseCrashRecoveryTests: XCTestCase {
    private let usd = Currency(code: "USD")!
    private var suites: [String] = []
    private let paid = RestorableTopUp(transactionID: 7, productID: "io.mobilife.snoozepay.balance.299",
                                       currency: Currency(code: "USD"), transactionPrice: 2.99,
                                       purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))

    override func tearDown() {
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        super.tearDown()
    }

    private func makeSuite() -> (UserDefaults, String) {
        let name = "StoreKitPurchaseCrashRecoveryTests.\(UUID())"
        suites.append(name)
        return (UserDefaults(suiteName: name)!, name)
    }

    /// A fresh process over `defaults`: new wallet, new purchase service.
    private func relaunch(_ defaults: UserDefaults) -> (BalanceService, StoreKitService) {
        let store = StoreKitService(notificationPoster: LocalNotificationPosterSpy(), defaults: defaults)
        store.beginObservingPurchaseFeedback()
        return (BalanceService(defaults: defaults, notificationCenter: NotificationCenter()), store)
    }

    private func topUpRows(_ defaults: UserDefaults) throws -> [Transaction] {
        try TransactionRepository(defaults: defaults).fetchAllChecked().filter { $0.type == .topup }
    }

    // MARK: - Fault injection at every persistence boundary

    /// Records every write the purchase makes, then replays each prefix of them
    /// into a fresh suite — the state a crash after write N leaves on disk — and
    /// relaunches over it. Mark-first ordering fails at the prefix holding only
    /// the marker: the replay finishes with zero rows.
    func testInterruptionAfterEveryWriteRecoversToExactlyOneCredit() async throws {
        let liveName = "StoreKitPurchaseCrashRecoveryTests.live.\(UUID())"
        suites.append(liveName)
        let live = try XCTUnwrap(WriteLogDefaults(suiteName: liveName))
        let (balance, store) = relaunch(live)
        let before = live.persistentDomain(forName: liveName) ?? [:]
        let firstWrite = live.writes.count
        await store.applyVerifiedPurchase(paid, balance: balance) {}
        let writes = Array(live.writes.dropFirst(firstWrite))
        XCTAssertTrue(writes.contains { $0.key == "stored_transactions" })
        XCTAssertTrue(writes.contains { $0.key == "storekit.processed_tx_ids" })

        for crashAfter in 0...writes.count {
            let (disk, name) = makeSuite()
            disk.setPersistentDomain(before, forName: name)
            writes.prefix(crashAfter).forEach { disk.set($0.value, forKey: $0.key) }
            let (relaunchedBalance, relaunchedStore) = relaunch(disk)
            var finishes = 0
            for _ in 0..<2 {
                await relaunchedStore.applyVerifiedPurchase(paid, balance: relaunchedBalance) { finishes += 1 }
            }
            let context = "crash after write \(crashAfter) of \(writes.count)"
            XCTAssertEqual(try topUpRows(disk).count, 1, context)
            XCTAssertEqual(relaunchedBalance.balance, 2.99, accuracy: 0.0001, context)
            XCTAssertEqual(finishes, 2, context)
            XCTAssertEqual(disk.stringArray(forKey: "storekit.processed_tx_ids"), ["7"], context)
        }
    }

    // MARK: - Explicit crash states

    /// Credit landed, marker and finish did not: the replay must find the row.
    func testRowWithoutMarkerFinishesWithoutSecondCredit() async throws {
        let (defaults, _) = makeSuite()
        let (balance, _) = relaunch(defaults)
        XCTAssertEqual(balance.topUpFromPurchase(amount: 2.99, currency: usd, ledgerID: paid.ledgerRowID), .credited)

        let (relaunchedBalance, relaunchedStore) = relaunch(defaults)
        var finishes = 0
        await relaunchedStore.applyVerifiedPurchase(paid, balance: relaunchedBalance) { finishes += 1 }

        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(try topUpRows(defaults).count, 1)
        XCTAssertEqual(relaunchedBalance.balance, 2.99, accuracy: 0.0001)
        XCTAssertEqual(defaults.stringArray(forKey: "storekit.processed_tx_ids"), ["7"])
    }

    func testRepeatedReplaysCreditOnceAndFinishEveryTime() async throws {
        let (defaults, _) = makeSuite()
        let (balance, store) = relaunch(defaults)
        var finishes = 0
        for _ in 0..<3 {
            await store.applyVerifiedPurchase(paid, balance: balance) { finishes += 1 }
        }
        let (relaunchedBalance, relaunchedStore) = relaunch(defaults)
        await relaunchedStore.applyVerifiedPurchase(paid, balance: relaunchedBalance) { finishes += 1 }

        XCTAssertEqual(finishes, 4)
        XCTAssertEqual(try topUpRows(defaults).map(\.id), [paid.ledgerRowID], "The row carries the link")
        XCTAssertEqual(relaunchedBalance.balance, 2.99, accuracy: 0.0001)
        XCTAssertEqual(defaults.stringArray(forKey: "storekit.processed_tx_ids"), ["7"])
    }

    // MARK: - Legacy

    /// A mark-first marker with no linked row is finished without credit and
    /// left in place — no retro-crediting (PM decision 2026-11-17).
    func testLegacyMarkerWithoutRowIsLeftAlone() async throws {
        let (defaults, _) = makeSuite()
        defaults.set(["7"], forKey: "storekit.processed_tx_ids")
        let (balance, store) = relaunch(defaults)
        var finishes = 0
        await store.applyVerifiedPurchase(paid, balance: balance) { finishes += 1 }

        XCTAssertEqual(finishes, 1)
        XCTAssertTrue(try topUpRows(defaults).isEmpty)
        XCTAssertEqual(balance.balance, 0)
        XCTAssertEqual(defaults.stringArray(forKey: "storekit.processed_tx_ids"), ["7"])
    }

    // MARK: - Unreadable storage

    func testUnreadableLedgerNeitherCreditsNorMarksNorFinishes() async {
        let (defaults, _) = makeSuite()
        let corrupt = Data("unreadable ledger".utf8)
        defaults.set(corrupt, forKey: "stored_transactions")
        let (balance, store) = relaunch(defaults)
        var finishes = 0
        for _ in 0..<2 {
            await store.applyVerifiedPurchase(paid, balance: balance) { finishes += 1 }
        }

        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(defaults.data(forKey: "stored_transactions"), corrupt)
        XCTAssertNil(defaults.object(forKey: "storekit.processed_tx_ids"))
        // The USD payment stops at the locked ledger, not at a currency refusal (#1133).
        XCTAssertEqual(balance.topUpFromPurchase(amount: 2.99, currency: usd, ledgerID: paid.ledgerRowID),
                       .notRecorded)
    }

    /// Credit landed, then the dedup table drifted: refuse rather than guess.
    func testUnreadableDedupTableWithLinkedRowRefusesWithoutSecondCredit() async throws {
        let (defaults, _) = makeSuite()
        let (balance, store) = relaunch(defaults)
        XCTAssertEqual(balance.topUpFromPurchase(amount: 2.99, currency: usd, ledgerID: paid.ledgerRowID), .credited)
        let corrupt = ["unexpected": 7]
        defaults.set(corrupt, forKey: "storekit.processed_tx_ids")
        var finishes = 0
        await store.applyVerifiedPurchase(paid, balance: balance) { finishes += 1 }

        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(try topUpRows(defaults).count, 1)
        XCTAssertEqual(defaults.object(forKey: "storekit.processed_tx_ids") as? [String: Int], corrupt)
    }

    // MARK: - Link identity

    func testLedgerRowIDIsStablePerTransactionAndDistinctAcrossThem() {
        func row(_ id: UInt64) -> UUID {
            RestorableTopUp(transactionID: id, productID: paid.productID, currency: usd,
                            transactionPrice: 1, purchaseDate: Date()).ledgerRowID
        }
        XCTAssertEqual(row(7), paid.ledgerRowID)
        XCTAssertEqual(Set([0, 1, 7, 256, UInt64.max].map(row)).count, 5)
        XCTAssertEqual(row(1).uuidString, "53504159-0000-8000-0000-000000000001")
    }
}

/// Logs every write so a test can rebuild the on-disk state after any prefix.
private final class WriteLogDefaults: UserDefaults, @unchecked Sendable {
    private(set) var writes: [(key: String, value: Any?)] = []

    override func set(_ value: Any?, forKey defaultName: String) {
        writes.append((defaultName, value))
        super.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        writes.append((defaultName, nil))
        super.removeObject(forKey: defaultName)
    }
}
