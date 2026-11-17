import XCTest
@testable import SnoozePay

@MainActor
final class AlarmOccurrenceFinishSessionTests: XCTestCase {
    private var fixture: FinishSessionFixture!
    override func setUp() { super.setUp(); fixture = FinishSessionFixture() }
    override func tearDown() { fixture.close(); fixture = nil; super.tearDown() }

    func testMissingLegacyAndEmptyFinishRequestsReadWithoutCreatingOrMigratingBytes() throws {
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID))
        XCTAssertNil(fixture.defaults.object(forKey: AlarmSnoozeSessionStore.key))
        for literal in [
            "{\"version\":1,\"sessions\":[],\"legacyMarker\":true}",
            "{\"version\":1,\"sessions\":[],\"finishRequests\":[]}"
        ] {
            let bytes = Data(literal.utf8)
            fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
            XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID))
            XCTAssertEqual(fixture.bytes, bytes)
        }
    }

    func testNullFinishRequestsFailsClosedWithoutRewritingOrOpeningDebit() throws {
        let raw = Data("{\"version\":1,\"sessions\":[],\"finishRequests\":null}".utf8)
        fixture.defaults.set(raw, forKey: AlarmSnoozeSessionStore.key)
        let ticket = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: fixture.alarmID, token: nil)
        assertFinishError(.sessionUnavailable) {
            try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID)
        }
        assertFinishError(.sessionUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
        }
        assertFinishError(.sessionUnavailable) { try fixture.store().validateOccurrenceFinish(ticket) }
        assertFinishError(.sessionUnavailable) { try fixture.store().commitOccurrenceFinish(ticket) }
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0))
        XCTAssertThrowsError(try fixture.store().pendingCount(
            .init(sessionID: UUID(), attemptID: UUID()), alarmID: fixture.alarmID
        ))
        XCTAssertEqual(fixture.bytes, raw)
    }

    func testUntrackedTicketSurvivesRestartAndRetryWithoutRewritingItsBytes() throws {
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
        let raw = try fixture.rewrite { $0["marker"] = "preserve retry formatting" }
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID), ticket)
        XCTAssertEqual(try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil), ticket)
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(ticket))
        XCTAssertEqual(fixture.bytes, raw)
    }

    func testTrackedTicketResolvesExactStoredReceiptAfterRestart() throws {
        let (token, receipt) = try fixture.scheduled()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        let raw = fixture.bytes
        XCTAssertEqual(ticket.token, token)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID), ticket)
        XCTAssertEqual(try fixture.store().validateOccurrenceFinish(ticket), receipt)
        XCTAssertEqual(try fixture.store().beginOccurrenceFinish(
            alarmID: fixture.alarmID, reference: .token(token)
        ), ticket)
        XCTAssertEqual(fixture.bytes, raw)
    }

    func testExistingTicketCannotBeResumedUnderADifferentTrackedOrUntrackedReference() throws {
        let untracked = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
        let unknown = AlarmSnoozeToken(sessionID: UUID(), attemptID: UUID())
        let untrackedBytes = fixture.bytes
        assertFinishError(.ownershipUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(unknown))
        }
        XCTAssertEqual(fixture.bytes, untrackedBytes)
        try fixture.store().commitOccurrenceFinish(untracked)
        let (tracked, _) = try fixture.scheduled()
        _ = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(tracked))
        let trackedBytes = fixture.bytes
        let differingReferences: [AlarmSnoozeReference?] = [nil, .token(unknown)]
        for reference in differingReferences {
            assertFinishError(.ownershipUnavailable) {
                try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: reference)
            }
            XCTAssertEqual(fixture.bytes, trackedBytes)
        }
    }

    func testPendingFinishQuarantinesNewReservationsAcrossStoreInstancesOnlyForItsAlarm() throws {
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
        let raw = fixture.bytes
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0))
        XCTAssertEqual(fixture.bytes, raw)
        XCTAssertNoThrow(try fixture.store().reserve(alarmID: UUID(), sessionID: nil, expectedCount: 0))
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID), ticket)
    }

    func testChargedCallbackCanCompleteWithItsGenuineReceiptWhileRegistrationIsQuarantined() throws {
        let token = try fixture.charged()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        let raw = fixture.bytes
        assertFinishError(.busy) { try fixture.store().validateOccurrenceFinish(ticket) }
        XCTAssertThrowsError(try fixture.store().pendingCount(token, alarmID: fixture.alarmID))
        XCTAssertEqual(fixture.bytes, raw)
        let receipt = fixture.receipt()
        try fixture.store().complete(token, alarmID: fixture.alarmID, receipt: receipt)
        XCTAssertEqual(try fixture.store().validateOccurrenceFinish(ticket), receipt)
        XCTAssertEqual(try fixture.store().resolve(token, alarmID: fixture.alarmID).count, 1)
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "scheduled")
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID), ticket)
    }

    func testReservedChargeRejectionCanSettleWithoutInventingADerivedReceipt() throws {
        let token = try fixture.store().reserve(alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0)
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(ticket))
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0))
        try fixture.store().rejectCharge(token, alarmID: fixture.alarmID)
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(ticket))
        try fixture.store().commitOccurrenceFinish(ticket)
        XCTAssertEqual(try fixture.session(token)["count"] as? Int, 0)
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "rejected")
        XCTAssertEqual(try fixture.session(token)["finished"] as? Bool, true)
    }

    func testPendingScheduleFailureRetainsItsAttemptCountAndNoReceiptThroughScopedCommit() throws {
        let token = try fixture.charged()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        try fixture.store().complete(token, alarmID: fixture.alarmID, receipt: nil)
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(ticket))
        try fixture.store().commitOccurrenceFinish(ticket)
        XCTAssertEqual(try fixture.session(token)["count"] as? Int, 1)
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "failed")
        XCTAssertNil(try fixture.attempt(token)["receipt"])
    }

    func testOldTokenOfTheSameSessionCannotFinishItsLaterAttempt() throws {
        let (first, _) = try fixture.scheduled()
        let second = try fixture.store().reserve(alarmID: fixture.alarmID,
                                                sessionID: first.sessionID, expectedCount: 1)
        try fixture.store().recordCharge(second, alarmID: fixture.alarmID)
        try fixture.store().complete(second, alarmID: fixture.alarmID, receipt: nil)
        let raw = fixture.bytes
        assertFinishError(.ownershipUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(first))
        }
        XCTAssertEqual(fixture.bytes, raw)
        let latest = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(second))
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(latest))
    }

    func testAnotherUnfinishedSessionOfTheSameAlarmRefusesTrackedAndUntrackedFinish() throws {
        let (first, _) = try fixture.scheduled()
        _ = try fixture.scheduled()
        let raw = fixture.bytes
        let references: [AlarmSnoozeReference?] = [.token(first), nil, .unavailable]
        for reference in references {
            assertFinishError(.ownershipUnavailable) {
                try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: reference)
            }
            XCTAssertEqual(fixture.bytes, raw)
        }
    }

    func testUnknownReferenceWrongAlarmAndAlreadyFinishedSessionDoNotCreateTickets() throws {
        let (token, _) = try fixture.scheduled()
        let raw = fixture.bytes
        assertFinishError(.ownershipUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: UUID(), reference: .token(token))
        }
        assertFinishError(.ownershipUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .unavailable)
        }
        XCTAssertEqual(fixture.bytes, raw)
        try fixture.store().finish(alarmID: fixture.alarmID)
        let finished = fixture.bytes
        assertFinishError(.ownershipUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        }
        XCTAssertEqual(fixture.bytes, finished)
    }

    func testOnlyAnExactStoredTicketCanValidateOrCommit() throws {
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
        let raw = fixture.bytes
        let mismatches = [
            AlarmOccurrenceFinishTicket(id: UUID(), alarmID: ticket.alarmID, token: nil),
            AlarmOccurrenceFinishTicket(id: ticket.id, alarmID: UUID(), token: nil),
            AlarmOccurrenceFinishTicket(id: ticket.id, alarmID: ticket.alarmID,
                                        token: .init(sessionID: UUID(), attemptID: UUID()))
        ]
        for wrong in mismatches {
            assertFinishError(.ownershipUnavailable) { try fixture.store().validateOccurrenceFinish(wrong) }
            assertFinishError(.ownershipUnavailable) { try fixture.store().commitOccurrenceFinish(wrong) }
            XCTAssertEqual(fixture.bytes, raw)
        }
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID), ticket)
    }

    func testScopedCommitFinishesOnlyItsSessionAndPreservesEveryAttemptAndOtherSession() throws {
        let (older, _) = try fixture.scheduled()
        try fixture.store().finish(alarmID: fixture.alarmID)
        let olderBefore = try fixture.session(older)
        let (owned, _) = try fixture.scheduled()
        let (other, _) = try fixture.scheduled(alarmID: UUID())
        let ownedBefore = try fixture.session(owned)
        let otherBefore = try fixture.session(other)
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(owned))
        try fixture.store().commitOccurrenceFinish(ticket)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID))
        let after = try fixture.session(owned)
        XCTAssertEqual(after["finished"] as? Bool, true)
        XCTAssertEqual(after["count"] as? Int, ownedBefore["count"] as? Int)
        XCTAssertEqual(after["attempts"] as? NSArray, ownedBefore["attempts"] as? NSArray)
        XCTAssertEqual(NSDictionary(dictionary: try fixture.session(older)), NSDictionary(dictionary: olderBefore))
        XCTAssertEqual(NSDictionary(dictionary: try fixture.session(other)), NSDictionary(dictionary: otherBefore))
        XCTAssertEqual(try fixture.store().resolve(other, alarmID: try XCTUnwrap(
            UUID(uuidString: try XCTUnwrap(otherBefore["alarmID"] as? String))
        )).count, 1)
        let committed = fixture.bytes
        assertFinishError(.ownershipUnavailable) { try fixture.store().commitOccurrenceFinish(ticket) }
        XCTAssertEqual(fixture.bytes, committed)
    }

    func testTrackedTicketCanRetryAfterOneShotFullCancellationAlreadyFinishedItsSession() throws {
        let (token, receipt) = try fixture.scheduled()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        try fixture.store().finish(alarmID: fixture.alarmID)
        let finished = fixture.bytes
        XCTAssertEqual(try fixture.store().beginOccurrenceFinish(
            alarmID: fixture.alarmID, reference: .token(token)
        ), ticket)
        XCTAssertEqual(try fixture.store().validateOccurrenceFinish(ticket), receipt)
        XCTAssertEqual(fixture.bytes, finished)
        try fixture.store().commitOccurrenceFinish(ticket)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID))
    }

    func testOnlyLiveCallbackIsBusyAndDurablePendingWaitsForScopedNativeCleanupCommit() throws {
        let token = try fixture.charged()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        try fixture.store().finish(alarmID: fixture.alarmID)
        assertFinishError(.busy) { try fixture.store().validateOccurrenceFinish(ticket) }
        fixture.store().operationEnded(token)
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(ticket))
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "charged")
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0))
        try fixture.store().commitOccurrenceFinish(ticket)
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "failed")
        XCTAssertEqual(try fixture.session(token)["count"] as? Int, 1)
    }

    func testScopedCommitSettlesUnchargedDurableReservationWithoutChangingItsCount() throws {
        let token = try fixture.store().reserve(alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0)
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        XCTAssertNil(try fixture.store().validateOccurrenceFinish(ticket))
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "reserved")
        try fixture.store().commitOccurrenceFinish(ticket)
        XCTAssertEqual(try fixture.attempt(token)["phase"] as? String, "rejected")
        XCTAssertEqual(try fixture.session(token)["count"] as? Int, 0)
    }

    func testMalformedDuplicateDanglingAndMismatchedTicketsPreserveBytesAndFailClosed() throws {
        let (token, _) = try fixture.scheduled()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        let baseline = try XCTUnwrap(fixture.bytes)
        let valid = try fixture.ticketJSON(ticket)
        var wrongOwner = valid
        wrongOwner["alarmID"] = UUID().uuidString
        var dangling = valid
        dangling["token"] = ["sessionID": UUID().uuidString, "attemptID": UUID().uuidString]
        var duplicateAlarm = valid
        duplicateAlarm["id"] = UUID().uuidString
        var untrackedOverActiveSession = valid
        untrackedOverActiveSession.removeValue(forKey: "token")
        let malformedRequests: [Any] = [
            [valid, valid], [valid, duplicateAlarm], [wrongOwner], [dangling],
            [untrackedOverActiveSession], "invalid-array"
        ]
        for requests in malformedRequests {
            fixture.defaults.set(baseline, forKey: AlarmSnoozeSessionStore.key)
            let raw = try fixture.rewrite { $0["finishRequests"] = requests }
            assertFinishError(.sessionUnavailable) {
                try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID)
            }
            XCTAssertThrowsError(try fixture.store().reserve(
                alarmID: fixture.alarmID, sessionID: nil, expectedCount: 0
            ))
            assertFinishError(.sessionUnavailable) { try fixture.store().commitOccurrenceFinish(ticket) }
            XCTAssertEqual(fixture.bytes, raw)
        }
    }

    func testNewerAttemptBehindATicketIsRejectedWithoutMutatingTheNewerOwner() throws {
        let (token, _) = try fixture.scheduled()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        let raw = try fixture.rewrite { envelope in
            var sessions = try XCTUnwrap(envelope["sessions"] as? [[String: Any]])
            var attempts = try XCTUnwrap(sessions[0]["attempts"] as? [[String: Any]])
            attempts.append(["id": UUID().uuidString, "phase": "rejected"])
            sessions[0]["attempts"] = attempts
            envelope["sessions"] = sessions
        }
        assertFinishError(.sessionUnavailable) { try fixture.store().validateOccurrenceFinish(ticket) }
        assertFinishError(.sessionUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: .token(token))
        }
        XCTAssertEqual(fixture.bytes, raw)
    }

    func testCorruptUnknownVersionAndNonDataContextStayUntouchedForEveryFinishEntryPoint() throws {
        let ticket = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: fixture.alarmID, token: nil)
        for bytes in [Data("broken".utf8), Data("{\"version\":2,\"sessions\":[]}".utf8)] {
            fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
            assertFinishError(.sessionUnavailable) {
                try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
            }
            assertFinishError(.sessionUnavailable) { try fixture.store().validateOccurrenceFinish(ticket) }
            assertFinishError(.sessionUnavailable) { try fixture.store().commitOccurrenceFinish(ticket) }
            assertFinishError(.sessionUnavailable) {
                try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID)
            }
            XCTAssertEqual(fixture.bytes, bytes)
        }
        fixture.defaults.set("not-data", forKey: AlarmSnoozeSessionStore.key)
        assertFinishError(.sessionUnavailable) {
            try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarmID, reference: nil)
        }
        assertFinishError(.sessionUnavailable) { try fixture.store().validateOccurrenceFinish(ticket) }
        assertFinishError(.sessionUnavailable) { try fixture.store().commitOccurrenceFinish(ticket) }
        assertFinishError(.sessionUnavailable) {
            try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarmID)
        }
        XCTAssertEqual(fixture.defaults.string(forKey: AlarmSnoozeSessionStore.key), "not-data")
    }

    private func assertFinishError<T>(
        _ expected: AlarmOccurrenceFinishError, _ operation: () throws -> T,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, expected, file: file, line: line)
        }
    }
}

