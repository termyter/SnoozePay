import XCTest
@testable import SnoozePay

@MainActor
final class AlarmOccurrenceRecoveryTests: XCTestCase {
    func testFreshDiscoveryRestoresExactTrackedTicketWithoutWritingOrWaking() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let before = fixture.defaults.dictionaryRepresentation()

        for _ in 0..<2 {
            let entries = try fixture.recoveryService().pendingFinishes()
            XCTAssertEqual(entries.map(\.ticket), [ticket])
            XCTAssertEqual(entries.first?.alarmName, fixture.alarm.name)
        }

        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
    }

    func testExplicitTrackedRetryCommitsOnlyItsTicketAndRecordsCurrentConfirmationOnce() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let confirmation = Date()
        let service = fixture.recoveryService(now: { confirmation })
        let ledger = try fixture.ledger.fetchAllChecked()
        let balance = fixture.wallet.balance

        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        XCTAssertEqual(fixture.backend.occurrenceVerificationRequests.count, 1)
        XCTAssertEqual(fixture.backend.occurrenceVerificationRequests.first?.alarmID, ticket.alarmID)
        XCTAssertEqual(fixture.wakes.wakeTimes(), [confirmation])
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: ticket.alarmID))
        XCTAssertEqual(fixture.wallet.balance, balance)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().map(\.id), ledger.map(\.id))
        let settled = fixture.defaults.dictionaryRepresentation()

        XCTAssertEqual(service.resume(ticket), .success(.alreadyCompleted))
        XCTAssertEqual(fixture.recoveryService().resume(ticket), .failure(.ownershipUnavailable))
        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, settled as NSDictionary)
        XCTAssertEqual(fixture.backend.occurrenceVerificationRequests.count, 1)
        assertNoNativeMutation(fixture)
    }

    func testNativeRefusalRetainsExactRequestAndAllMoneyUntilExplicitRetry() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        fixture.backend.occurrenceVerificationResult = .failure(.nativeUnconfirmed)
        let before = fixture.defaults.dictionaryRepresentation()
        let service = fixture.recoveryService()

        XCTAssertEqual(service.resume(ticket), .failure(.nativeUnconfirmed))
        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertEqual(try service.pendingFinishes().map(\.ticket), [ticket])
        assertNoNativeMutation(fixture)

        fixture.backend.occurrenceVerificationResult = .success(())
        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        XCTAssertEqual(fixture.wallet.balance, 150)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().filter { $0.type == .charge }.count, 1)
        XCTAssertTrue(try fixture.ledger.fetchAllChecked().filter { $0.type == .refund }.isEmpty)
    }

    func testLivePhysicalCallbackStaysBusyWithoutAnyNativeProbeOrWake() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let store = fixture.store()
        let token = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        XCTAssertNotNil(fixture.wallet.chargeWithReceipt(amount: 50, alarmID: fixture.alarm.id))
        try store.recordCharge(token, alarmID: fixture.alarm.id)
        defer { store.operationEnded(token) }
        let ticket = try store.beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: .token(token))
        let bytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let service = fixture.recoveryService()

        XCTAssertEqual(try service.pendingFinishes().map(\.ticket), [ticket])
        XCTAssertEqual(service.resume(ticket), .failure(.busy))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        assertNoNativeMutation(fixture)
    }

    func testForgedTicketCannotAcquireAnotherRequestOrReachNativeProof() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let before = fixture.defaults.dictionaryRepresentation()
        let forgeries = [
            AlarmOccurrenceFinishTicket(id: UUID(), alarmID: ticket.alarmID, token: ticket.token),
            AlarmOccurrenceFinishTicket(id: ticket.id, alarmID: ticket.alarmID, token: nil),
            AlarmOccurrenceFinishTicket(id: ticket.id, alarmID: UUID(), token: ticket.token)
        ]
        let service = fixture.recoveryService()
        for forged in forgeries { XCTAssertEqual(service.resume(forged), .failure(.ownershipUnavailable)) }
        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        assertNoNativeMutation(fixture)
    }

    func testCorruptSessionDiscoveryAndRetryPreserveBytesAndNeverPretendEmpty() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let bytes = Data("corrupt-pending-ticket".utf8)
        fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
        let service = fixture.recoveryService()

        XCTAssertThrowsError(try service.pendingFinishes())
        XCTAssertEqual(service.resume(ticket), .failure(.sessionUnavailable))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
    }

    func testWrongTypeCorruptAndDuplicateAlarmSnapshotsRefuseWithoutOverwriting() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let corrupt = Data("corrupt".utf8)
        let invalid: [Any] = [
            "not-data", corrupt, try JSONEncoder().encode([fixture.alarm, fixture.alarm])
        ]
        let service = fixture.recoveryService()
        for value in invalid {
            fixture.defaults.set(value, forKey: "stored_alarms")
            var expected = fixture.defaults.dictionaryRepresentation()
            if let data = value as? Data, data == corrupt {
                expected[AlarmRepository.corruptBackupKey] = corrupt
            }
            XCTAssertThrowsError(try service.pendingFinishes())
            guard case .failure = service.resume(ticket) else { return XCTFail("Invalid snapshot must refuse") }
            XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, expected as NSDictionary)
            XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        }
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
    }

    func testMissingAlarmStillHasDurableEntryAndUsesCheckedAbsenceRequest() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        fixture.defaults.removeObject(forKey: "stored_alarms")
        let service = fixture.recoveryService()

        let entry = try XCTUnwrap(service.pendingFinishes().first)
        XCTAssertEqual(entry.ticket, ticket)
        XCTAssertNil(entry.alarmName)
        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        XCTAssertNil(fixture.backend.occurrenceVerificationRequests.first?.weekly)
        XCTAssertTrue(try fixture.repository.fetchOccurrenceFinishAlarms().isEmpty)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        assertNoNativeMutation(fixture)
    }

    func testOneShotRetryUsesPersistOnlyDisableAfterProofWithoutFullCancellation() throws {
        let fixture = try OccurrenceVMFixture(oneShot: true)
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let service = fixture.recoveryService()

        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        XCTAssertFalse(try XCTUnwrap(fixture.repository.fetchChecked(id: fixture.alarm.id)).enabled)
        XCTAssertNil(fixture.backend.occurrenceVerificationRequests.first?.weekly)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        XCTAssertEqual(fixture.wallet.balance, 150)
        assertNoNativeMutation(fixture)
    }

    func testUntrackedQuietRequestDoesNotInventATokenChargeOrBillingSession() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: fixture.alarm.id, reference: nil)
        let service = fixture.recoveryService()

        XCTAssertEqual(try service.pendingFinishes().map(\.ticket), [ticket])
        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.first?.allowsUntrackedDerived == true)
        XCTAssertNil(fixture.backend.occurrenceVerificationRequests.first?.expectedDerivedFireDate)
        XCTAssertEqual(fixture.wallet.balance, 200)
        XCTAssertTrue(try fixture.ledger.fetchAllChecked().filter { $0.type == .charge }.isEmpty)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        assertNoNativeMutation(fixture)
    }

    func testRefusedOneShotWriteKeepsTicketAndNoWakeUntilARealReadback() throws {
        let fixture = try OccurrenceVMFixture(oneShot: true)
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let service = fixture.recoveryService()
        let bytes = fixture.defaults.data(forKey: "stored_alarms")
        fixture.defaults.skippedKey = "stored_alarms"

        XCTAssertEqual(service.resume(ticket), .failure(.persistenceFailed))
        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), bytes)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: ticket.alarmID), ticket)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        assertNoNativeMutation(fixture)

        fixture.defaults.skippedKey = nil
        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testRefusedTicketCommitDoesNotClaimSuccessOrWakeAndCanBeRetried() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let bytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        fixture.defaults.skippedKey = AlarmSnoozeSessionStore.key
        let service = fixture.recoveryService()

        XCTAssertEqual(service.resume(ticket), .failure(.persistenceFailed))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
        fixture.defaults.skippedKey = nil
        XCTAssertEqual(service.resume(ticket), .success(.completedNow))
        assertNoNativeMutation(fixture)
    }

    func testChangedModelDuringReadOnlyVerificationCannotBeOverwrittenOrCommitted() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let replacement = fixture.alarm.with(name: "newer edit")
        let verifier = RecoveryTestVerifier()
        verifier.onVerify = { XCTAssertTrue(fixture.seedRepository.save(replacement)) }
        let service = fixture.recoveryService(verifier: verifier)
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(service.resume(ticket), .failure(.ownershipUnavailable))
        XCTAssertEqual(try fixture.repository.fetchChecked(id: fixture.alarm.id), replacement)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
        XCTAssertEqual(verifier.tickets, [ticket])
        assertNoNativeMutation(fixture)
    }

    private func assertNoNativeMutation(_ fixture: OccurrenceVMFixture) {
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledOriginalIDs.isEmpty)
        XCTAssertTrue(fixture.backend.stoppedIDs.isEmpty)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)
        XCTAssertTrue(fixture.backend.scheduledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.snoozedIDs.isEmpty)
    }
}

