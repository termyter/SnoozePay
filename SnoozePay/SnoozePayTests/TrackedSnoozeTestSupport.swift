import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class TrackedSessionBackend: AlarmKitScheduling {
    enum Rejection: Error { case schedule }
    var isAuthorized = true
    var deferred = false
    var reject = false
    var unconfirmedRegistration = false
    var confirmsCancellation = true
    var alertingAlarmIDs: Set<UUID>? = []
    private(set) var attemptCounts: [Int] = []
    private(set) var cancelledSnoozes: [UUID] = []
    private(set) var tokens: [AlarmSnoozeToken] = []
    private(set) var receipts: [AlarmSnoozeReceipt] = []
    private(set) var requestedDates: [Date] = []
    private(set) var cancelled: [UUID] = []
    private(set) var registrations: [UUID: Date] = [:]
    private var pending: (() -> Void)?
    var occurrenceFinishResult: Result<Void, AlarmOccurrenceFinishError> = .success(())
    private(set) var occurrenceFinishRequests: [AlarmOccurrenceFinishRequest] = []
    private(set) var lateSnoozeCleanupRequests: [AlarmOccurrenceFinishRequest] = []
    private(set) var finishOriginalStopIDs: [UUID] = []

    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(isAuthorized) }
    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) {
        registrations[alarm.id] = alarm.time
        completion(.success(()))
    }
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(AlarmSnoozeContextError.unsupportedBackend))
    }
    func scheduleTrackedSnooze(
        _ alarm: Alarm, fireDate: Date, token: AlarmSnoozeToken, attemptCount: Int,
        isCurrent: @escaping () -> Bool,
        completion: @escaping (Result<AlarmSnoozeReceipt, Error>) -> Void
    ) {
        guard isCurrent() else { completion(.failure(AlarmSnoozeContextError.finished)); return }
        attemptCounts.append(attemptCount)
        tokens.append(token)
        requestedDates.append(fireDate)
        let register = { [self] in
            guard !reject else { completion(.failure(Rejection.schedule)); return }
            let id = AlarmKitScheduler.snoozeID(for: alarm.id)
            // Deliberately differs from the requested date: callers must use the returned registration.
            registrations[id] = fireDate.addingTimeInterval(17)
            guard let actual = registrations[id] else { XCTFail("Fake registration missing"); return }
            let receipt = AlarmSnoozeReceipt(systemID: id, fireDate: actual)
            receipts.append(receipt)
            if unconfirmedRegistration {
                completion(.failure(AlarmSnoozeContextError.unconfirmedRegistration))
            } else { completion(.success(receipt)) }
        }
        if deferred { pending = register } else { register() }
    }
    func resolve() { let operation = pending; pending = nil; operation?() }
    func cancelOriginal(_ alarmID: UUID) { registrations[alarmID] = nil }
    func cancelTrackedSnooze(_ alarmID: UUID) -> Bool {
        cancelledSnoozes.append(alarmID)
        guard confirmsCancellation else { return false }
        registrations[AlarmKitScheduler.snoozeID(for: alarmID)] = nil
        return true
    }
    func cancel(_ alarmID: UUID) {
        cancelled.append(alarmID)
        registrations[alarmID] = nil
        registrations[AlarmKitScheduler.snoozeID(for: alarmID)] = nil
    }
    func stop(_ alarmID: UUID) {}

    /// A configured consumer outcome; this fake's Date dictionary models snoozes, not native state.
    func finishOccurrence(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        occurrenceFinishRequests.append(request)
        if case .success = occurrenceFinishResult {
            let derivedID = AlarmKitScheduler.snoozeID(for: request.alarmID)
            if let date = registrations[derivedID] {
                guard request.expectedDerivedFireDate == date || request.allowsUntrackedDerived else {
                    return .failure(.ownershipUnavailable)
                }
                guard confirmsCancellation else { return .failure(.nativeUnconfirmed) }
            }
            registrations[derivedID] = nil
            if request.weekly == nil { registrations[request.alarmID] = nil }
        }
        return occurrenceFinishResult
    }

    func cleanUpLateSnooze(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        lateSnoozeCleanupRequests.append(request)
        guard confirmsCancellation else { return .failure(.nativeUnconfirmed) }
        let derivedID = AlarmKitScheduler.snoozeID(for: request.alarmID)
        if let date = registrations[derivedID],
           request.expectedDerivedFireDate != date && !request.allowsUntrackedDerived {
            return .failure(.ownershipUnavailable)
        }
        registrations[derivedID] = nil
        return .success(())
    }

    func stopOriginalForFinish(_ alarmID: UUID) -> Result<Void, AlarmOccurrenceFinishError> {
        finishOriginalStopIDs.append(alarmID)
        return .success(())
    }
}

@MainActor
final class TrackedSessionFixture {
    let suite = "TrackedSession-\(UUID().uuidString)"
    let defaults: UserDefaults
    let alarm: Alarm

    init(alarm: Alarm? = nil) {
        self.alarm = alarm ?? Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6], snoozeMinutes: 5,
                                    penaltyAmount: 50, progressiveScale: true, enabled: true)
        defaults = UserDefaults(suiteName: suite)!
        let repository = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
        XCTAssertTrue(repository.save(self.alarm))
        XCTAssertTrue(BalanceService(defaults: defaults).topUp(amount: 2_000))
    }
    func close() { defaults.removePersistentDomain(forName: suite) }
    func store() -> AlarmSnoozeSessionStore { AlarmSnoozeSessionStore(defaults: defaults) }
    func ledger() -> TransactionRepository { TransactionRepository(defaults: defaults) }
    func scheduler(_ backend: AlarmKitScheduling) -> AlarmScheduler {
        AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend, snoozeSessions: store())
    }
    func model(backend: AlarmKitScheduling, reference: AlarmSnoozeReference? = nil, count: Int = 0) -> AlarmFiringViewModel {
        let model = AlarmFiringViewModel(
            alarm: alarm, snoozeCount: count,
            balanceService: BalanceService(defaults: defaults, transactionRepository: ledger()),
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler(backend)),
            scheduler: scheduler(backend), wakeStore: WakeEventStore(defaults: defaults), ledger: ledger(),
            snoozeSessions: store()
        )
        if let reference { model.bindSnoozeSession(reference, store: store()) }
        return model
    }
    func presenter(host: UIViewController, backend: AlarmKitScheduling) -> AlarmFiringPresenter {
        let presenter = AlarmFiringPresenter(
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler(backend))
        )
        presenter.snoozeSessions = store()
        presenter.locateHost = { .success(host) }
        presenter.makeFiringScreen = { [self] _, count in
            ReadBackFiringScreen(viewModel: model(backend: backend, count: count))
        }
        return presenter
    }
}

@MainActor
final class TrackedSessionHost: UIViewController {
    private(set) var screens: [ReadBackFiringScreen] = []
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        guard let screen = viewControllerToPresent as? ReadBackFiringScreen else { XCTFail("Unexpected screen"); return }
        screens.append(screen)
        screen.wiredPresenter = self
    }
}
