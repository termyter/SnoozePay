import XCTest
@testable import SnoozePay

@MainActor
final class AlarmOccurrenceViewModelTests: XCTestCase {
    func testWeeklyFinishPreservesEnabledAlarmAndPublishesOnlyConfirmedWake() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let model = fixture.model()
        let balance = fixture.wallet.balance

        XCTAssertEqual(model.dismiss(), .success(.completedNow))

        XCTAssertTrue(try XCTUnwrap(fixture.repository.fetchChecked(id: fixture.alarm.id)).enabled)
        XCTAssertEqual(fixture.backend.occurrenceFinishRequests.count, 1)
        let request = try XCTUnwrap(fixture.backend.occurrenceFinishRequests.first)
        XCTAssertEqual(request.weekly?.hour, 7)
        XCTAssertEqual(request.weekly?.minute, 10)
        XCTAssertEqual(request.weekly?.mondayFirstDays, [0, 2])
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wallet.balance, balance)
    }

    func testFailedNativeFinishKeepsWakeEmptyTicketAndEarlyDebitGuardUntilRetry() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        fixture.backend.occurrenceFinishResult = .failure(.nativeUnconfirmed)
        let model = fixture.model()
        let rows = try fixture.ledger.fetchAllChecked()

        XCTAssertEqual(model.dismiss(), .failure(.nativeUnconfirmed))
        let ticket = try XCTUnwrap(fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertTrue(model.finishRequested)
        XCTAssertFalse(model.snooze())
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().map(\.id), rows.map(\.id))
        XCTAssertTrue(fixture.backend.snoozedIDs.isEmpty)
        XCTAssertThrowsError(try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0))

        fixture.backend.occurrenceFinishResult = .success(())
        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        XCTAssertEqual(fixture.backend.occurrenceFinishRequests.count, 2)
        XCTAssertEqual(ticket.alarmID, fixture.alarm.id)
    }

    func testAnotherViewModelResumesTheSameUntrackedTicketWithoutAnotherDebit() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        fixture.backend.occurrenceFinishResult = .failure(.inventoryUnavailable)
        XCTAssertEqual(fixture.model().dismiss(), .failure(.inventoryUnavailable))
        let ticket = try XCTUnwrap(fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        let reopened = fixture.model()

        XCTAssertTrue(reopened.finishRequested)
        XCTAssertFalse(reopened.snooze())
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id), ticket)
        fixture.backend.occurrenceFinishResult = .success(())
        XCTAssertEqual(reopened.dismiss(), .success(.completedNow))
        XCTAssertEqual(fixture.wallet.balance, 200)
        XCTAssertTrue(try fixture.ledger.fetchAllChecked().filter { $0.type == .charge }.isEmpty)
    }

    func testDuplicateFinishReturnsAlreadyCompletedWithoutMoreNativeWorkOrWrites() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let model = fixture.model()
        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        let snapshot = fixture.defaults.dictionaryRepresentation()

        XCTAssertEqual(model.dismiss(), .success(.alreadyCompleted))

        XCTAssertEqual(fixture.backend.occurrenceFinishRequests.count, 1)
        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, snapshot as NSDictionary)
    }

    func testOneShotWriteReadbackFailureRetainsTicketAndWakeUntilActualPersistence() throws {
        let fixture = try OccurrenceVMFixture(oneShot: true)
        defer { fixture.close() }
        let model = fixture.model()
        let alarmBytes = fixture.defaults.data(forKey: "stored_alarms")
        fixture.defaults.skippedKey = "stored_alarms"

        XCTAssertEqual(model.dismiss(), .failure(.persistenceFailed))
        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), alarmBytes)
        XCTAssertTrue(try XCTUnwrap(fixture.repository.fetchChecked(id: fixture.alarm.id)).enabled)
        XCTAssertNotNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)

        fixture.defaults.skippedKey = nil
        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        XCTAssertFalse(try XCTUnwrap(fixture.repository.fetchChecked(id: fixture.alarm.id)).enabled)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testSessionCommitReadbackFailureKeepsQuarantineAndAllowsTheSameRetry() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let model = fixture.model()
        fixture.backend.occurrenceFinishResult = .failure(.nativeUnconfirmed)
        XCTAssertEqual(model.dismiss(), .failure(.nativeUnconfirmed))
        let pendingBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        fixture.backend.occurrenceFinishResult = .success(())
        fixture.defaults.skippedKey = AlarmSnoozeSessionStore.key

        XCTAssertEqual(model.dismiss(), .failure(.persistenceFailed))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), pendingBytes)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertFalse(fixture.model().snooze())

        fixture.defaults.skippedKey = nil
        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testCorruptSessionBytesOnlyAttemptOriginalStopAndNeverRecordWake() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let bytes = Data("corrupt-session".utf8)
        fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(fixture.model().dismiss(), .failure(.sessionUnavailable))

        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertEqual(fixture.backend.finishOriginalStopIDs, [fixture.alarm.id])
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.lateSnoozeCleanupRequests.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
    }

    func testUnreadableAlarmStorePreservesBytesAndDoesNotReportNativeFinish() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let bytes = Data("corrupt-alarms".utf8)
        fixture.defaults.set(bytes, forKey: "stored_alarms")

        XCTAssertEqual(fixture.model().dismiss(), .failure(.persistenceFailed))

        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), bytes)
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertEqual(fixture.backend.finishOriginalStopIDs, [fixture.alarm.id])
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
    }

    func testWrongTypeAlarmStoreCannotBecomeMissingAndCancelTheNativeOriginal() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        fixture.defaults.set("wrong-type-alarm-evidence", forKey: "stored_alarms")

        XCTAssertEqual(fixture.model().dismiss(), .failure(.persistenceFailed))

        XCTAssertEqual(fixture.defaults.string(forKey: "stored_alarms"), "wrong-type-alarm-evidence")
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledOriginalIDs.isEmpty)
        XCTAssertEqual(fixture.backend.finishOriginalStopIDs, [fixture.alarm.id])
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
    }

    func testChangedRepositoryScheduleRefusesStaleScreenWithoutStoppingAnotherOwner() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let model = fixture.model()
        let updated = fixture.alarm.with(time: fixture.alarm.time.addingTimeInterval(3_600))
        XCTAssertTrue(fixture.seedRepository.save(updated))
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(model.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertEqual(try fixture.repository.fetchChecked(id: fixture.alarm.id)?.time, updated.time)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
    }

    func testCheckedMissingAlarmCanFinishWithoutRecreatingIt() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        XCTAssertTrue(fixture.seedRepository.delete(id: fixture.alarm.id))

        XCTAssertEqual(fixture.model().dismiss(), .success(.completedNow))

        XCTAssertNil(try fixture.repository.fetchChecked(id: fixture.alarm.id))
        XCTAssertNil(try XCTUnwrap(fixture.backend.occurrenceFinishRequests.last).weekly)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testDisabledSnapshotCannotFinishAReenabledWeeklyOriginal() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        XCTAssertTrue(fixture.seedRepository.setEnabled(false, id: fixture.alarm.id))
        let captured = try XCTUnwrap(fixture.seedRepository.fetchChecked(id: fixture.alarm.id))
        XCTAssertFalse(captured.enabled)
        let stale = fixture.model(captured)
        XCTAssertTrue(fixture.seedRepository.setEnabled(true, id: fixture.alarm.id))
        let alarmBytes = fixture.defaults.data(forKey: "stored_alarms")
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(stale.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), alarmBytes)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertTrue(try XCTUnwrap(fixture.repository.fetchChecked(id: fixture.alarm.id)).enabled)
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
    }

    func testOlderAttemptCannotFinishTheNewerAttemptOfTheSameSession() throws {
        let fixture = TrackedSessionFixture()
        defer { fixture.close() }
        let store = fixture.store()
        let first = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(first, alarmID: fixture.alarm.id)
        try store.complete(first, alarmID: fixture.alarm.id, receipt: nil)
        let second = try store.reserve(alarmID: fixture.alarm.id, sessionID: first.sessionID, expectedCount: 1)
        try store.recordCharge(second, alarmID: fixture.alarm.id)
        try store.complete(second, alarmID: fixture.alarm.id, receipt: nil)
        let backend = TrackedSessionBackend()
        let stale = fixture.model(backend: backend, reference: .token(first))
        let bytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(stale.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertEqual(try store.resolve(second, alarmID: fixture.alarm.id).count, 2)
        XCTAssertTrue(backend.finishOriginalStopIDs.isEmpty)
        XCTAssertTrue(backend.occurrenceFinishRequests.isEmpty)
    }

    func testStopThenLateTrackedFailureKeepsTheExistingLinkedRefundAndRequiresConfirmedRetry() throws {
        let fixture = TrackedSessionFixture()
        defer { fixture.close() }
        let backend = TrackedSessionBackend()
        backend.schedule(fixture.alarm) { _ in }
        let original = backend.registrations[fixture.alarm.id]
        backend.deferred = true
        backend.reject = true
        let model = fixture.model(backend: backend)
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        XCTAssertTrue(model.snooze { outcome = $0 })
        XCTAssertEqual(model.dismiss(), .failure(.busy))

        backend.resolve()

        guard case .scheduleFailed = outcome else { return XCTFail("The original failed schedule must refund") }
        let rows = try fixture.ledger().fetchAllChecked()
        let charges = rows.filter { $0.type == .charge }
        let refunds = rows.filter { $0.type == .refund }
        XCTAssertEqual(charges.count, 1)
        XCTAssertEqual(refunds.count, 1)
        XCTAssertEqual(refunds.first?.refundsTransactionID, charges.first?.id)
        XCTAssertEqual(charges.first?.amount, 50)
        XCTAssertEqual(refunds.first?.amount, 50)
        XCTAssertEqual(BalanceService(defaults: fixture.defaults).balance, 2_000)
        XCTAssertEqual(model.snoozeCount, 1, "Attempts retain their existing forward-price meaning")
        XCTAssertNil(model.nextRingDate())
        XCTAssertTrue(WakeEventStore(defaults: fixture.defaults).wakeDays().isEmpty)
        XCTAssertFalse(fixture.model(backend: backend).snooze())
        XCTAssertTrue(backend.cancelled.isEmpty)
        XCTAssertEqual(backend.registrations[fixture.alarm.id], original)

        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        XCTAssertEqual(WakeEventStore(defaults: fixture.defaults).wakeDays().count, 1)
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().map(\.id), rows.map(\.id))
    }

    // MARK: - #1071 civil clock in the ownership check

    func testStaleExplicitClockWithTheSameDateRefusesBeforeAnyTicketOrNativeCall() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let stale = fixture.alarm.with(clockTime: try XCTUnwrap(TimeOfDay(hour: 7, minute: 0)))
        let current = fixture.alarm.with(clockTime: try XCTUnwrap(TimeOfDay(hour: 8, minute: 0)))
        XCTAssertEqual(stale.time, current.time)
        XCTAssertEqual(stale.repeatDays, current.repeatDays)
        XCTAssertEqual(stale.repeatMode, current.repeatMode)
        XCTAssertTrue(fixture.seedRepository.save(current))
        let model = fixture.model(stale)
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(model.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        assertNoFinishSideEffects(fixture)
        XCTAssertEqual(try fixture.repository.fetchChecked(id: fixture.alarm.id)?.clockTime, current.clockTime)
    }

    func testLegacyClockSnapshotRefusesARowThatGainedADifferentExplicitClock() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        XCTAssertNil(fixture.alarm.clockTime, "The fixture row is a legacy Date-only alarm")
        let current = fixture.alarm.with(clockTime: try XCTUnwrap(TimeOfDay(hour: 8, minute: 0)))
        XCTAssertEqual(current.time, fixture.alarm.time)
        XCTAssertTrue(fixture.seedRepository.save(current))
        let model = fixture.model()

        XCTAssertEqual(model.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        assertNoFinishSideEffects(fixture)
    }

    func testFreshExplicitClockFinishesAndPreservesTheSelectedWeeklyClock() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let explicit = fixture.alarm.with(clockTime: try XCTUnwrap(TimeOfDay(hour: 7, minute: 0)))
        XCTAssertTrue(fixture.seedRepository.save(explicit))

        XCTAssertEqual(fixture.model(explicit).dismiss(), .success(.completedNow))

        let request = try XCTUnwrap(fixture.backend.occurrenceFinishRequests.first)
        XCTAssertEqual(fixture.backend.occurrenceFinishRequests.count, 1)
        XCTAssertEqual(request.weekly?.hour, 7)
        XCTAssertEqual(request.weekly?.minute, 0)
        XCTAssertEqual(request.weekly?.mondayFirstDays, [0, 2])
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    // MARK: - An earlier ring's request cannot hold a fresh ring hostage

    func testFreshRingRetiresEarlierRingsTokenRequestAndDismissStopsTheNewRing() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        // Ring N: snoozed, "I'm up", process died before the local commit.
        let stale = try fixture.recoveryTrackedTicket()
        let staleToken = try XCTUnwrap(stale.token)
        fixture.backend.supersedeVerificationResult = .success(())

        // Ring N+1 of the original: no snooze reference.
        let model = fixture.model()

        XCTAssertFalse(model.finishRequested)
        XCTAssertNil(model.snoozeReference)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        let proof = try XCTUnwrap(fixture.backend.supersedeVerificationRequests.first)
        XCTAssertEqual(fixture.backend.supersedeVerificationRequests.count, 1)
        XCTAssertEqual(proof.alarmID, fixture.alarm.id)
        XCTAssertNotNil(proof.expectedDerivedFireDate)
        XCTAssertFalse(proof.allowsUntrackedDerived)
        XCTAssertThrowsError(try fixture.store().resolve(staleToken, alarmID: fixture.alarm.id))
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty, "The earlier ring's wake is not invented")

        XCTAssertEqual(model.dismiss(), .success(.completedNow))

        let request = try XCTUnwrap(fixture.backend.occurrenceFinishRequests.first)
        XCTAssertEqual(fixture.backend.occurrenceFinishRequests.count, 1)
        XCTAssertEqual(request.alarmID, fixture.alarm.id)
        XCTAssertEqual(request.weekly?.hour, 7)
        XCTAssertEqual(request.weekly?.minute, 10)
        XCTAssertEqual(request.weekly?.mondayFirstDays, [0, 2])
        XCTAssertNil(request.expectedDerivedFireDate)
        XCTAssertTrue(request.allowsUntrackedDerived)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wakes.wakeTimes().count, 1)
        XCTAssertEqual(fixture.wallet.balance, 150, "Ring N's charge stays; no refund is invented")
    }

    func testEarlierRingsRequestIsKeptWhenNativeStateCannotProveItsSnoozeCopyGone() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let stale = try fixture.recoveryTrackedTicket()
        // Default double: the old copy may still be registered or the original is not alerting.
        let model = fixture.model()
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertTrue(model.finishRequested)
        XCTAssertFalse(model.snooze())
        XCTAssertEqual(model.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id), stale)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertEqual(fixture.backend.supersedeVerificationRequests.count, 2)
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
        XCTAssertEqual(fixture.wallet.balance, 150)
    }

    func testEarlierRingsRequestWithAnUndueSnoozeCopyIsKeptWithoutANativeProbe() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let stale = try fixture.recoveryTrackedTicket(snoozeFireDate: Date().addingTimeInterval(600))
        fixture.backend.supersedeVerificationResult = .success(())

        let model = fixture.model()

        XCTAssertTrue(model.finishRequested)
        XCTAssertTrue(fixture.backend.supersedeVerificationRequests.isEmpty)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id), stale)
    }

    func testSnoozeIsAvailableOnTheFreshRingAfterRetiringTheEarlierRequest() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let stale = try fixture.recoveryTrackedTicket()
        fixture.backend.supersedeVerificationResult = .success(())
        let model = fixture.model()
        XCTAssertFalse(model.finishRequested)
        XCTAssertTrue(model.canSnooze)

        XCTAssertTrue(model.snooze())

        guard case .token(let token)? = model.snoozeReference else {
            return XCTFail("A fresh ring's snooze must reserve its own session")
        }
        XCTAssertNotEqual(token.sessionID, stale.token?.sessionID)
    }

    // MARK: - The wake belongs to the request, not to a later confirmation

    func testSameRingRetryRecordsTheFirstRequestInstantNotTheLaterConfirmation() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        fixture.backend.occurrenceFinishResult = .failure(.nativeUnconfirmed)
        let model = fixture.model()
        XCTAssertEqual(model.dismiss(), .failure(.nativeUnconfirmed))
        let ticket = try XCTUnwrap(fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        let requested = try XCTUnwrap(ticket.wakeAt)
        XCTAssertGreaterThanOrEqual(requested, model.firingStartedAt)

        fixture.backend.occurrenceFinishResult = .success(())
        XCTAssertEqual(model.dismiss(), .success(.completedNow))

        XCTAssertEqual(fixture.wakes.wakeTimes(), [requested])
    }

    func testRecreatedScreenOnTheSameRingResumesWithTheFirstRequestInstant() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        fixture.backend.occurrenceFinishResult = .failure(.nativeUnconfirmed)
        XCTAssertEqual(fixture.model().dismiss(), .failure(.nativeUnconfirmed))
        let ticket = try XCTUnwrap(fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        let requested = try XCTUnwrap(ticket.wakeAt)

        // Relaunch / re-present while the same ring is still alerting.
        let recreated = fixture.model()
        XCTAssertLessThanOrEqual(requested, recreated.firingStartedAt)
        fixture.backend.occurrenceFinishResult = .success(())
        XCTAssertEqual(recreated.dismiss(), .success(.completedNow))

        XCTAssertEqual(fixture.wakes.wakeTimes(), [requested])
    }

    func testEarlierRingsUntrackedRequestSettledByAFreshRingRecordsTodaysWake() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        // Ring N: "I'm up" on the original yesterday, process died before the commit.
        let yesterday = Date().addingTimeInterval(-86_400)
        let stale = try fixture.store().beginOccurrenceFinish(
            alarmID: fixture.alarm.id, reference: nil, wakeAt: yesterday
        )
        let model = fixture.model()

        XCTAssertEqual(model.dismiss(), .success(.completedNow))

        XCTAssertEqual(try XCTUnwrap(fixture.backend.occurrenceFinishRequests.first).allowsUntrackedDerived, true)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        let times = fixture.wakes.wakeTimes()
        XCTAssertEqual(times.count, 1)
        XCTAssertFalse(times.contains(try XCTUnwrap(stale.wakeAt)))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(times.first), model.firingStartedAt)
        let today = try XCTUnwrap(WakeDayIdentity(date: Date(), calendar: .current).canonicalStoredDay)
        XCTAssertEqual(fixture.wakes.wakeDays(), [today])
    }

    private func assertNoFinishSideEffects(
        _ fixture: OccurrenceVMFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.backend.stoppedIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.backend.supersedeVerificationRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty, file: file, line: line)
    }
}

