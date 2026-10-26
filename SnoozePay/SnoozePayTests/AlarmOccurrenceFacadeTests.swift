import XCTest
import UserNotifications
@testable import SnoozePay

@MainActor
final class AlarmOccurrenceFacadeTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: AlarmSnoozeSessionStore!
    private var backend: OccurrenceFacadeBackend!
    private var scheduler: AlarmScheduler!

    override func setUp() {
        super.setUp()
        suite = "test.occurrence.facade.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = AlarmSnoozeSessionStore(defaults: defaults)
        backend = OccurrenceFacadeBackend()
        scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(),
                                   alarmKit: backend, snoozeSessions: store)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testValidatedUntrackedTicketPreservesWeeklyClockAndDays() throws {
        let alarm = weeklyAlarm()
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
        let request = try XCTUnwrap(backend.finished.first)
        XCTAssertEqual(request.alarmID, alarm.id)
        XCTAssertEqual(request.weekly, NativeOccurrenceSnapshot.Weekly(hour: 7, minute: 15, mondayFirstDays: [0, 6]))
        XCTAssertNil(request.expectedDerivedFireDate)
        XCTAssertTrue(request.allowsUntrackedDerived)
        XCTAssertTrue(backend.cancelled.isEmpty)
    }

    func testDisabledNeverAndExplicitlyDeletedAlarmExpectBothIDsAbsent() throws {
        let alarm = weeklyAlarm()
        for (candidate, preserve) in [(alarm.with(enabled: false), true),
                                      (alarm.with(repeatMode: .never), true), (alarm, false)] {
            let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
            assertSuccess(scheduler.finishOccurrence(for: candidate, ticket: ticket, preserveWeekly: preserve))
            XCTAssertNil(backend.finished.last?.weekly)
        }
    }

    func testTrackedTicketUsesOnlyItsExactStoredReceipt() throws {
        let alarm = weeklyAlarm()
        let (ticket, receipt) = try trackedTicket(alarm)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
        XCTAssertEqual(backend.finished.last?.expectedDerivedFireDate, receipt.fireDate)
        XCTAssertEqual(backend.finished.last?.allowsUntrackedDerived, false)
        assertSuccess(scheduler.cleanUpLateSnooze(for: alarm, ticket: ticket, receipt: receipt))
        XCTAssertEqual(backend.late.last?.expectedDerivedFireDate, receipt.fireDate)
        XCTAssertTrue(backend.cancelled.isEmpty)
    }

    func testWrongSuppliedReceiptCannotReachTheBackend() throws {
        let alarm = weeklyAlarm()
        let (ticket, receipt) = try trackedTicket(alarm)
        let wrong = AlarmSnoozeReceipt(systemID: receipt.systemID, fireDate: receipt.fireDate.addingTimeInterval(1))
        assertFailure(scheduler.cleanUpLateSnooze(for: alarm, ticket: ticket, receipt: wrong), .ownershipUnavailable)
        XCTAssertTrue(backend.late.isEmpty)
    }

    func testWrongStoredSystemIDCannotAuthorizeDerivedCleanup() throws {
        let alarm = weeklyAlarm()
        let token = try store.reserve(alarmID: alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: alarm.id)
        let receipt = AlarmSnoozeReceipt(systemID: UUID(), fireDate: Date(timeIntervalSince1970: 1_800_000_037))
        try store.complete(token, alarmID: alarm.id, receipt: receipt)
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: .token(token))
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: ticket), .ownershipUnavailable)
        assertFailure(scheduler.cleanUpLateSnooze(for: alarm, ticket: ticket, receipt: receipt), .ownershipUnavailable)
        XCTAssertTrue(backend.finished.isEmpty)
        XCTAssertTrue(backend.late.isEmpty)
    }

    func testWrongAlarmOrForgedTicketCannotReachTheBackend() throws {
        let alarm = weeklyAlarm()
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        assertFailure(scheduler.finishOccurrence(for: Alarm(), ticket: ticket), .ownershipUnavailable)
        let forged = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: alarm.id, token: nil)
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: forged), .ownershipUnavailable)
        XCTAssertTrue(backend.finished.isEmpty)
    }

    func testCorruptStoreRefusesFinishAndAnotherLegacyRegistration() throws {
        let alarm = weeklyAlarm()
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        let corrupt = Data("corrupt finish ownership".utf8)
        defaults.set(corrupt, forKey: AlarmSnoozeSessionStore.key)
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: ticket), .sessionUnavailable)
        var failed = false
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { if case .failure = $0 { failed = true } }
        XCTAssertTrue(failed)
        XCTAssertTrue(backend.finished.isEmpty)
        XCTAssertTrue(backend.pending.isEmpty)
        XCTAssertTrue(backend.stopped.isEmpty)
        XCTAssertEqual(defaults.data(forKey: AlarmSnoozeSessionStore.key), corrupt)
    }

    func testPendingTicketRefusesANewLegacyRegistrationBeforeStop() throws {
        let alarm = weeklyAlarm()
        _ = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        var failures = 0
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { if case .failure = $0 { failures += 1 } }
        XCTAssertEqual(failures, 1)
        XCTAssertTrue(backend.pending.isEmpty)
        XCTAssertTrue(backend.stopped.isEmpty)
    }

    func testOutstandingLegacyRegistrationStaysBusyThroughCleanupAndCompletion() throws {
        let alarm = weeklyAlarm()
        var ticket: AlarmOccurrenceFinishTicket?
        var results = 0
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { result in
            guard case .success = result, let ticket else { return XCTFail("Expected physical success") }
            results += 1
            XCTAssertEqual(self.backend.late.count, 1, "cleanup precedes genuine completion")
            self.assertFailure(self.scheduler.finishOccurrence(for: alarm, ticket: ticket), .busy)
        }
        ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        let activeTicket = try XCTUnwrap(ticket)
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: activeTicket), .busy)
        backend.pending[0](.success(()))
        XCTAssertEqual(results, 1)
        XCTAssertEqual(backend.late.count, 1)
        XCTAssertTrue(backend.cancelled.isEmpty)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: activeTicket))
        XCTAssertEqual(backend.finished.count, 1)
    }

    func testFailedLateCleanupDoesNotInventAScheduleFailureOrPermanentlyBlockRetry() throws {
        let alarm = weeklyAlarm()
        backend.lateResult = .failure(.nativeUnconfirmed)
        var successes = 0
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { if case .success = $0 { successes += 1 } }
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        backend.pending[0](.success(()))
        XCTAssertEqual(successes, 1, "finish must not create a voluntary refund")
        XCTAssertEqual(try store.pendingOccurrenceFinish(alarmID: alarm.id), ticket)
        XCTAssertTrue(backend.cancelled.isEmpty)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
    }

    func testNativeLegacyFailureIsDeliveredUnchangedAndDuplicateCompletionIsIgnored() throws {
        let alarm = weeklyAlarm()
        var messages: [String] = []
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { result in
            if case .failure(.system(let message)) = result { messages.append(message) }
        }
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        let error = NSError(domain: "NativeFailure", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "real native failure"])
        backend.pending[0](.failure(error))
        backend.pending[0](.success(()))
        XCTAssertEqual(messages, ["real native failure"])
        XCTAssertTrue(backend.late.isEmpty)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
    }

    func testReentrantLegacyCompletionIsClaimedOnceWhileFinishRemainsBusy() throws {
        let alarm = weeklyAlarm()
        var completions = 0
        scheduler.scheduleSnooze(for: alarm, snoozeCount: 1) { _ in
            completions += 1
            if completions == 1 { self.backend.pending[0](.success(())) }
        }
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        backend.pending[0](.success(()))
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(backend.late.count, 1)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
    }

    func testUnfinishedPhysicalTrackedOperationRefusesNativeFinish() throws {
        let alarm = weeklyAlarm()
        let token = try store.reserve(alarmID: alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: alarm.id)
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: .token(token))
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: ticket), .busy)
        XCTAssertTrue(backend.finished.isEmpty)
        try store.complete(token, alarmID: alarm.id, receipt: nil)
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
        XCTAssertEqual(backend.finished.last?.allowsUntrackedDerived, false)
        XCTAssertNil(backend.finished.last?.expectedDerivedFireDate)
    }

    func testIsolatedNilStoreSupportsOnlyUntrackedTickets() {
        let alarm = weeklyAlarm()
        let isolated = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        let untracked = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: alarm.id, token: nil)
        assertSuccess(isolated.finishOccurrence(for: alarm, ticket: untracked))
        let tracked = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: alarm.id,
                                                 token: .init(sessionID: UUID(), attemptID: UUID()))
        assertFailure(isolated.finishOccurrence(for: alarm, ticket: tracked), .ownershipUnavailable)
        XCTAssertEqual(backend.finished.count, 1)
    }

    func testUnavailableBackendAndBestEffortStopCannotPretendToFinish() {
        let alarm = weeklyAlarm()
        let isolated = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        let ticket = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: alarm.id, token: nil)
        assertFailure(isolated.finishOccurrence(for: alarm, ticket: ticket), .unsupported)
        scheduler.stopOriginalAfterUnverifiedFinish(alarm.id)
        XCTAssertEqual(backend.originalStops, [alarm.id])
        XCTAssertTrue(backend.stopped.isEmpty)
        XCTAssertTrue(backend.cancelled.isEmpty)
        XCTAssertTrue(backend.finished.isEmpty)
    }

    func testBackendConfirmationFailureIsPreservedAndDoesNotCommitTicket() throws {
        let alarm = weeklyAlarm()
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        backend.finishResult = .failure(.nativeUnconfirmed)
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: ticket), .nativeUnconfirmed)
        XCTAssertEqual(try store.pendingOccurrenceFinish(alarmID: alarm.id), ticket)
    }

    func testOnlyVerifiedWeeklyFinishRemovesOwnedLegacyPendingAndDeliveredNotifications() throws {
        let alarm = weeklyAlarm()
        let unrelatedID = UUID()
        let owned = ["alarm_\(alarm.id)_day0", "alarm_\(alarm.id)_day6", "alarm_\(alarm.id)_once",
                     "alarm_\(alarm.id)_old_burst91", "snooze_\(alarm.id)", "snooze_\(alarm.id)_burst37"]
        let unrelated = ["alarm_\(unrelatedID)_once", "snooze_\(unrelatedID)_burst37",
                         "snooze_\(alarm.id)unrelated", "calendar_event"]
        let center = OccurrenceLegacyNotifications(identifiers: owned + unrelated)
        let scheduler = AlarmScheduler(notificationCenter: center, alarmKit: backend, snoozeSessions: store)
        let ticket = try store.beginOccurrenceFinish(alarmID: alarm.id, reference: nil)
        let forged = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: alarm.id, token: nil)
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: forged), .ownershipUnavailable)
        XCTAssertTrue(backend.finished.isEmpty)
        backend.finishResult = .failure(.nativeUnconfirmed)
        assertFailure(scheduler.finishOccurrence(for: alarm, ticket: ticket), .nativeUnconfirmed)
        XCTAssertEqual(center.pendingIDs, Set(owned + unrelated))
        XCTAssertEqual(center.deliveredIDs, Set(owned + unrelated))
        XCTAssertEqual(center.pendingReads, 0)
        XCTAssertEqual(center.deliveredReads, 0)

        backend.finishResult = .success(())
        assertSuccess(scheduler.finishOccurrence(for: alarm, ticket: ticket))
        XCTAssertEqual(backend.finished.last?.weekly,
                       NativeOccurrenceSnapshot.Weekly(hour: 7, minute: 15, mondayFirstDays: [0, 6]))
        XCTAssertEqual(center.pendingReads, 1)
        XCTAssertEqual(center.deliveredReads, 1)
        XCTAssertTrue(center.pendingIDs.contains("alarm_\(alarm.id)_old_burst91"))
        XCTAssertTrue(center.deliveredIDs.contains("snooze_\(alarm.id)_burst37"))
        center.deliverInventoryReads()
        XCTAssertEqual(center.pendingIDs, Set(unrelated))
        XCTAssertEqual(center.deliveredIDs, Set(unrelated))
        XCTAssertTrue(backend.cancelled.isEmpty, "Occurrence finish must preserve the weekly native original")
        XCTAssertTrue(backend.originalCancels.isEmpty)
    }

    func testOldBackendDefaultsCannotClaimOccurrenceSupport() {
        let alarm = weeklyAlarm()
        let request = AlarmOccurrenceFinishRequest(alarmID: alarm.id, weekly: nil,
                                                   expectedDerivedFireDate: nil, allowsUntrackedDerived: true)
        let oldBackend = UnsupportedOccurrenceBackend()
        assertFailure(oldBackend.finishOccurrence(request), .unsupported)
        assertFailure(oldBackend.cleanUpLateSnooze(request), .unsupported)
        assertFailure(oldBackend.stopOriginalForFinish(alarm.id), .unsupported)
    }

    private func trackedTicket(_ alarm: Alarm) throws -> (AlarmOccurrenceFinishTicket, AlarmSnoozeReceipt) {
        let token = try store.reserve(alarmID: alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: alarm.id)
        let receipt = AlarmSnoozeReceipt(systemID: AlarmKitScheduler.snoozeID(for: alarm.id),
                                         fireDate: Date(timeIntervalSince1970: 1_800_000_037))
        try store.complete(token, alarmID: alarm.id, receipt: receipt)
        return (try store.beginOccurrenceFinish(alarmID: alarm.id, reference: .token(token)), receipt)
    }

    private func weeklyAlarm() -> Alarm {
        let time = Calendar.current.date(bySettingHour: 7, minute: 15, second: 0,
                                         of: Date(timeIntervalSince1970: 1_800_000_000))!
        return Alarm(time: time, repeatDays: [0, 6], repeatMode: .weekly)
    }

    private func assertSuccess(_ result: Result<Void, AlarmOccurrenceFinishError>,
                               file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result { XCTFail("Unexpected finish failure: \(error)", file: file, line: line) }
    }

    private func assertFailure(
        _ result: Result<Void, AlarmOccurrenceFinishError>, _ expected: AlarmOccurrenceFinishError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .failure(let error) = result else { return XCTFail("Expected failure", file: file, line: line) }
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}

