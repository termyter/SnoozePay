import XCTest
@testable import SnoozePay

/// Codable contract for `TransactionType` — the persisted `stored_transactions`
/// ledger is the user's money, so adding `.refund` (issue #358) must not make a
/// single historic row unreadable.
///
/// `TransactionRepository` decodes the ledger as one array and treats ANY
/// decode failure as corruption (locks writes, backs the blob up, see #72), so
/// "one bad token" and "whole wallet history lost" are the same event. These
/// tests pin both directions of version skew.
final class TransactionTypeCodableTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.txType.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Backward compatibility (pre-#358 ledgers)

    /// A ledger written before `.refund` existed must decode unchanged. This
    /// is the regression that would cost a user their entire history.
    func testDecode_legacyLedgerWithoutRefundCase_stillDecodes() {
        let json = """
        [
          {"id":"\(UUID().uuidString)","type":"topup","amount":500,
           "createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,
           "createdAt":760000100},
          {"id":"\(UUID().uuidString)","type":"promotion","amount":200,
           "createdAt":760000200}
        ]
        """
        let decoded = try? JSONDecoder().decode([Transaction].self, from: Data(json.utf8))

        XCTAssertEqual(decoded?.count, 3, "Legacy rows must survive the new case")
        XCTAssertEqual(decoded?.map(\.type), [.topup, .charge, .promotion])
        XCTAssertNil(decoded?.first?.refundsTransactionID,
            "A legacy row without the field decodes to nil, not a decode failure")
    }

    /// The pre-#358 refund shape — a `.topup` carrying `refundsTransactionID` —
    /// must keep decoding AND keep pairing with its charge, so old ledgers
    /// don't start counting reversed snoozes again.
    func testDecode_legacyRefundShape_stillPairsWithItsCharge() {
        let chargeID = UUID()
        let json = """
        [
          {"id":"\(chargeID.uuidString)","type":"charge","amount":50,
           "createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"topup","amount":50,
           "createdAt":760000100,"refundsTransactionID":"\(chargeID.uuidString)"}
        ]
        """
        let decoded = try? JSONDecoder().decode([Transaction].self, from: Data(json.utf8))
        XCTAssertEqual(decoded?.count, 2)

        let real = TransactionRepository.realCharges(from: decoded ?? [])
        XCTAssertTrue(real.isEmpty,
            "Consumers pair on refundsTransactionID, not on the type — legacy .topup refunds still cancel their charge")
    }

    /// Full ledger path: a legacy blob planted directly in UserDefaults must
    /// load through `TransactionRepository` without tripping the #72 lock.
    func testLegacyLedgerBlob_loadsThroughRepositoryWithoutLocking() {
        let json = """
        [
          {"id":"\(UUID().uuidString)","type":"topup","amount":500,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000100}
        ]
        """
        testDefaults.set(Data(json.utf8), forKey: "stored_transactions")
        let repo = TransactionRepository(defaults: testDefaults)

        XCTAssertEqual(repo.fetchAll().count, 2)
        XCTAssertFalse(repo.lastLoadFailed,
            "A pre-#358 ledger must not be mistaken for a corrupt blob")
    }

    // MARK: - Forward compatibility (downgrade / newer tokens)

    /// An unrecognised token must degrade to `.unknown` instead of failing the
    /// whole array — the downgrade scenario (older build reading a ledger that
    /// already contains `.refund`, or any future case).
    func testDecode_unrecognisedToken_degradesToUnknownAndKeepsSiblings() {
        let json = """
        [
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"cashback","amount":10,"createdAt":760000100}
        ]
        """
        let decoded = try? JSONDecoder().decode([Transaction].self, from: Data(json.utf8))

        XCTAssertEqual(decoded?.count, 2, "One unknown token must not sink the whole ledger")
        XCTAssertEqual(decoded?.last?.type, .unknown("cashback"))
        XCTAssertEqual(decoded?.first?.type, .charge)
    }

    /// Re-encoding must preserve the original token verbatim. Every `record()`
    /// rewrites the whole array, so a lossy sentinel would permanently destroy
    /// the row's meaning after a single downgrade + write.
    func testUnknownToken_roundTripsLosslessly() {
        let original = Transaction(type: .unknown("cashback"), amount: 10)

        let data = try? JSONEncoder().encode([original])
        let decoded = try? JSONDecoder().decode([Transaction].self, from: data ?? Data())

        XCTAssertEqual(decoded?.first?.type, .unknown("cashback"))
        XCTAssertEqual(decoded?.first?.type.rawValue, "cashback")
    }

    /// `.refund` itself round-trips through the persisted representation.
    func testRefundType_roundTrips() {
        let data = try? JSONEncoder().encode([Transaction(type: .refund, amount: 50)])
        let decoded = try? JSONDecoder().decode([Transaction].self, from: data ?? Data())

        XCTAssertEqual(decoded?.first?.type, .refund)
        XCTAssertEqual(decoded?.first?.type.rawValue, "refund",
            "The on-disk token is a contract — renaming it orphans every persisted refund")
    }

    /// Genuine corruption (not a version skew) must still be reported. The
    /// unknown-token tolerance is scoped to the enum, not to the blob.
    func testDecode_malformedBlob_stillFails() {
        let decoded = try? JSONDecoder().decode(
            [Transaction].self, from: Data("{ not json ]".utf8)
        )
        XCTAssertNil(decoded, "Tolerating unknown tokens must not tolerate a corrupt blob")
    }

    // MARK: - Direction classification

    func testIsDebit_onlyChargeTakesMoneyOut() {
        XCTAssertTrue(TransactionType.charge.isDebit)
        XCTAssertFalse(TransactionType.topup.isDebit)
        XCTAssertFalse(TransactionType.promotion.isDebit)
        XCTAssertFalse(TransactionType.refund.isDebit)
        XCTAssertFalse(TransactionType.unknown("cashback").isDebit)
    }

    func testFormattedAmount_refundReadsAsCredit() {
        XCTAssertEqual(Transaction(type: .refund, amount: 50).formattedAmount,
                       "+\(MoneyFormatter.string(50))")
        XCTAssertEqual(Transaction(type: .charge, amount: 50).formattedAmount,
                       "-\(MoneyFormatter.string(50))")
    }
}
