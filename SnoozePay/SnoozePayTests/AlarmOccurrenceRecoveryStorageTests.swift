import XCTest
@testable import SnoozePay

@MainActor
final class AlarmOccurrenceRecoveryStorageTests: XCTestCase {
    func testEnumerationOfMissingLegacyAndEmptyMetadataNeverCreatesOrMigratesBytes() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        XCTAssertTrue(try fixture.store().pendingOccurrenceFinishes().isEmpty)
        XCTAssertNil(fixture.defaults.object(forKey: AlarmSnoozeSessionStore.key))
        for literal in [
            "{\"version\":1,\"sessions\":[],\"marker\":\"keep legacy\"}",
            "{\"version\":1,\"sessions\":[],\"finishRequests\":[]}"
        ] {
            let raw = Data(literal.utf8)
            fixture.defaults.set(raw, forKey: AlarmSnoozeSessionStore.key)
            let before = fixture.domain
            XCTAssertTrue(try fixture.store().pendingOccurrenceFinishes().isEmpty)
            XCTAssertEqual(fixture.domain, before)
            XCTAssertEqual(fixture.sessionBytes, raw)
        }
    }

    func testEnumerationFindsExactTrackedAndUntrackedTicketsAcrossFreshStoreInstancesInStableOrder() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let token = try fixture.scheduled()
        let tracked = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: .token(token))
        let untracked = try fixture.store().beginOccurrenceFinish(alarmID: UUID(), reference: nil)
        let before = fixture.domain
        let expected = [tracked, untracked].sorted { $0.id.uuidString < $1.id.uuidString }

        XCTAssertEqual(try fixture.store().pendingOccurrenceFinishes(), expected)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinishes(), expected)
        XCTAssertEqual(expected.first(where: { $0.id == tracked.id })?.token, token)
        XCTAssertEqual(fixture.domain, before)
    }

    func testEnumerationRetainsAValidTrackedRequestAfterItsSessionWasFullyCancelled() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let token = try fixture.scheduled()
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: .token(token))
        try fixture.store().finish(alarmID: fixture.alarm.id)
        let before = fixture.domain

        XCTAssertEqual(try fixture.store().pendingOccurrenceFinishes(), [ticket])
        XCTAssertEqual(try fixture.store().validateOccurrenceFinish(ticket), fixture.receipt)
        XCTAssertEqual(fixture.domain, before)
    }

    func testEnumerationKeepsLiveCallbackDiscoverableButExplicitValidationRemainsBusy() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let token = try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        defer { fixture.store().operationEnded(token) }
        try fixture.store().recordCharge(token, alarmID: fixture.alarm.id)
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: .token(token))
        let before = fixture.domain

        XCTAssertEqual(try fixture.store().pendingOccurrenceFinishes(), [ticket])
        assertFinishError(.busy) { try fixture.store().validateOccurrenceFinish(ticket) }
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0))
        XCTAssertEqual(fixture.domain, before)
        try fixture.store().complete(token, alarmID: fixture.alarm.id, receipt: fixture.receipt)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinishes(), [ticket])
        XCTAssertEqual(try fixture.store().validateOccurrenceFinish(ticket), fixture.receipt)
    }

    func testEnumerationRejectsARequestForAnEarlierAttemptWithoutRewritingItsEvidence() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let token = try fixture.scheduled()
        _ = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: .token(token))
        let raw = try fixture.rewriteSessions { envelope in
            var sessions = try XCTUnwrap(envelope["sessions"] as? [[String: Any]])
            var attempts = try XCTUnwrap(sessions[0]["attempts"] as? [[String: Any]])
            attempts.append(["id": UUID().uuidString, "phase": "rejected"])
            sessions[0]["attempts"] = attempts
            envelope["sessions"] = sessions
        }

        assertFinishError(.sessionUnavailable) { try fixture.store().pendingOccurrenceFinishes() }
        XCTAssertEqual(fixture.sessionBytes, raw)
    }

    func testEnumerationRejectsAnotherUnfinishedOwnerWithoutDroppingThePendingRequest() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let token = try fixture.scheduled()
        _ = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: .token(token))
        let raw = try fixture.rewriteSessions { envelope in
            var sessions = try XCTUnwrap(envelope["sessions"] as? [[String: Any]])
            sessions.append([
                "id": UUID().uuidString, "alarmID": fixture.alarm.id.uuidString,
                "count": 0, "finished": false, "attempts": []
            ])
            envelope["sessions"] = sessions
        }

        assertFinishError(.sessionUnavailable) { try fixture.store().pendingOccurrenceFinishes() }
        XCTAssertEqual(fixture.sessionBytes, raw)
    }

    func testEnumerationRejectsCorruptNullAndDuplicateMetadataWithoutTreatingItAsEmpty() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: nil)
        let duplicate = try fixture.rewriteSessions { envelope in
            let requests = try XCTUnwrap(envelope["finishRequests"] as? [[String: Any]])
            envelope["finishRequests"] = requests + requests
        }
        for raw in [
            Data("corrupt-session-bytes".utf8),
            Data("{\"version\":1,\"sessions\":[],\"finishRequests\":null}".utf8), duplicate
        ] {
            fixture.defaults.set(raw, forKey: AlarmSnoozeSessionStore.key)
            assertFinishError(.sessionUnavailable) { try fixture.store().pendingOccurrenceFinishes() }
            XCTAssertEqual(fixture.sessionBytes, raw)
        }
        fixture.defaults.set("unreadable-type", forKey: AlarmSnoozeSessionStore.key)
        assertFinishError(.sessionUnavailable) { try fixture.store().pendingOccurrenceFinishes() }
        XCTAssertEqual(fixture.defaults.string(forKey: AlarmSnoozeSessionStore.key), "unreadable-type")
        XCTAssertEqual(ticket.alarmID, fixture.alarm.id)
    }

    func testOccurrenceFinishReadDistinguishesMissingEmptyAndHealthyInventoryWithoutWriting() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        XCTAssertTrue(try fixture.repository.fetchOccurrenceFinishAlarms().isEmpty)
        XCTAssertNil(fixture.defaults.object(forKey: "stored_alarms"))
        for alarms in [[], [fixture.alarm]] {
            try fixture.writeAlarms(alarms)
            let before = fixture.domain
            XCTAssertEqual(try fixture.repository.fetchOccurrenceFinishAlarms(), alarms)
            XCTAssertEqual(fixture.domain, before)
            XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
            XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
        }
    }

    func testOccurrenceFinishReadRejectsUnknownTypeAndAnyDuplicateIdentityWithoutOverwriting() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        fixture.defaults.set("unknown-storage-type", forKey: "stored_alarms")
        let unknown = fixture.domain
        assertFinishError(.persistenceFailed) { try fixture.repository.fetchOccurrenceFinishAlarms() }
        XCTAssertEqual(fixture.domain, unknown)
        let other = Alarm(repeatDays: [6], name: "Other")
        try fixture.writeAlarms([fixture.alarm, other, other])
        let duplicate = fixture.domain
        assertFinishError(.ownershipUnavailable) { try fixture.repository.fetchOccurrenceFinishAlarms() }
        assertFinishError(.ownershipUnavailable) { try fixture.repository.persistFinishedOneShot(fixture.alarm) }
        XCTAssertEqual(fixture.domain, duplicate)
        XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
        XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
    }

    func testOccurrenceFinishReadRefusesMalformedBytesAndPreservesDiagnosticEvidence() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let raw = Data("invalid-finish-inventory".utf8)
        fixture.defaults.set(raw, forKey: "stored_alarms")
        assertFinishError(.persistenceFailed) { try fixture.repository.fetchOccurrenceFinishAlarms() }
        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), raw)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), raw)
        XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
        XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
    }

    func testPersistOnlyOneShotDisableRetainsEveryOtherFieldAndAlarmWithoutScheduling() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let unrelated = Alarm(time: fixture.alarm.time.addingTimeInterval(3_600), repeatDays: [6], name: "Other")
        for expected in [fixture.alarm, fixture.alarm.with(repeatDays: [], repeatMode: .weekly)] {
            try fixture.writeAlarms([unrelated, expected])
            try fixture.repository.persistFinishedOneShot(expected)
            let stored = try fixture.repository.fetchAllChecked()
            XCTAssertEqual(stored.first(where: { $0.id == expected.id }), expected.with(enabled: false))
            XCTAssertEqual(stored.first(where: { $0.id == unrelated.id }), unrelated)
            XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
            XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
        }
    }

    func testPersistOnlyDisableRefusesAnyChangedCapturedRecordWithoutOverwritingIt() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        for changed in [
            fixture.alarm.with(time: fixture.alarm.time.addingTimeInterval(60)),
            fixture.alarm.with(repeatDays: [6]), fixture.alarm.with(name: "Renamed"),
            fixture.alarm.with(enabled: false), fixture.alarm.with(repeatMode: .weekly)
        ] {
            try fixture.writeAlarms([changed])
            let before = fixture.domain
            assertFinishError(.ownershipUnavailable) { try fixture.repository.persistFinishedOneShot(fixture.alarm) }
            XCTAssertEqual(fixture.domain, before)
            XCTAssertEqual(try fixture.repository.fetchChecked(id: fixture.alarm.id), changed)
            XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
            XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
        }
    }

    func testPersistOnlyDisableRefusesEnabledWeeklyAndAlreadyDisabledExpectedRecords() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        for expected in [fixture.alarm.with(repeatMode: .weekly), fixture.alarm.with(enabled: false)] {
            try fixture.writeAlarms([expected])
            let before = fixture.domain
            assertFinishError(.ownershipUnavailable) { try fixture.repository.persistFinishedOneShot(expected) }
            XCTAssertEqual(fixture.domain, before)
            XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
            XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
        }
    }

    func testPersistOnlyDisableRefusesMissingOrDuplicateCurrentIdentityWithoutCreatingAnAlarm() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        for alarms in [[], [fixture.alarm, fixture.alarm]] {
            try fixture.writeAlarms(alarms)
            let before = fixture.domain
            assertFinishError(.ownershipUnavailable) { try fixture.repository.persistFinishedOneShot(fixture.alarm) }
            XCTAssertEqual(fixture.domain, before)
            XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
            XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
        }
    }

    func testPersistOnlyDisableDetectsDroppedWriteAndLeavesTheOriginalEnabledRecord() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        try fixture.writeAlarms([fixture.alarm])
        let before = fixture.domain
        fixture.defaults.rejectAlarmWrites = true

        assertFinishError(.persistenceFailed) { try fixture.repository.persistFinishedOneShot(fixture.alarm) }

        XCTAssertEqual(fixture.domain, before)
        XCTAssertEqual(try fixture.repository.fetchChecked(id: fixture.alarm.id), fixture.alarm)
        XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
        XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
    }

    func testPersistOnlyDisablePreservesUnreadableAlarmBytesAndNeverCallsScheduler() throws {
        let fixture = try RecoveryStorageFixture()
        defer { fixture.close() }
        let raw = Data("corrupt-alarm-evidence".utf8)
        fixture.defaults.set(raw, forKey: "stored_alarms")

        assertFinishError(.persistenceFailed) { try fixture.repository.persistFinishedOneShot(fixture.alarm) }

        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), raw)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), raw)
        fixture.defaults.set("unreadable-alarm-type", forKey: "stored_alarms")
        assertFinishError(.persistenceFailed) { try fixture.repository.persistFinishedOneShot(fixture.alarm) }
        XCTAssertEqual(fixture.defaults.string(forKey: "stored_alarms"), "unreadable-alarm-type")
        XCTAssertTrue(fixture.scheduler.scheduled.isEmpty)
        XCTAssertTrue(fixture.scheduler.cancelled.isEmpty)
    }

    private func assertFinishError<T>(
        _ expected: AlarmOccurrenceFinishError, file: StaticString = #filePath, line: UInt = #line,
        _ body: () throws -> T
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, expected, file: file, line: line)
        }
    }
}

