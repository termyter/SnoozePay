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
