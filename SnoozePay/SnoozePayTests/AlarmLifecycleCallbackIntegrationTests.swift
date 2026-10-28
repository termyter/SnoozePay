import XCTest
@testable import SnoozePay

@MainActor
final class AlarmLifecycleCallbackIntegrationTests: XCTestCase {
    func testRegistrationAndFinishGatesBothRemainBusyThroughLateCleanupAndCallerCompletion() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let civil = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        XCTAssertTrue(fixture.seedRepository.save(civil))
        let backend = LifecycleCallbackBackend(alarmID: civil.id)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: fixture.store())
        let charge = try XCTUnwrap(fixture.wallet.chargeWithReceipt(amount: 50, alarmID: civil.id))
        var ticket: AlarmOccurrenceFinishTicket?
        var completions = 0
        backend.onLate = {
            guard let ticket else { return XCTFail("The original finish ticket must exist during late cleanup") }
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
            XCTAssertEqual(backend.recoveries, 0)
            XCTAssertTrue(backend.finished.isEmpty)
            XCTAssertTrue(backend.verified.isEmpty)
        }
        scheduler.scheduleSnooze(for: civil, snoozeCount: 1) { result in
            completions += 1
            guard case .success = result, let ticket else {
                return XCTFail("Deliver the genuine successful registration")
            }
            XCTAssertEqual(backend.late.count, 1, "Finish-aware cleanup must precede delivery")
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
            XCTAssertEqual(fixture.wallet.balance, 150)
        }
        ticket = try fixture.store().beginOccurrenceFinish(alarmID: civil.id, reference: nil)
        let pending = try XCTUnwrap(ticket)
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        assertBothBusy(scheduler, alarm: civil, ticket: pending)
        XCTAssertEqual(backend.pending.count, 1)

        backend.pending[0](.success(()))
        backend.pending[0](.success(()))

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(backend.late.count, 1)
        XCTAssertEqual(backend.late.first?.weekly?.hour, 6)
        XCTAssertEqual(backend.late.first?.weekly?.minute, 40)
        XCTAssertEqual(backend.recoveries, 0)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: civil.id), pending)
        let rows = try fixture.ledger.fetchAllChecked()
        XCTAssertEqual(rows.filter { $0.type == .charge }.map(\.id), [charge.id])
        XCTAssertTrue(rows.filter { $0.type == .refund }.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertNoThrow(try scheduler.finishOccurrence(for: civil, ticket: pending).get())
        XCTAssertEqual(backend.finished.count, 1)

        var refusedRegistrations = 0
        let attemptRegistration = {
            scheduler.schedule(Alarm()) { result in
                guard case .failure(.recoveryInProgress) = result else {
                    return XCTFail("Recovery must exclude a registration until its commit completes")
                }
                refusedRegistrations += 1
            }
        }
        backend.onRecovery = {
            attemptRegistration()
            self.assertBothBusy(scheduler, alarm: civil, ticket: pending)
        }
        var commits = 0
        try scheduler.recoverCorruptAlarms {
            commits += 1
            XCTAssertTrue(backend.registered.isEmpty)
            attemptRegistration()
            self.assertBothBusy(scheduler, alarm: civil, ticket: pending)
            switch scheduler.recoverCorruptAlarms(commit: {}) {
            case .success:
                XCTFail("Recovery must remain busy through its synchronous commit")
            case .failure(let error):
                XCTAssertEqual(error, .busy)
            }
        }.get()
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(backend.recoveries, 1)
        XCTAssertEqual(refusedRegistrations, 2)
        XCTAssertEqual(backend.registrations, 0)
        XCTAssertEqual(backend.finished.count, 1)
        XCTAssertTrue(backend.verified.isEmpty)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertEqual(fixture.wallet.balance, 150)
    }

    func testGenuineLegacyFailureRefundCompletesWhileBothGatesStayBusyAndDuplicateCallbackCannotRefundAgain() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let civil = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        XCTAssertTrue(fixture.seedRepository.save(civil))
        let backend = LifecycleCallbackBackend(alarmID: civil.id)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: fixture.store())
        let charge = try XCTUnwrap(fixture.wallet.chargeWithReceipt(amount: 50, alarmID: civil.id))
        var ticket: AlarmOccurrenceFinishTicket?
        var completions = 0
        scheduler.scheduleSnooze(for: civil, snoozeCount: 1) { result in
            completions += 1
            guard case .failure(.system(let message)) = result, let ticket else {
                return XCTFail("Native rejection must remain a genuine failure")
            }
            XCTAssertEqual(message, "genuine rejected schedule")
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
            // The existing caller contract reverses this exact real charge.
            XCTAssertTrue(fixture.wallet.refund(amount: charge.amount, refundsTransactionID: charge.id))
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
        }
        ticket = try fixture.store().beginOccurrenceFinish(alarmID: civil.id, reference: nil)
        let pending = try XCTUnwrap(ticket)
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        assertBothBusy(scheduler, alarm: civil, ticket: pending)
        let failure = NSError(domain: "LifecycleRegistration", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "genuine rejected schedule"])

        backend.pending[0](.failure(failure))
        backend.pending[0](.success(()))

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(backend.late.isEmpty)
        XCTAssertEqual(backend.recoveries, 0)
        let rows = try fixture.ledger.fetchAllChecked()
        let refunds = rows.filter { $0.type == .refund }
        XCTAssertEqual(rows.filter { $0.type == .charge }.map(\.id), [charge.id])
        XCTAssertEqual(refunds.count, 1)
        XCTAssertEqual(refunds.first?.refundsTransactionID, charge.id)
        XCTAssertEqual(refunds.first?.amount, charge.amount)
        XCTAssertEqual(fixture.wallet.balance, 200)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: civil.id), pending)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertNoThrow(try scheduler.verifyPendingOccurrenceFinish(currentAlarm: civil, ticket: pending).get())
        XCTAssertEqual(backend.verified.count, 1)
        XCTAssertNoThrow(try scheduler.recoverCorruptAlarms {}.get())
        XCTAssertEqual(backend.recoveries, 1)
    }

    func testTrackedReceiptSettlementKeepsScopedFinishAndGlobalRecoveryBusyUntilItsCallerReturns() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let civil = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        XCTAssertTrue(fixture.seedRepository.save(civil))
        let sessions = fixture.store()
        let token = try sessions.reserve(alarmID: civil.id, sessionID: nil, expectedCount: 0)
        let charge = try XCTUnwrap(fixture.wallet.chargeWithReceipt(amount: 50, alarmID: civil.id))
        try sessions.recordCharge(token, alarmID: civil.id)
        defer { sessions.operationEnded(token) }
        let backend = LifecycleCallbackBackend(alarmID: civil.id)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: sessions)
        var ticket: AlarmOccurrenceFinishTicket?
        var completions = 0
        scheduler.scheduleTrackedSnooze(for: civil, token: token) { result in
            completions += 1
            guard case .success(let receipt) = result, let ticket else {
                return XCTFail("Expected the genuine registered receipt and pending finish")
            }
            do {
                try sessions.complete(token, alarmID: civil.id, receipt: receipt)
                // Prove the session's running gate has ended. Registration must
                // independently retain ownership until this caller returns.
                XCTAssertEqual(try sessions.validateOccurrenceFinish(ticket), receipt)
            } catch { return XCTFail("Receipt settlement must succeed: \(error)") }
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
        }
        ticket = try sessions.beginOccurrenceFinish(alarmID: civil.id, reference: .token(token))
        let pending = try XCTUnwrap(ticket)
        assertBothBusy(scheduler, alarm: civil, ticket: pending)
        let requested = try XCTUnwrap(backend.trackedDates.first)
        let receipt = AlarmSnoozeReceipt(systemID: AlarmKitScheduler.snoozeID(for: civil.id),
                                        fireDate: requested.addingTimeInterval(17))
        XCTAssertEqual(backend.pendingTracked.count, 1)

        backend.pendingTracked[0](.success(receipt))
        backend.pendingTracked[0](.success(receipt))

        XCTAssertEqual(completions, 1)
        XCTAssertNoThrow(try scheduler.verifyPendingOccurrenceFinish(currentAlarm: civil, ticket: pending).get())
        XCTAssertNoThrow(try scheduler.finishOccurrence(for: civil, ticket: pending).get())
        XCTAssertEqual(backend.verified.last?.expectedDerivedFireDate, receipt.fireDate)
        XCTAssertEqual(backend.finished.last?.expectedDerivedFireDate, receipt.fireDate)
        XCTAssertEqual(backend.verified.last?.weekly?.hour, 6)
        XCTAssertEqual(backend.finished.last?.weekly?.minute, 40)
        XCTAssertNoThrow(try scheduler.recoverCorruptAlarms {}.get())
        XCTAssertEqual(backend.recoveries, 1)
        XCTAssertEqual(try sessions.pendingOccurrenceFinish(alarmID: civil.id), pending)
        let rows = try fixture.ledger.fetchAllChecked()
        XCTAssertEqual(rows.filter { $0.type == .charge }.map(\.id), [charge.id])
        XCTAssertTrue(rows.filter { $0.type == .refund }.isEmpty)
        XCTAssertEqual(fixture.wallet.balance, 150)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
    }

    func testEarlyPendingFinishRejectionRetainsBothGatesThroughTheGenuineLinkedRefundCaller() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let civil = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        XCTAssertTrue(fixture.seedRepository.save(civil))
        let ticket = try fixture.store().beginOccurrenceFinish(alarmID: civil.id, reference: nil)
        let sessions = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let charge = try XCTUnwrap(fixture.wallet.chargeWithReceipt(amount: 50, alarmID: civil.id))
        let backend = LifecycleCallbackBackend(alarmID: civil.id)
        let inventory = backend.registered
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: fixture.store())
        var completions = 0

        scheduler.scheduleSnooze(for: civil, snoozeCount: 1) { result in
            completions += 1
            guard case .failure(.system(let message)) = result else {
                return XCTFail("An existing finish must reject before any physical registration")
            }
            XCTAssertEqual(message, AlarmSnoozeContextError.finished.localizedDescription)
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
            XCTAssertTrue(fixture.wallet.refund(amount: charge.amount, refundsTransactionID: charge.id))
            self.assertBothBusy(scheduler, alarm: civil, ticket: ticket)
        }

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(backend.pending.isEmpty, "There is no backend callback or legacy operation in this phase")
        XCTAssertTrue(backend.stopped.isEmpty)
        XCTAssertTrue(backend.cancelled.isEmpty)
        XCTAssertTrue(backend.originalCancels.isEmpty)
        XCTAssertTrue(backend.late.isEmpty)
        XCTAssertTrue(backend.finished.isEmpty)
        XCTAssertTrue(backend.verified.isEmpty)
        XCTAssertEqual(backend.registered, inventory)
        XCTAssertEqual(backend.recoveries, 0)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessions)
        let rows = try fixture.ledger.fetchAllChecked()
        XCTAssertEqual(rows.filter { $0.type == .charge }.map(\.id), [charge.id])
        XCTAssertEqual(rows.filter { $0.type == .refund }.map(\.refundsTransactionID), [charge.id])
        XCTAssertEqual(fixture.wallet.balance, 200)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertNoThrow(try scheduler.verifyPendingOccurrenceFinish(currentAlarm: civil, ticket: ticket).get())
        XCTAssertNoThrow(try scheduler.recoverCorruptAlarms {}.get())
        XCTAssertEqual(backend.recoveries, 1)
    }

    func testUnrelatedRegistrationBlocksOnlyGlobalRecoveryAndCannotBorrowAnotherAlarmsScopedTicket() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let civil = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        XCTAssertTrue(fixture.seedRepository.save(civil))
        let ticket = try fixture.recoveryTrackedTicket()
        let other = Alarm(clockTime: TimeOfDay(hour: 9, minute: 0), name: "Other registration owner")
        let backend = LifecycleCallbackBackend(alarmID: civil.id)
        backend.holdOriginalRegistration = true
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend,
                                       snoozeSessions: fixture.store())
        var completed = 0
        scheduler.schedule(other) { result in
            guard case .success = result else { return XCTFail("Other registration should succeed") }
            completed += 1
        }
        XCTAssertEqual(backend.pendingOriginal.count, 1)
        let sessionBytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertThrowsError(try scheduler.recoverCorruptAlarms {}.get()) {
            XCTAssertEqual($0 as? AlarmRecoveryError, .busy)
        }
        XCTAssertNoThrow(try scheduler.finishOccurrence(for: civil, ticket: ticket).get())
        XCTAssertNoThrow(try scheduler.verifyPendingOccurrenceFinish(currentAlarm: civil, ticket: ticket).get())
        XCTAssertThrowsError(try scheduler.finishOccurrence(for: other, ticket: ticket).get()) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, .ownershipUnavailable)
        }
        XCTAssertThrowsError(try scheduler.verifyPendingOccurrenceFinish(currentAlarm: other, ticket: ticket).get()) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, .ownershipUnavailable)
        }

        XCTAssertEqual(completed, 0)
        XCTAssertEqual(backend.finished.map(\.alarmID), [civil.id])
        XCTAssertEqual(backend.verified.map(\.alarmID), [civil.id])
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessionBytes)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: civil.id), ticket)
        backend.pendingOriginal[0](.success(()))
        XCTAssertEqual(completed, 1)
        XCTAssertNoThrow(try scheduler.recoverCorruptAlarms {}.get())
        XCTAssertEqual(backend.recoveries, 1)
    }

    private func assertBothBusy(
        _ scheduler: AlarmScheduler, alarm: Alarm, ticket: AlarmOccurrenceFinishTicket,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try scheduler.recoverCorruptAlarms {}.get(), file: file, line: line) {
            XCTAssertEqual($0 as? AlarmRecoveryError, .busy, file: file, line: line)
        }
        XCTAssertThrowsError(try scheduler.finishOccurrence(for: alarm, ticket: ticket).get(), file: file, line: line) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, .busy, file: file, line: line)
        }
        XCTAssertThrowsError(try scheduler.verifyPendingOccurrenceFinish(currentAlarm: alarm, ticket: ticket).get(),
                             file: file, line: line) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, .busy, file: file, line: line)
        }
    }
}