@MainActor
private final class RecoveryStorageFixture {
    let suite: String
    let defaults: RecoveryStorageDefaults
    let scheduler = RecoveryStorageScheduler()
    let alarm = Alarm(
        time: Date(timeIntervalSince1970: 1_800_000_000), repeatDays: [0, 2], name: "Recovery",
        penaltyAmount: 75, progressiveScale: true, repeatMode: .never
    )
    var repository: AlarmRepository { AlarmRepository(defaults: defaults, scheduler: scheduler) }
    var sessionBytes: Data? { defaults.data(forKey: AlarmSnoozeSessionStore.key) }
    var domain: NSDictionary { NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]) }
    var receipt: AlarmSnoozeReceipt {
        AlarmSnoozeReceipt(systemID: AlarmKitScheduler.snoozeID(for: alarm.id),
                           fireDate: Date(timeIntervalSince1970: 1_800_000_600))
    }

    init() throws {
        let suite = "OccurrenceRecoveryStorage-\(UUID().uuidString)"
        self.suite = suite
        defaults = try XCTUnwrap(RecoveryStorageDefaults(suiteName: suite))
    }
    func close() { defaults.removePersistentDomain(forName: suite) }
    func store() -> AlarmSnoozeSessionStore { AlarmSnoozeSessionStore(defaults: defaults) }
    func writeAlarms(_ alarms: [Alarm]) throws {
        defaults.set(try JSONEncoder().encode(alarms), forKey: "stored_alarms")
    }
    func scheduled() throws -> AlarmSnoozeToken {
        let token = try store().reserve(alarmID: alarm.id, sessionID: nil, expectedCount: 0)
        defer { store().operationEnded(token) }
        try store().recordCharge(token, alarmID: alarm.id)
        try store().complete(token, alarmID: alarm.id, receipt: receipt)
        return token
    }
    func rewriteSessions(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sessionBytes)) as? [String: Any])
        try change(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        defaults.set(data, forKey: AlarmSnoozeSessionStore.key)
        return data
    }
}

private final class RecoveryStorageScheduler: AlarmScheduling {
    private(set) var scheduled: [UUID] = []
    private(set) var cancelled: [UUID] = []
    func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
        scheduled.append(alarm.id)
        completion?(.success(()))
    }
    func cancel(_ alarmID: UUID) { cancelled.append(alarmID) }
}

private final class RecoveryStorageDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var rejected = false
    var rejectAlarmWrites: Bool {
        get { lock.lock(); defer { lock.unlock() }; return rejected }
        set { lock.lock(); defer { lock.unlock() }; rejected = newValue }
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        guard defaultName != "stored_alarms" || !rejectAlarmWrites else { return }
        super.set(value, forKey: defaultName)
    }
}
