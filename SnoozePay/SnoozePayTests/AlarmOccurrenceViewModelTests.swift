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
}

@MainActor
final class OccurrenceVMFixture {
    let suite: String
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
        let suite = "OccurrenceVM-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(FinishWriteRefusingDefaults(suiteName: suite))
        self.suite = suite
        self.defaults = defaults
        let time = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 7, minute: 10
        )))
        alarm = Alarm(time: time, repeatDays: [0, 2], penaltyAmount: 50, repeatMode: oneShot ? .never : .weekly)
        ledger = TransactionRepository(defaults: defaults)
        wallet = BalanceService(defaults: defaults, transactionRepository: ledger)
        wakes = WakeEventStore(defaults: defaults)
        XCTAssertTrue(seedRepository.save(alarm))
        XCTAssertTrue(wallet.topUp(amount: 200))
    }

    func model() -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: alarm, balanceService: wallet, alarmRepository: repository,
            scheduler: scheduler, wakeStore: wakes, ledger: ledger, snoozeSessions: store()
        )
    }
    func store() -> AlarmSnoozeSessionStore { AlarmSnoozeSessionStore(defaults: defaults) }
    func close() { defaults.removePersistentDomain(forName: suite) }

    private final class NoopScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}

final class FinishWriteRefusingDefaults: UserDefaults, @unchecked Sendable {
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
