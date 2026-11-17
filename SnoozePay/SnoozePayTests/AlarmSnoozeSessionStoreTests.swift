import XCTest
@testable import SnoozePay

@MainActor
final class AlarmSnoozeSessionStoreTests: XCTestCase {
    private var fixture: TrackedSessionFixture!
    override func setUp() { super.setUp(); fixture = TrackedSessionFixture() }
    override func tearDown() { fixture.close(); fixture = nil; super.tearDown() }

    func testReservationAndChargedButUnconfirmedAttemptRemainUnavailableAfterReconstruction() throws {
        let store = fixture.store()
        let token = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        try store.recordCharge(token, alarmID: fixture.alarm.id)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0))
    }

    func testFailedAttemptAdvancesCountAndAnOlderValidTokenCannotLowerIt() throws {
        let first = try confirmedAttempt()
        let store = fixture.store()
        let second = try store.reserve(alarmID: fixture.alarm.id, sessionID: first.sessionID, expectedCount: 1)
        try store.recordCharge(second, alarmID: fixture.alarm.id)
        try store.complete(second, alarmID: fixture.alarm.id, receipt: nil)
        XCTAssertEqual(try fixture.store().resolve(first, alarmID: fixture.alarm.id).count, 2)
        XCTAssertEqual(try fixture.store().resolve(second, alarmID: fixture.alarm.id).count, 2)
    }

    func testCorruptAndUnsupportedBytesArePreservedAndNeverResetToAnEmptyStore() {
        for bytes in [Data("broken".utf8), Data("{\"version\":2,\"sessions\":[]}".utf8)] {
            fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
            XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0))
            XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
            XCTAssertThrowsError(try fixture.store().finish(alarmID: fixture.alarm.id))
            XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        }
    }

    func testExactReceiptMatchingRejectsPredictedDatesAndAmbiguousBindings() throws {
        let receipt = AlarmSnoozeReceipt(systemID: UUID(), fireDate: Date(timeIntervalSince1970: 1_000))
        let token = try confirmedAttempt(receipt: receipt)
        XCTAssertEqual(try fixture.store().token(for: receipt, alarmID: fixture.alarm.id), token)
        let different = AlarmSnoozeReceipt(systemID: receipt.systemID, fireDate: receipt.fireDate.addingTimeInterval(1))
        XCTAssertThrowsError(try fixture.store().token(for: different, alarmID: fixture.alarm.id))
        _ = try confirmedAttempt(receipt: receipt)
        XCTAssertThrowsError(try fixture.store().token(for: receipt, alarmID: fixture.alarm.id))
    }

    func testFinishedUnknownAndWrongOwnerTokensCannotResumeOrBeCompletedLate() throws {
        let token = try confirmedAttempt()
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: UUID()))
        let unknown = AlarmSnoozeToken(sessionID: UUID(), attemptID: UUID())
        XCTAssertThrowsError(try fixture.store().resolve(unknown, alarmID: fixture.alarm.id))
        try fixture.store().finish(alarmID: fixture.alarm.id)
        let finishedBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        XCTAssertThrowsError(try fixture.store().complete(token, alarmID: fixture.alarm.id, receipt: nil))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), finishedBytes)
    }

    func testRejectedDebitDoesNotCountAsAnAttempt() throws {
        let store = fixture.store()
        let rejected = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        try store.rejectCharge(rejected, alarmID: fixture.alarm.id)
        let accepted = try store.reserve(alarmID: fixture.alarm.id, sessionID: rejected.sessionID, expectedCount: 0)
        try store.recordCharge(accepted, alarmID: fixture.alarm.id)
        try store.complete(accepted, alarmID: fixture.alarm.id, receipt: nil)
        XCTAssertEqual(try store.resolve(accepted, alarmID: fixture.alarm.id).count, 1)
        XCTAssertThrowsError(try store.resolve(rejected, alarmID: fixture.alarm.id))
    }

    func testUnknownFinishAndSettlementPreserveAbsentContextKeyIncludingSchedulerCancellation() throws {
        XCTAssertNil(fixture.defaults.object(forKey: AlarmSnoozeSessionStore.key))
        try fixture.store().finish(alarmID: fixture.alarm.id)
        XCTAssertNil(fixture.defaults.object(forKey: AlarmSnoozeSessionStore.key))
        try fixture.store().settleCancelled(alarmID: fixture.alarm.id)
        XCTAssertNil(fixture.defaults.object(forKey: AlarmSnoozeSessionStore.key))
        fixture.scheduler(TrackedSessionBackend()).cancel(fixture.alarm.id)
        XCTAssertNil(fixture.defaults.object(forKey: AlarmSnoozeSessionStore.key),
                     "Legacy cancellation must not create an empty tracked-session envelope")
    }

    func testUnknownAndActiveUnfinishedNoOpsPreserveUnrelatedRawContextBytes() throws {
        let token = try confirmedAttempt()
        let raw = try seedDistinctRawBytes()
        let unknown = UUID()
        try fixture.store().finish(alarmID: unknown)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), raw)
        try fixture.store().settleCancelled(alarmID: unknown)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), raw)
        try fixture.store().settleCancelled(alarmID: fixture.alarm.id)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), raw)
        XCTAssertEqual(try fixture.store().resolve(token, alarmID: fixture.alarm.id).count, 1)
    }

    func testLegitimateFinishPersistsButRepeatedFinishAndSettledCleanupPreserveRawBytes() throws {
        let token = try confirmedAttempt()
        let active = try seedDistinctRawBytes()
        try fixture.store().finish(alarmID: fixture.alarm.id)
        XCTAssertNotEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), active)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        let finished = try seedDistinctRawBytes()
        try fixture.store().finish(alarmID: fixture.alarm.id)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), finished)
        try fixture.store().settleCancelled(alarmID: fixture.alarm.id)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), finished)
    }

    func testCleanupPersistsOnlyAfterPhysicalOperationEndsAndDoesNotRewriteItsSettledResult() throws {
        let store = fixture.store()
        let token = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: fixture.alarm.id)
        try store.finish(alarmID: fixture.alarm.id)
        let pending = try seedDistinctRawBytes()
        try fixture.store().settleCancelled(alarmID: fixture.alarm.id)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), pending,
                       "The live physical callback still owns this pending attempt")
        store.operationEnded(token)
        try fixture.store().settleCancelled(alarmID: fixture.alarm.id)
        let settled = try XCTUnwrap(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key))
        XCTAssertNotEqual(settled, pending)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: settled) as? [String: Any])
        let session = try XCTUnwrap((envelope["sessions"] as? [[String: Any]])?.first)
        let attempt = try XCTUnwrap((session["attempts"] as? [[String: Any]])?.first)
        XCTAssertEqual(session["finished"] as? Bool, true)
        XCTAssertEqual(session["count"] as? Int, 1)
        XCTAssertEqual(attempt["phase"] as? String, "failed")
        try fixture.store().settleCancelled(alarmID: fixture.alarm.id)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), settled)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        XCTAssertNoThrow(try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0))
    }

    func testNoOpEntryPointsStillRejectCorruptUnsupportedAndNonDataContextWithoutChangingIt() throws {
        let unknown = UUID()
        for bytes in [Data("broken".utf8), Data("{\"version\":2,\"sessions\":[]}".utf8)] {
            fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
            XCTAssertThrowsError(try fixture.store().finish(alarmID: unknown))
            XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
            XCTAssertThrowsError(try fixture.store().settleCancelled(alarmID: unknown))
            XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        }
        fixture.defaults.set("not-data", forKey: AlarmSnoozeSessionStore.key)
        XCTAssertThrowsError(try fixture.store().finish(alarmID: unknown))
        XCTAssertThrowsError(try fixture.store().settleCancelled(alarmID: unknown))
        XCTAssertEqual(fixture.defaults.string(forKey: AlarmSnoozeSessionStore.key), "not-data")
    }

    /// Distinct formatting plus an ignored field makes re-encoding observable even if values do not change.
    private func seedDistinctRawBytes() throws -> Data {
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        envelope["noOpMarker"] = "preserve exact unrelated bytes"
        let raw = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        fixture.defaults.set(raw, forKey: AlarmSnoozeSessionStore.key)
        return raw
    }

    private func confirmedAttempt(receipt: AlarmSnoozeReceipt? = nil) throws -> AlarmSnoozeToken {
        let store = fixture.store()
        let token = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: fixture.alarm.id)
        try store.complete(token, alarmID: fixture.alarm.id, receipt: receipt ?? AlarmSnoozeReceipt(
            systemID: UUID(), fireDate: Date(timeIntervalSince1970: 1_000)
        ))
        return token
    }
}
