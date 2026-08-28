import XCTest
@testable import SnoozePay

/// Unit tests for the Wallet reload decision logic (#419).
///
/// The Wallet surfaces (preview, weekly stats, full history) previously read
/// the lossy `TransactionRepository.fetchAll()`, so a corrupt ledger rendered
/// as the friendly "нет операций" empty-state. `WalletLedgerLoad` now wraps a
/// decode-checked read and classifies the outcome so the VCs render a distinct
/// error banner instead — these tests pin that classification with a mock that
/// throws (mirroring `StatisticsViewModel`'s checked load), and verify the real
/// `TransactionRepository` path against a corrupt blob written to disk.
final class WalletLedgerLoadTests: XCTestCase {

    // MARK: - Mock

    /// Outcome a `MockLedger` replays — a fixed list or a decode failure,
    /// standing in for a corrupt `UserDefaults` blob without one.
    private enum MockOutcome {
        case success([Transaction])
        case failure
    }

    /// Mock ledger reader driving the reload decision under test.
    private final class MockLedger: WalletLedgerReading {
        let outcome: MockOutcome

        init(outcome: MockOutcome) {
            self.outcome = outcome
        }

        func fetchAllChecked() throws -> [Transaction] {
            switch outcome {
            case .success(let txs):
                return txs
            case .failure:
                throw TransactionRepository.RepositoryError.decodeFailure(
                    underlying: NSError(domain: "test", code: 1)
                )
            }
        }
    }

    // MARK: - Decision: failure → error-state, NOT empty-state

    func testLoad_whenDecodeFails_classifiesAsFailed() {
        let load = WalletLedgerLoad.load(from: MockLedger(outcome: .failure))

        XCTAssertTrue(load.didFail, "A decode failure must surface the error banner")
        XCTAssertTrue(load.transactions.isEmpty)
    }

    func testLoad_whenDecodeFails_yieldsNoTransactions_butIsDistinctFromEmpty() {
        let failed = WalletLedgerLoad.load(from: MockLedger(outcome: .failure))
        let empty = WalletLedgerLoad.load(from: MockLedger(outcome: .success([])))

        // Both have zero transactions...
        XCTAssertTrue(failed.transactions.isEmpty)
        XCTAssertTrue(empty.transactions.isEmpty)
        // ...but only the failure drives the error banner — the empty ledger
        // must keep the friendly empty-state (the #419 regression was these
        // two being indistinguishable through lossy `fetchAll()`).
        XCTAssertTrue(failed.didFail)
        XCTAssertFalse(empty.didFail)
    }

    // MARK: - Decision: success → loaded with the rows

    func testLoad_whenDecodeSucceeds_classifiesAsLoadedWithRows() {
        let txs = [
            Transaction(type: .topup, amount: 500),
            Transaction(type: .charge, amount: 50)
        ]
        let load = WalletLedgerLoad.load(from: MockLedger(outcome: .success(txs)))

        XCTAssertFalse(load.didFail)
        XCTAssertEqual(load.transactions.count, 2)
    }

    func testLoad_whenLedgerEmpty_isLoadedNotFailed() {
        let load = WalletLedgerLoad.load(from: MockLedger(outcome: .success([])))

        XCTAssertFalse(load.didFail, "An empty ledger is a legitimate empty-state, not an error")
        XCTAssertTrue(load.transactions.isEmpty)
    }

    // MARK: - Real repository: corrupt blob → failed

    func testLoad_realRepository_withCorruptBlob_isFailed() {
        let suiteName = "test.walletLedger.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Write bytes that can't decode into `[Transaction]` — the exact
        // corruption mode `fetchAllChecked()` is meant to catch (#72/#210).
        defaults.set(Data("{not valid json".utf8), forKey: "stored_transactions")
        let repo = TransactionRepository(defaults: defaults)

        let load = WalletLedgerLoad.load(from: repo)

        XCTAssertTrue(load.didFail, "Corrupt persisted ledger must classify as failed")
        XCTAssertTrue(repo.lastLoadFailed, "Checked read latches the repository lock")
    }

    func testLoad_realRepository_withValidLedger_isLoaded() {
        let suiteName = "test.walletLedger.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repo = TransactionRepository(defaults: defaults)
        repo.record(Transaction(type: .topup, amount: 300))

        let load = WalletLedgerLoad.load(from: repo)

        XCTAssertFalse(load.didFail)
        XCTAssertEqual(load.transactions.count, 1)
    }
}

/// Tests the Deposit-sheet gating decision (#419): a corrupt balance must be
/// detected BEFORE attempting a top-up, since `BalanceService` keeps the
/// mutation gate locked until `acknowledgeCorruption()` — so a top-up would
/// always fail back into the generic, unsatisfiable retry loop.
final class DepositCorruptionGateTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.depositGate.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCorruptBalance_isDetected_andTopUpStaysGated() {
        // Seed a negative (corrupt) balance, then construct the service so its
        // init-time probe latches the corruption flag.
        testDefaults.set(-100.0, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())

        // The Deposit sheet's pre-top-up guard reads exactly this flag.
        XCTAssertTrue(service.balanceCorrupted, "Negative balance must flip the corruption flag")

        // And the gate would have blocked the top-up anyway — proving the
        // detection guard isn't merely cosmetic: without it the user hits the
        // generic failure they can't satisfy.
        XCTAssertFalse(service.topUp(amount: 50), "Top-up must stay gated while corrupt")
    }

    func testHealthyBalance_isNotFlaggedCorrupt() {
        testDefaults.set(500.0, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())

        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertTrue(service.topUp(amount: 50), "Healthy balance accepts top-up")
    }
}