@MainActor
private final class OccurrenceFacadeBackend: AlarmKitScheduling {
    var isAuthorized = true
    var finished: [AlarmOccurrenceFinishRequest] = []
    var late: [AlarmOccurrenceFinishRequest] = []
    var cancelled: [UUID] = []
    var originalCancels: [UUID] = []
    var stopped: [UUID] = []
    var originalStops: [UUID] = []
    var pending: [(Result<Void, Error>) -> Void] = []
    var finishResult: Result<Void, AlarmOccurrenceFinishError> = .success(())
    var lateResult: Result<Void, AlarmOccurrenceFinishError> = .success(())

    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(isAuthorized) }
    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) { completion(.success(())) }
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        pending.append(completion)
    }
    func cancelOriginal(_ alarmID: UUID) { originalCancels.append(alarmID) }
    func cancel(_ alarmID: UUID) { cancelled.append(alarmID) }
    func stop(_ alarmID: UUID) { stopped.append(alarmID) }
    func finishOccurrence(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        finished.append(request)
        return finishResult
    }
    func cleanUpLateSnooze(_ request: AlarmOccurrenceFinishRequest) -> Result<Void, AlarmOccurrenceFinishError> {
        late.append(request)
        return lateResult
    }
    func stopOriginalForFinish(_ alarmID: UUID) -> Result<Void, AlarmOccurrenceFinishError> {
        originalStops.append(alarmID)
        return .failure(.nativeUnconfirmed)
    }
}

