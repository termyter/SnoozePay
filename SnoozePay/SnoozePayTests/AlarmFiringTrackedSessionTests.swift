import AlarmKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmFiringTrackedSessionTests: XCTestCase {
    private var fixture: TrackedSessionFixture!
    override func setUp() { super.setUp(); fixture = TrackedSessionFixture() }
    override func tearDown() { fixture.close(); fixture = nil; super.tearDown() }

    func testFreshVMAndAllReconstructedServicesChargeTheApprovedLadder() throws {
        var reference: AlarmSnoozeReference?
        for (index, expected) in [50.0, 100, 200, 400, 400].enumerated() {
            let backend = TrackedSessionBackend()
            let model = fixture.model(backend: backend, reference: reference)
            XCTAssertEqual(model.currentPenalty, expected)
            var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
            XCTAssertTrue(model.snooze { outcome = $0 })
            XCTAssertEqual(outcome, .scheduled)
            let token = try XCTUnwrap(backend.tokens.last)
            let actual = try XCTUnwrap(backend.receipts.last)
            let requested = try XCTUnwrap(backend.requestedDates.last)
            XCTAssertNotEqual(actual.fireDate, requested)
            XCTAssertEqual(model.nextRingDate(), actual.fireDate)
            XCTAssertEqual(model.secondsUntilNextRing(from: actual.fireDate), 0)
            XCTAssertEqual(backend.attemptCounts, [index + 1])
            var systemTitle: String?
            _ = try AlarmKitScheduler.makeSnoozeConfiguration(
                for: fixture.alarm, fireDate: requested, token: token, attemptCount: try XCTUnwrap(backend.attemptCounts.last),
                construct: { schedule, attributes, stop, snooze, sound in
                    systemTitle = attributes.presentation.alert.secondaryButton.map { String(localized: $0.text) }
                    return .alarm(schedule: schedule, attributes: attributes,
                                  stopIntent: stop, secondaryIntent: snooze, sound: sound)
                }
            )
            XCTAssertEqual(systemTitle, AlarmKitCopy.pricedSnooze(
                penalty: [100.0, 200, 400, 400, 400][index], currency: .legacyDefault
            ))
            XCTAssertEqual(try fixture.store().token(for: actual, alarmID: fixture.alarm.id), token)
            XCTAssertThrowsError(try fixture.store().token(for: AlarmSnoozeReceipt(
                systemID: actual.systemID, fireDate: requested
            ), alarmID: fixture.alarm.id))
            reference = .token(token)
        }
        let rows = try fixture.ledger().fetchAllChecked()
        XCTAssertEqual(rows.filter { $0.type == .charge }.reversed().map(\.amount), [50, 100, 200, 400, 400])
        XCTAssertEqual(rows.filter { $0.type == .refund }.count, 0)
        XCTAssertEqual(BalanceService(defaults: fixture.defaults).balance, 850)
    }

    func testRefundedFailureKeepsItsAttemptAcrossFreshTokenBoundVM() throws {
        let backend = TrackedSessionBackend()
        backend.reject = true
        let model = fixture.model(backend: backend)
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        XCTAssertTrue(model.snooze { outcome = $0 })
        guard case .scheduleFailed = outcome else { return XCTFail("Expected linked refund") }
        let token = try XCTUnwrap(backend.tokens.last)
        let next = fixture.model(backend: TrackedSessionBackend(), reference: .token(token))
        XCTAssertEqual(next.snoozeCount, 1)
        XCTAssertEqual(next.currentPenalty, 100)
        XCTAssertEqual(BalanceService(defaults: fixture.defaults).balance, 2_000)
        let rows = try fixture.ledger().fetchAllChecked()
        XCTAssertEqual(TransactionRepository.realCharges(from: rows).count, 0)
        XCTAssertEqual(rows.first { $0.type == .refund }?.refundsTransactionID,
                       rows.first { $0.type == .charge }?.id)
    }

    func testRefundFailureRetainsAttemptAndTheExistingDegradedOutcome() throws {
        let backend = TrackedSessionBackend()
        backend.deferred = true
        backend.reject = true
        let model = fixture.model(backend: backend)
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        XCTAssertTrue(model.snooze { outcome = $0 })
        let token = try XCTUnwrap(backend.tokens.last)
        fixture.defaults.set(Data("corrupt-ledger".utf8), forKey: "stored_transactions")
        backend.resolve()
        guard case .scheduleFailedAndRefundFailed = outcome else { return XCTFail("Expected degraded refund outcome") }
        XCTAssertEqual(try fixture.store().resolve(token, alarmID: fixture.alarm.id).count, 1)
        XCTAssertEqual(fixture.model(backend: backend, reference: .token(token)).currentPenalty, 100)
    }

    func testLegacyBackendCannotConvertVoidSuccessIntoATrackedReceipt() {
        let model = fixture.model(backend: TestAlarmKitBackend())
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        XCTAssertTrue(model.snooze { outcome = $0 })
        guard case .scheduleFailed = outcome else { return XCTFail("Unsupported tracked backend must refuse") }
        XCTAssertEqual(BalanceService(defaults: fixture.defaults).balance, 2_000)
        XCTAssertNil(model.nextRingDate())
        XCTAssertEqual(model.snoozeCount, 1)
    }

    func testPendingFinishAndLateSuccessCannotReactivateOrArmTheSession() throws {
        let backend = TrackedSessionBackend()
        backend.deferred = true
        let model = fixture.model(backend: backend)
        XCTAssertTrue(model.snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        XCTAssertEqual(model.dismiss(), .failure(.busy))
        backend.resolve()
        XCTAssertNil(model.nextRingDate())
        XCTAssertFalse(model.snooze())
        XCTAssertTrue(backend.cancelled.isEmpty, "Finish must preserve the weekly original")
        XCTAssertEqual(backend.lateSnoozeCleanupRequests.map(\.alarmID), [fixture.alarm.id])
        XCTAssertNil(backend.registrations[AlarmKitScheduler.snoozeID(for: fixture.alarm.id)])
        XCTAssertTrue(WakeEventStore(defaults: fixture.defaults).wakeDays().isEmpty)
        XCTAssertEqual(model.dismiss(), .success(.completedNow))
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().filter { $0.type == .refund }.count, 0,
                       "Confirmed finish retains the existing charge/refund policy")
    }

    func testDisableOrDeleteCancellationInvalidatesTheDurableToken() throws {
        let backend = TrackedSessionBackend()
        let model = fixture.model(backend: backend)
        XCTAssertTrue(model.snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        fixture.scheduler(backend).cancel(fixture.alarm.id)
        XCTAssertThrowsError(try fixture.store().resolve(token, alarmID: fixture.alarm.id))
        XCTAssertFalse(fixture.model(backend: backend, reference: .token(token)).canSnooze)
    }

    func testCorruptMissingAndUnresolvedTrackedStateNeverChargeOrQuoteZero() throws {
        let missing = AlarmSnoozeToken(sessionID: UUID(), attemptID: UUID())
        let missingModel = fixture.model(backend: TrackedSessionBackend(), reference: .token(missing))
        XCTAssertTrue(missingModel.currentPenalty.isNaN)
        XCTAssertFalse(missingModel.snooze())
        let reserved = try fixture.store().reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        let unresolved = fixture.model(backend: TrackedSessionBackend(), reference: .token(reserved))
        XCTAssertTrue(unresolved.currentPenalty.isNaN)
        XCTAssertFalse(unresolved.snooze())
        let bytes = Data("damaged-context".utf8)
        fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
        let corrupt = fixture.model(backend: TrackedSessionBackend())
        XCTAssertFalse(corrupt.snooze(), "Preflight must refuse before any debit")
        XCTAssertTrue(corrupt.currentPenalty.isNaN)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().filter { $0.type == .charge }.count, 0)
    }

    func testUnavailableUIShowsExplanationAndFreeFinishWithoutNoBalanceOrPrice() {
        let model = fixture.model(backend: TrackedSessionBackend(), reference: .unavailable)
        let screen = AlarmFiringViewController(viewModel: model)
        screen.loadViewIfNeeded()
        defer { screen.viewDidDisappear(false) }
        screen.updateUI()
        XCTAssertFalse(screen.progressionUnavailableLabel.isHidden)
        XCTAssertEqual(screen.progressionUnavailableLabel.text, Localized.text("firing.progression.unavailable"))
        XCTAssertTrue(screen.snoozeCTA?.isHidden == true)
        XCTAssertTrue(screen.noBalanceContainer?.isHidden == true)
        XCTAssertFalse(screen.dismissButton.isHidden)
        XCTAssertTrue(screen.dismissButton.isEnabled)
        XCTAssertFalse(model.canSnooze)
    }
}