@MainActor
private final class FinishSessionFixture {
    let alarmID = UUID()
    let suite: String
    let defaults: UserDefaults
    var chargedTokens: [AlarmSnoozeToken] = []
    var bytes: Data? { defaults.data(forKey: AlarmSnoozeSessionStore.key) }

    init() {
        let suite = "test.occurrence-finish.\(UUID().uuidString)"
        self.suite = suite
        defaults = UserDefaults(suiteName: suite)!
    }
    func store() -> AlarmSnoozeSessionStore { AlarmSnoozeSessionStore(defaults: defaults) }
    func close() {
        chargedTokens.forEach { store().operationEnded($0) }
        defaults.removePersistentDomain(forName: suite)
    }
    func receipt() -> AlarmSnoozeReceipt {
        .init(systemID: UUID(), fireDate: Date(timeIntervalSince1970: 1_000))
    }
    func charged(alarmID owner: UUID? = nil) throws -> AlarmSnoozeToken {
        let owner = owner ?? alarmID
        let token = try store().reserve(alarmID: owner, sessionID: nil, expectedCount: 0)
        try store().recordCharge(token, alarmID: owner)
        chargedTokens.append(token)
        return token
    }
    func scheduled(alarmID owner: UUID? = nil) throws -> (AlarmSnoozeToken, AlarmSnoozeReceipt) {
        let owner = owner ?? alarmID
        let token = try charged(alarmID: owner)
        let receipt = receipt()
        try store().complete(token, alarmID: owner, receipt: receipt)
        return (token, receipt)
    }
    func object() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(bytes)) as? [String: Any])
    }
    func session(_ token: AlarmSnoozeToken) throws -> [String: Any] {
        let sessions = try XCTUnwrap(try object()["sessions"] as? [[String: Any]])
        return try XCTUnwrap(sessions.first { ($0["id"] as? String) == token.sessionID.uuidString })
    }
    func attempt(_ token: AlarmSnoozeToken) throws -> [String: Any] {
        let attempts = try XCTUnwrap(try session(token)["attempts"] as? [[String: Any]])
        return try XCTUnwrap(attempts.first { ($0["id"] as? String) == token.attemptID.uuidString })
    }
    func ticketJSON(_ ticket: AlarmOccurrenceFinishTicket) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ticket)) as? [String: Any])
    }
    func rewrite(_ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        var envelope = try object()
        try mutate(&envelope)
        let raw = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        defaults.set(raw, forKey: AlarmSnoozeSessionStore.key)
        return raw
    }
}
