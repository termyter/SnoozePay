import XCTest
@testable import SnoozePay

/// Codable contract for `TransactionType` — the persisted `stored_transactions`
/// ledger is the user's money, so adding `.refund` (issue #358) must not make a
/// single historic row unreadable.
///
/// `TransactionRepository` decodes the ledger as one array and treats ANY
/// decode failure as corruption (locks writes, backs the blob up, see #72), so
/// "one bad token" and "whole wallet history lost" are the same event. These
/// tests pin where the line sits: which damage is tolerated (and then reported
/// via `lastLoadUnrecognizedTypes`) and which still trips the #72 gate.
///
/// Every decode here is `try`, not `try?` — swallowing the error would make
/// these tests pass on exactly the regression they exist to catch.
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

    // MARK: - Helpers

    private func decode(_ json: String) throws -> [Transaction] {
        try JSONDecoder().decode([Transaction].self, from: Data(json.utf8))
    }

    /// Plants a raw blob under the ledger key and returns a repository over it.
    private func makeRepo(withBlob json: String) -> TransactionRepository {
        testDefaults.set(Data(json.utf8), forKey: "stored_transactions")
        return TransactionRepository(defaults: testDefaults)
    }

    // MARK: - Backward compatibility (pre-#358 ledgers)

    /// A ledger written before `.refund` existed must decode unchanged. This
    /// is the regression that would cost a user their entire history.
    func testDecode_legacyLedgerWithoutRefundCase_stillDecodes() throws {
        let decoded = try decode("""
        [
          {"id":"\(UUID().uuidString)","type":"topup","amount":500,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000100},
          {"id":"\(UUID().uuidString)","type":"promotion","amount":200,"createdAt":760000200}
        ]
        """)

        XCTAssertEqual(decoded.count, 3, "Legacy rows must survive the new case")
        XCTAssertEqual(decoded.map(\.type), [.topup, .charge, .promotion])
        XCTAssertNil(decoded.first?.refundsTransactionID,
            "A legacy row without the field decodes to nil, not a decode failure")
    }

    /// The pre-#358 refund shape — a `.topup` carrying `refundsTransactionID` —
    /// must keep decoding AND keep pairing with its charge, so old ledgers
    /// don't start counting reversed snoozes again.
    func testDecode_legacyRefundShape_stillPairsWithItsCharge() throws {
        let chargeID = UUID()
        let decoded = try decode("""
        [
          {"id":"\(chargeID.uuidString)","type":"charge","amount":50,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"topup","amount":50,
           "createdAt":760000100,"refundsTransactionID":"\(chargeID.uuidString)"}
        ]
        """)
        XCTAssertEqual(decoded.count, 2)

        XCTAssertTrue(TransactionRepository.realCharges(from: decoded).isEmpty,
            "Consumers pair on refundsTransactionID, not on the type — legacy .topup refunds still cancel their charge")
    }

    /// Full ledger path: a legacy blob planted directly in UserDefaults must
    /// load through `TransactionRepository` without tripping the #72 lock or
    /// the #358 unrecognised-type signal.
    func testLegacyLedgerBlob_loadsCleanly() {
        let repo = makeRepo(withBlob: """
        [
          {"id":"\(UUID().uuidString)","type":"topup","amount":500,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000100}
        ]
        """)

        XCTAssertEqual(repo.fetchAllOrFail().count, 2)
        XCTAssertFalse(repo.lastLoadFailed,
            "A pre-#358 ledger must not be mistaken for a corrupt blob")
        XCTAssertFalse(repo.lastLoadHadUnrecognizedTypes,
            "Every token in a legacy ledger is recognised — no false incident")
    }

    // MARK: - Tolerated: unrecognised token (but reported, never silent)

    /// An unrecognised token degrades to `.unknown` instead of failing the
    /// whole array — this is what keeps a future-version ledger readable.
    func testDecode_unrecognisedToken_degradesToUnknownAndKeepsSiblings() throws {
        let decoded = try decode("""
        [
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"cashback","amount":10,"createdAt":760000100}
        ]
        """)

        XCTAssertEqual(decoded.count, 2, "One unknown token must not sink the whole ledger")
        XCTAssertEqual(decoded.first?.type, .charge)
        XCTAssertEqual(decoded.last?.type, .unknown("cashback"))
    }

    /// In-place damage to a `type` string ("charge" → "chargf") used to throw
    /// and latch the #72 gate. It no longer does — so it MUST surface through
    /// the replacement signal instead, otherwise #358 traded a loud failure for
    /// a silent one: the row is skipped by every aggregate while `user_balance`
    /// still reflects it, and the wallet screens quietly contradict the balance.
    func testDamagedTypeString_isReportedAsAnIncident() {
        let repo = makeRepo(withBlob: """
        [
          {"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"chargf","amount":50,"createdAt":760000100}
        ]
        """)

        XCTAssertEqual(repo.fetchAllOrFail().count, 2, "The intact rows stay readable")
        XCTAssertFalse(repo.lastLoadFailed, "The blob itself is fine — writes must not be locked")
        XCTAssertTrue(repo.lastLoadHadUnrecognizedTypes,
            "Damaged type strings must not be silently absorbed (#358 review)")
        XCTAssertEqual(repo.lastLoadUnrecognizedTypes, ["chargf"],
            "The offending token is kept for the log / support ticket")
    }

    /// Empty string and case-mismatched tokens are damage too, not valid data.
    func testOtherDamagedTypeStrings_alsoReported() {
        let repo = makeRepo(withBlob: """
        [
          {"id":"\(UUID().uuidString)","type":"","amount":50,"createdAt":760000000},
          {"id":"\(UUID().uuidString)","type":"Charge","amount":50,"createdAt":760000100}
        ]
        """)
        _ = repo.fetchAllOrFail()

        XCTAssertEqual(repo.lastLoadUnrecognizedTypes, ["", "Charge"],
            "Token matching is exact — an empty or re-cased string is not a charge")
    }

    /// Like `lastLoadFailed`, the signal describes the last *load* — it stays
    /// clear until something has actually been read.
    func testUnrecognizedSignal_isClearBeforeAnyLoad() {
        let repo = makeRepo(withBlob: """
        [{"id":"\(UUID().uuidString)","type":"cashback","amount":10,"createdAt":760000000}]
        """)

        XCTAssertFalse(repo.lastLoadHadUnrecognizedTypes)
        _ = repo.fetchAllOrFail()
        XCTAssertTrue(repo.lastLoadHadUnrecognizedTypes)
    }

    /// The signal clears once the ledger is healthy again, so a stale flag
    /// can't keep warning the user forever.
    func testUnrecognizedSignal_clearsOnAHealthyLedger() {
        let repo = makeRepo(withBlob: """
        [{"id":"\(UUID().uuidString)","type":"cashback","amount":10,"createdAt":760000000}]
        """)
        _ = repo.fetchAllOrFail()
        XCTAssertTrue(repo.lastLoadHadUnrecognizedTypes)

        testDefaults.set(Data("""
        [{"id":"\(UUID().uuidString)","type":"charge","amount":50,"createdAt":760000000}]
        """.utf8), forKey: "stored_transactions")

        XCTAssertEqual(repo.fetchAllOrFail().count, 1)
        XCTAssertFalse(repo.lastLoadHadUnrecognizedTypes)
        XCTAssertTrue(repo.lastLoadUnrecognizedTypes.isEmpty)
    }

    // MARK: - Still fatal: structural damage keeps tripping the #72 gate

    /// A non-string `type` is structural damage, not a token this build hasn't
    /// heard of — it must still throw so the ledger is backed up and locked.
    func testDecode_nonStringType_stillThrows() {
        XCTAssertThrowsError(try decode("""
        [{"id":"\(UUID().uuidString)","type":3,"amount":50,"createdAt":760000000}]
        """))
    }

    func testDecode_nullType_stillThrows() {
        XCTAssertThrowsError(try decode("""
        [{"id":"\(UUID().uuidString)","type":null,"amount":50,"createdAt":760000000}]
        """))
    }

    func testDecode_missingTypeKey_stillThrows() {
        XCTAssertThrowsError(try decode("""
        [{"id":"\(UUID().uuidString)","amount":50,"createdAt":760000000}]
        """))
    }

    /// Genuine blob corruption must still be reported. The unknown-token
    /// tolerance is scoped to the enum, not to the JSON.
    func testDecode_malformedBlob_stillThrows() {
        XCTAssertThrowsError(try decode("{ not json ]"))
    }

    /// End-to-end: structural damage still arms the #72 gate through the
    /// repository, not just the bare decoder.
    func testStructurallyDamagedBlob_stillLocksTheLedger() {
        let repo = makeRepo(withBlob: """
        [{"id":"\(UUID().uuidString)","type":3,"amount":50,"createdAt":760000000}]
        """)

        XCTAssertThrowsError(try repo.fetchAllChecked())
        XCTAssertTrue(repo.lastLoadFailed, "The #72 corruption gate must still arm")
    }

    // MARK: - Round-trips

    /// Re-encoding must preserve the original token verbatim. Every `record()`
    /// rewrites the whole array, so a lossy sentinel would permanently destroy
    /// the row's meaning after a single write.
    func testUnknownToken_roundTripsLosslessly() throws {
        let data = try JSONEncoder().encode([Transaction(type: .unknown("cashback"), amount: 10)])
        let decoded = try JSONDecoder().decode([Transaction].self, from: data)

        XCTAssertEqual(decoded.first?.type, .unknown("cashback"))
        XCTAssertEqual(decoded.first?.type.rawValue, "cashback")
    }

    /// `.refund` itself round-trips through the persisted representation.
    func testRefundType_roundTrips() throws {
        let data = try JSONEncoder().encode([Transaction(type: .refund, amount: 50)])
        let decoded = try JSONDecoder().decode([Transaction].self, from: data)

        XCTAssertEqual(decoded.first?.type, .refund)
        XCTAssertEqual(decoded.first?.type.rawValue, "refund",
            "The on-disk token is a contract — renaming it orphans every persisted refund")
    }

    // MARK: - Direction classification

    func testIsDebit_onlyChargeTakesMoneyOut() {
        XCTAssertTrue(TransactionType.charge.isDebit)
        XCTAssertFalse(TransactionType.topup.isDebit)
        XCTAssertFalse(TransactionType.promotion.isDebit)
        XCTAssertFalse(TransactionType.refund.isDebit)
        XCTAssertFalse(TransactionType.unknown("cashback").isDebit)
    }

    func testIsUnrecognized_onlyUnknown() {
        XCTAssertTrue(TransactionType.unknown("cashback").isUnrecognized)
        for known: TransactionType in [.charge, .topup, .promotion, .refund] {
            XCTAssertFalse(known.isUnrecognized, "\(known.rawValue) is a known token")
        }
    }

    func testFormattedAmount_signsCreditsAndDebits_butNotUnknowns() {
        XCTAssertEqual(Transaction(type: .refund, amount: 50).formattedAmount,
                       "+\(MoneyFormatter.string(50))")
        XCTAssertEqual(Transaction(type: .charge, amount: 50).formattedAmount,
                       "-\(MoneyFormatter.string(50))")
        XCTAssertEqual(Transaction(type: .unknown("cashback"), amount: 50).formattedAmount,
                       MoneyFormatter.string(50),
                       "An unrecognised row has no direction to sign")
    }
}