/// Deterministic registration/caller seam. Native inventory correctness has
/// separate combined tests using the real adapter and injected full readers.
@MainActor
private final class LifecycleCallbackBackend: AlarmKitScheduling {
    var isAuthorized = true
    var onLate: (() -> Void)?
    var onRecovery: (() -> Void)?
    var holdOriginalRegistration = false
    var pending: [(Result<Void, Error>) -> Void] = []
    var pendingOriginal: [(Result<Void, Error>) -> Void] = []
    var pendingTracked: [(Result<AlarmSnoozeReceipt, Error>) -> Void] = []
    private(set) var trackedDates: [Date] = []
    private(set) var registered: Set<UUID>
    private(set) var registrations = 0
    private(set) var recoveries = 0
    private(set) var late: [AlarmOccurrenceFinishRequest] = []
    private(set) var finished: [AlarmOccurrenceFinishRequest] = []
    private(set) var verified: [AlarmOccurrenceFinishRequest] = []
    private(set) var stopped: [UUID] = []
    private(set) var cancelled: [UUID] = []
    private(set) var originalCancels: [UUID] = []

    init(alarmID: UUID) { registered = [alarmID, AlarmKitScheduler.snoozeID(for: alarmID), UUID()] }
    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(isAuthorized) }
    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
        registrations += 1
        registered.insert(alarm.id)
        if holdOriginalRegistration { pendingOriginal.append(completion) } else { completion(.success(())) }
    }
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        pending.append(completion)
    }
    // swiftlint:disable:next function_parameter_count
    func scheduleTrackedSnooze(
        _ alarm: Alarm, fireDate: Date, token: AlarmSnoozeToken, attemptCount: Int,
        isCurrent: @escaping () -> Bool, completion: @escaping (Result<AlarmSnoozeReceipt, Error>) -> Void
    ) {
        guard isCurrent() else { return completion(.failure(AlarmSnoozeContextError.finished)) }
        trackedDates.append(fireDate)
        pendingTracked.append(completion)
    }
    func cancelOriginal(_ alarmID: UUID) {
        originalCancels.append(alarmID)
        registered.remove(alarmID)
    }
    func cancel(_ alarmID: UUID) {
        cancelled.append(alarmID)
        registered.remove(alarmID)
    }
    func stop(_ alarmID: UUID) { stopped.append(alarmID) }
    func finishOccurrence(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        finished.append(request)
        return .success(())
    }
    func verifyFinishedOccurrence(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        verified.append(request)
        return .success(())
    }
    func cleanUpLateSnooze(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        late.append(request)
        onLate?()
        registered.remove(AlarmKitScheduler.snoozeID(for: request.alarmID))
        return .success(())
    }
    func clearRegisteredAlarmsForRecovery() -> Result<Void, AlarmRecoveryError> {
        recoveries += 1
        onRecovery?()
        registered.removeAll()
        return .success(())
    }
}