@MainActor
extension OccurrenceVMFixture {
    func recoveryTrackedTicket() throws -> AlarmOccurrenceFinishTicket {
        let sessions = store()
        let token = try sessions.reserve(alarmID: alarm.id, sessionID: nil, expectedCount: 0)
        XCTAssertNotNil(wallet.chargeWithReceipt(amount: 50, alarmID: alarm.id))
        try sessions.recordCharge(token, alarmID: alarm.id)
        defer { sessions.operationEnded(token) }
        try sessions.complete(token, alarmID: alarm.id, receipt: AlarmSnoozeReceipt(
            systemID: AlarmKitScheduler.snoozeID(for: alarm.id), fireDate: Date().addingTimeInterval(-60)
        ))
        return try sessions.beginOccurrenceFinish(alarmID: alarm.id, reference: .token(token))
    }

    func recoveryService(
        now: @escaping () -> Date = Date.init, verifier: AlarmOccurrenceRecoveryVerifying? = nil
    ) -> AlarmOccurrenceRecovery {
        AlarmOccurrenceRecovery(repository: repository, scheduler: verifier ?? scheduler,
                                sessions: store(), wakes: wakes, now: now)
    }
}

@MainActor
final class RecoveryTestVerifier: AlarmOccurrenceRecoveryVerifying {
    var onVerify: (() -> Void)?
    private(set) var tickets: [AlarmOccurrenceFinishTicket] = []
    func verifyPendingOccurrenceFinish(
        currentAlarm: Alarm?, ticket: AlarmOccurrenceFinishTicket
    ) -> Result<Void, AlarmOccurrenceFinishError> {
        tickets.append(ticket)
        onVerify?()
        return .success(())
    }
}