@MainActor
private final class OccurrenceLegacyNotifications: NotificationScheduling {
    private var pending: [UNNotificationRequest]
    private(set) var deliveredIDs: Set<String>
    private(set) var pendingReads = 0
    private(set) var deliveredReads = 0
    private var pendingCompletion: (@Sendable ([UNNotificationRequest]) -> Void)?
    private var deliveredCompletion: (@Sendable ([String]) -> Void)?
    var pendingIDs: Set<String> { Set(pending.map(\.identifier)) }
    init(identifiers: [String]) {
        let content = UNMutableNotificationContent()
        pending = identifiers.map { UNNotificationRequest(identifier: $0, content: content, trigger: nil) }
        deliveredIDs = Set(identifiers)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void
    ) {
        pendingReads += 1
        pendingCompletion = completionHandler
    }
    func getDeliveredNotificationIdentifiers(completionHandler: @escaping @Sendable ([String]) -> Void) {
        deliveredReads += 1
        deliveredCompletion = completionHandler
    }
    func deliverInventoryReads() {
        let pendingCallback = pendingCompletion
        let deliveredCallback = deliveredCompletion
        pendingCompletion = nil
        deliveredCompletion = nil
        pendingCallback?(pending)
        deliveredCallback?(Array(deliveredIDs))
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        let removed = Set(identifiers)
        pending.removeAll { removed.contains($0.identifier) }
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        deliveredIDs.subtract(identifiers)
    }
    func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void) {
        XCTFail("The framework-free fixture must use the delivered identifier projection")
        completionHandler([])
    }
    func add(_ request: UNNotificationRequest, withCompletionHandler completion: (@Sendable (Error?) -> Void)?) {
        XCTFail("Occurrence finish must not register notifications")
        completion?(nil)
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeAllPendingNotificationRequests() { XCTFail("Unrelated notifications must be retained") }
    func requestAuthorization(options: UNAuthorizationOptions,
                              completionHandler: @escaping @Sendable (Bool, Error?) -> Void) {
        XCTFail("Legacy cleanup must not request notification authorization")
        completionHandler(false, nil)
    }
}

@MainActor
private final class UnsupportedOccurrenceBackend: AlarmKitScheduling {
    var isAuthorized = true
    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) { completion(.success(())) }
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
    func cancelOriginal(_ alarmID: UUID) {}
    func cancel(_ alarmID: UUID) {}
    func stop(_ alarmID: UUID) {}
}