@MainActor
final class OccurrenceVMFixture {
    let slot: Int
    let defaults: FinishWriteRefusingDefaults
    let alarm: Alarm
    let backend = TestAlarmKitBackend()
    let wallet: BalanceService
    let ledger: TransactionRepository
    let wakes: WakeEventStore
    lazy var scheduler = AlarmScheduler(
        notificationCenter: InertNotificationCenter(), alarmKit: backend, snoozeSessions: store()
    )
    var repository: AlarmRepository { AlarmRepository(defaults: defaults, scheduler: scheduler) }
    var seedRepository: AlarmRepository { AlarmRepository(defaults: defaults, scheduler: NoopScheduler()) }

    init(oneShot: Bool = false) throws {
        let (slot, defaults) = IsolatedDefaultsPool.checkOut(as: FinishWriteRefusingDefaults.self)
        self.slot = slot
        self.defaults = defaults
        let time = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 7, minute: 10
        )))
        alarm = Alarm(time: time, repeatDays: [0, 2], penaltyAmount: 50, repeatMode: oneShot ? .never : .weekly)
        ledger = TransactionRepository(defaults: defaults)
        wallet = BalanceService(
            defaults: defaults, transactionRepository: ledger, notificationCenter: NotificationCenter()
        )
        wakes = WakeEventStore(defaults: defaults)
        XCTAssertTrue(seedRepository.save(alarm))
        XCTAssertTrue(wallet.topUp(amount: 200))
    }

    func model(_ captured: Alarm? = nil) -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: captured ?? alarm, balanceService: wallet, alarmRepository: repository,
            scheduler: scheduler, wakeStore: wakes, ledger: ledger, snoozeSessions: store()
        )
    }
    func store() -> AlarmSnoozeSessionStore { AlarmSnoozeSessionStore(defaults: defaults) }
    func close() { IsolatedDefaultsPool.checkIn(slot) }

    private final class NoopScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}

final class FinishWriteRefusingDefaults: UserDefaults, IsolatedDefaultsSubclass, @unchecked Sendable {
    // Spelled out: an inherited initializer does not witness `IsolatedDefaultsSubclass`.
    override init?(suiteName suitename: String?) { super.init(suiteName: suitename) }
    private let lock = NSLock()
    private var blocked: String?
    var skippedKey: String? {
        get { lock.lock(); defer { lock.unlock() }; return blocked }
        set { lock.lock(); defer { lock.unlock() }; blocked = newValue }
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        guard defaultName != skippedKey else { return }
        super.set(value, forKey: defaultName)
    }
}
