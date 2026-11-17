import AlarmKit
import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmFiringTrackedLifecycleTests: XCTestCase {
    private var fixture: TrackedSessionFixture!
    override func setUp() { super.setUp(); fixture = TrackedSessionFixture() }
    override func tearDown() { fixture.close(); fixture = nil; super.tearDown() }

    func testPendingAThenFinishBlocksBDebitUntilLateARegistrationIsRemoved() throws {
        let backend = TrackedSessionBackend()
        backend.deferred = true
        let first = fixture.model(backend: backend)
        XCTAssertTrue(first.snooze())
        let firstToken = try XCTUnwrap(backend.tokens.last)
        first.dismiss()
        let blocked = fixture.model(backend: backend)
        XCTAssertFalse(blocked.snooze(), "A still owns the physical operation, even after finish")
        XCTAssertEqual(try charges().map(\.amount), [50])
        XCTAssertEqual(backend.tokens, [firstToken])

        backend.resolve() // The entered A operation really registers after finish, then its callback cleans it.
        let id = AlarmKitScheduler.snoozeID(for: fixture.alarm.id)
        XCTAssertNil(backend.registrations[id])
        XCTAssertNil(first.nextRingDate())
        XCTAssertTrue(WakeEventStore(defaults: fixture.defaults).wakeDays().isEmpty)
        XCTAssertEqual(first.dismiss(), .success(.completedNow), "Retry confirms cleanup before a new debit")
        XCTAssertThrowsError(try fixture.store().resolve(firstToken, alarmID: fixture.alarm.id))
        backend.deferred = false
        let second = fixture.model(backend: backend)
        XCTAssertTrue(second.snooze())
        let secondToken = try XCTUnwrap(backend.tokens.last)
        XCTAssertNotEqual(secondToken.sessionID, firstToken.sessionID)
        let paidB = try XCTUnwrap(backend.registrations[id])
        backend.resolve() // The old completion is consumed, so it cannot remove or overwrite B.
        XCTAssertEqual(backend.registrations[id], paidB)
        XCTAssertEqual(second.nextRingDate(), paidB)
        XCTAssertEqual(try fixture.store().resolve(secondToken, alarmID: fixture.alarm.id).count, 1)
        XCTAssertEqual(try charges().map(\.amount), [50, 50])
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().filter { $0.type == .refund }.count, 0)
        XCTAssertEqual(BalanceService(defaults: fixture.defaults).balance, 1_900)
    }

    func testUnconfirmedPhysicalCleanupKeepsNextDebitBlocked() throws {
        let backend = TrackedSessionBackend()
        backend.deferred = true
        let first = fixture.model(backend: backend)
        XCTAssertTrue(first.snooze())
        first.dismiss()
        backend.confirmsCancellation = false
        backend.resolve()
        XCTAssertFalse(fixture.model(backend: backend).snooze())
        XCTAssertEqual(try charges().count, 1)
        backend.confirmsCancellation = true
        XCTAssertEqual(first.dismiss(), .success(.completedNow), "Checked retry must retain the weekly original")
        backend.deferred = false
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        XCTAssertEqual(try charges().count, 2)
    }

    func testConcreteBackendRechecksOwnershipBeforeItsTaskEntersPhysicalAwait() async throws {
        let store = fixture.store()
        let token = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: fixture.alarm.id)
        let backend = AlarmKitScheduler(cancelAlarm: { _ in })
        var entered = false
        backend.registerTracked = { id, _ in
            entered = true
            return AlarmSnoozeReceipt(systemID: id, fireDate: Date().addingTimeInterval(300))
        }
        let ended = expectation(description: "cancelled task reports a failure")
        var succeeded = false
        backend.scheduleTrackedSnooze(
            fixture.alarm, fireDate: Date().addingTimeInterval(300), token: token, attemptCount: 1,
            isCurrent: { (try? store.pendingCount(token, alarmID: self.fixture.alarm.id)) == 1 }
        ) { result in
            if case .success = result { succeeded = true }
            ended.fulfill()
        }
        // No suspension yet: the concrete backend Task has not entered schedule.
        try store.finish(alarmID: fixture.alarm.id)
        await fulfillment(of: [ended], timeout: 5)
        XCTAssertFalse(entered)
        XCTAssertFalse(succeeded)
        store.operationEnded(token)
        XCTAssertTrue(backend.cancelTrackedSnooze(fixture.alarm.id))
        try store.settleCancelled(alarmID: fixture.alarm.id)
        XCTAssertNoThrow(try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0))
    }

    func testActualDisableBeforeFirstAttemptRefusesCachedUnboundVMWithoutDebitOrRegistration() throws {
        let backend = TrackedSessionBackend()
        let cached = fixture.model(backend: backend)
        let repository = AlarmRepository(defaults: fixture.defaults, scheduler: fixture.scheduler(backend))
        XCTAssertTrue(repository.setEnabled(false, id: fixture.alarm.id))
        XCTAssertFalse(try XCTUnwrap(repository.fetchChecked(id: fixture.alarm.id)).enabled)
        XCTAssertFalse(cached.snooze())
        XCTAssertTrue(cached.currentPenalty.isNaN)
        XCTAssertTrue(try charges().isEmpty)
        XCTAssertTrue(backend.tokens.isEmpty)
        XCTAssertTrue(backend.registrations.isEmpty)
        XCTAssertEqual(backend.cancelled, [fixture.alarm.id])
    }

    func testActualDeleteBeforeFirstAttemptRefusesCachedUnboundVMWithoutDebitOrRegistration() throws {
        let backend = TrackedSessionBackend()
        let cached = fixture.model(backend: backend)
        let repository = AlarmRepository(defaults: fixture.defaults, scheduler: fixture.scheduler(backend))
        XCTAssertTrue(repository.delete(id: fixture.alarm.id))
        XCTAssertNil(try repository.fetchChecked(id: fixture.alarm.id))
        XCTAssertFalse(cached.snooze())
        XCTAssertTrue(try charges().isEmpty)
        XCTAssertTrue(backend.tokens.isEmpty)
        XCTAssertTrue(backend.registrations.isEmpty)
        XCTAssertEqual(backend.cancelled, [fixture.alarm.id])
    }

    func testOneShotCanSnoozeWhileEnabledThenConfirmedFinishDisablesIt() throws {
        let once = TrackedSessionFixture(alarm: Alarm(repeatDays: [0], penaltyAmount: 50, repeatMode: .never))
        defer { once.close() }
        let backend = TrackedSessionBackend()
        let model = once.model(backend: backend)
        XCTAssertTrue(model.snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        XCTAssertEqual(model.nextRingDate(), backend.receipts.last?.fireDate)
        let repository = AlarmRepository(defaults: once.defaults, scheduler: once.scheduler(backend))
        XCTAssertTrue(try XCTUnwrap(repository.fetchChecked(id: once.alarm.id)).enabled)
        model.dismiss()
        XCTAssertFalse(try XCTUnwrap(repository.fetchChecked(id: once.alarm.id)).enabled)
        XCTAssertThrowsError(try once.store().resolve(token, alarmID: once.alarm.id))
        XCTAssertNil(model.nextRingDate())
        XCTAssertFalse(once.model(backend: backend).snooze())
        XCTAssertEqual(try once.ledger().fetchAllChecked().filter { $0.type == .charge }.count, 1)
    }

    func testAsyncDismissalMountRebindRestoresAvailabilityAfterChargedAttemptBecomesScheduled() throws {
        let backend = TrackedSessionBackend()
        backend.deferred = true
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        let stale = ReadBackFiringScreen(alarm: Alarm())
        let host = TrackedSessionHost()
        let presenter = fixture.presenter(host: host, backend: backend)
        presenter.isRootReady = { true }
        var currentHost: UIViewController = stale
        presenter.locateHost = { .success(currentHost) }
        var finishDismissal: (() -> Void)?
        presenter.dismissStaleScreen = { _, completion in finishDismissal = completion }
        var constructed: ReadBackFiringScreen?
        presenter.makeFiringScreen = { [self] _, count in
            let screen = ReadBackFiringScreen(viewModel: fixture.model(backend: backend, count: count))
            constructed = screen
            return screen
        }
        XCTAssertFalse(presenter.present(alarm: fixture.alarm, snoozeReference: .token(token)))
        let held = try XCTUnwrap(constructed)
        XCTAssertFalse(held.viewModel.isProgressionAvailable)
        XCTAssertTrue(held.viewModel.currentPenalty.isNaN)
        XCTAssertTrue(host.screens.isEmpty)
        backend.resolve()
        currentHost = host
        try XCTUnwrap(finishDismissal)()
        let mounted = try XCTUnwrap(host.screens.last)
        XCTAssertTrue(mounted === held)
        XCTAssertTrue(mounted.viewModel.isProgressionAvailable)
        XCTAssertEqual(mounted.viewModel.snoozeCount, 1)
        XCTAssertEqual(mounted.viewModel.currentPenalty, 100)
        XCTAssertEqual(mounted.viewModel.nextRingDate(), backend.receipts.last?.fireDate)
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }

    func testTrackedColdRearmAndRealCurrencyFreezePreservePaidDeadlineAndContext() async throws {
        let backend = TrackedSessionBackend()
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        let receipt = try XCTUnwrap(backend.receipts.last)
        let bytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let scheduler = fixture.scheduler(backend) // Reconstructed services after a tracked paid snooze.
        let rearmed = expectation(description: "cold rearm completed")
        scheduler.rescheduleAll([fixture.alarm]) { failures in
            XCTAssertEqual(failures, 0)
            rearmed.fulfill()
        }
        await fulfillment(of: [rearmed], timeout: 5)
        let center = NotificationCenter()
        let wallet = BalanceService(defaults: fixture.defaults, notificationCenter: center)
        let refreshed = expectation(description: "first wallet currency refresh completed")
        let observers = AppDelegate.observeAlarmRescheduleTriggers(center: center) { trigger in
            AppDelegate.rearmSavedAlarms([self.fixture.alarm], trigger: trigger, scheduler: scheduler) { failures in
                XCTAssertEqual(failures, 0)
                refreshed.fulfill()
            }
        }
        defer { observers.forEach { center.removeObserver($0) } }
        XCTAssertNil(WalletCurrencyStore(defaults: fixture.defaults).storedCurrency)
        XCTAssertEqual(wallet.alarmQuoteCurrency, .legacyDefault)
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 49, currency: .legacyDefault), .credited)
        await fulfillment(of: [refreshed], timeout: 5)
        XCTAssertEqual(backend.registrations[receipt.systemID], receipt.fireDate)
        XCTAssertEqual(backend.registrations[fixture.alarm.id], fixture.alarm.time)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertEqual(try fixture.store().token(for: receipt, alarmID: fixture.alarm.id), token)
        let restored = fixture.model(backend: backend, reference: .token(token))
        XCTAssertEqual(restored.currentPenalty, 100)
        XCTAssertEqual(restored.nextRingDate(), receipt.fireDate)
        XCTAssertEqual(try charges().count, 1)
        XCTAssertEqual(wallet.alarmQuoteCurrency, .legacyDefault)
        XCTAssertTrue(backend.cancelled.isEmpty)
        XCTAssertTrue(backend.cancelledSnoozes.isEmpty)
    }

    func testConcreteInvalidReceiptCancelsOnlyDerivedRegistrationBeforeReportingUnknown() async throws {
        let id = AlarmKitScheduler.snoozeID(for: fixture.alarm.id)
        var physical = [fixture.alarm.id: fixture.alarm.time]
        var cancelled: [UUID] = []
        let backend = AlarmKitScheduler(cancelAlarm: { alarmID in
            cancelled.append(alarmID)
            physical[alarmID] = nil
        })
        backend.registerTracked = { registeredID, _ in
            physical[registeredID] = Date().addingTimeInterval(300)
            return AlarmSnoozeReceipt(systemID: registeredID, fireDate: Date(timeIntervalSince1970: .nan))
        }
        let ended = expectation(description: "invalid receipt rejected")
        let token = AlarmSnoozeToken(sessionID: UUID(), attemptID: UUID())
        backend.scheduleTrackedSnooze(
            fixture.alarm, fireDate: Date().addingTimeInterval(300), token: token,
            attemptCount: 1, isCurrent: { true }
        ) { result in
            guard case .failure(let error) = result,
                  case .unconfirmedRegistration? = error as? AlarmSnoozeContextError else {
                XCTFail("Invalid fixed receipt must never be confirmed")
                ended.fulfill()
                return
            }
            ended.fulfill()
        }
        await fulfillment(of: [ended], timeout: 5)
        XCTAssertEqual(cancelled, [id])
        XCTAssertEqual(physical, [fixture.alarm.id: fixture.alarm.time])
    }

    func testInvalidReceiptRefundPreservesUnknownGuardUntilFreeFinishAndConfirmedCleanup() throws {
        let backend = TrackedSessionBackend()
        backend.unconfirmedRegistration = true
        backend.confirmsCancellation = false
        let model = fixture.model(backend: backend)
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        XCTAssertTrue(model.snooze { outcome = $0 })
        guard case .scheduleFailed = outcome else { return XCTFail("Existing linked refund must be reported") }
        let token = try XCTUnwrap(backend.tokens.last)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        XCTAssertNil(model.nextRingDate())
        XCTAssertTrue(model.currentPenalty.isNaN)
        XCTAssertFalse(fixture.model(backend: backend).snooze())
        XCTAssertNotNil(backend.registrations[AlarmKitScheduler.snoozeID(for: fixture.alarm.id)])
        XCTAssertEqual(try charges().count, 1)
        let rows = try fixture.ledger().fetchAllChecked()
        XCTAssertEqual(rows.filter { $0.type == .refund }.count, 1)
        XCTAssertEqual(rows.first { $0.type == .refund }?.refundsTransactionID, try charges().first?.id)
        XCTAssertEqual(BalanceService(defaults: fixture.defaults).balance, 2_000)
        backend.confirmsCancellation = true
        XCTAssertEqual(model.dismiss(), .failure(.ownershipUnavailable),
                       "An unconfirmed receipt must not authorize deletion of an unknown derived registration")
        XCTAssertFalse(fixture.model(backend: backend).snooze())
        XCTAssertTrue(backend.cancelTrackedSnooze(fixture.alarm.id), "External cleanup establishes actual absence")
        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        backend.unconfirmedRegistration = false
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        XCTAssertEqual(try charges().count, 2)
    }

    private func charges() throws -> [Transaction] {
        try fixture.ledger().fetchAllChecked().filter { $0.type == .charge }
    }
}
