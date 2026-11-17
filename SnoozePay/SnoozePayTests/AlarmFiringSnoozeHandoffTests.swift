import UIKit
import XCTest
@testable import SnoozePay

/// #641: money moving is not confirmation of another ring. Exercise the actual
/// firing action, deferred backend completion, durable warning, and Stop race.
@MainActor
final class AlarmFiringSnoozeHandoffTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var screen: HandoffScreen!
    private var backend: HandoffBackend!
    private var wallet: HandoffWallet!
    private var warnings: CriticalWarningCenter!

    override func setUp() {
        super.setUp()
        suite = "AlarmFiringSnoozeHandoffTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        backend = HandoffBackend()
        wallet = HandoffWallet()
        warnings = CriticalWarningCenter(defaults: defaults)
        warnings.isForegroundActive = { false }
    }

    override func tearDown() {
        if screen?.isViewLoaded == true { screen.viewDidDisappear(false) }
        screen = nil
        backend = nil
        wallet = nil
        warnings = nil
        drainMainQueue()
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testSynchronousDenied_keepsFiringAndPersistsRefundWarningWithoutTarget() {
        backend.isAuthorized = false
        makeScreen(loadView: false) // The native denied E2E covers the mounted audio/UI path.

        screen.snoozeTapped()

        assertFailure(refunded: true)
        XCTAssertEqual(wallet.balance, 200)
        XCTAssertEqual(screen.viewModel.snoozeCount, 1, "The refunded charge remains an attempt")
        XCTAssertEqual(backend.snoozeCalls, 0, "Denied scheduling cannot reach AlarmKit")
    }

    func testDelayedFailure_hasNoEarlyCountdownOrDismiss_thenRefundsAndKeepsStop() {
        makeScreen()
        screen.snoozeTapped()
        assertPending()

        backend.resolve(.failure(TestAlarmKitBackend.ScheduleRejected()))

        assertFailure(refunded: true)
        XCTAssertEqual(wallet.balance, 200)
        XCTAssertTrue(screen.snoozeCTA?.isEnabled == true)
    }

    func testDelayedSuccess_dismissesOnlyAfterConfirmationAndDoesNotStopNewAlarm() {
        makeScreen()
        screen.snoozeTapped()
        assertPending()
        screen.snoozeTapped()
        XCTAssertEqual(wallet.charges, [50], "Pending repeated tap must not charge again")
        XCTAssertEqual(backend.snoozeCalls, 1, "Pending repeated tap must not schedule again")

        backend.resolve(.success(()))

        XCTAssertEqual(screen.dismissals, 1)
        XCTAssertFalse(screen.viewModel.isSnoozeScheduling)
        XCTAssertNotNil(screen.viewModel.nextRingDate())
        XCTAssertEqual(backend.stoppedIDs, [screen.viewModel.alarm.id], "Only scheduler's initial stop is allowed")
        XCTAssertTrue(backend.cancelledIDs.isEmpty, "Handoff must preserve the freshly scheduled alarm")
        XCTAssertTrue(wallet.refunds.isEmpty)
        XCTAssertTrue(warnings.pending.isEmpty)
        XCTAssertFalse(screen.isSnoozedStateActive)
    }

    func testDelayedFailure_refundFailureRetainsChargedWarningAndNoCountdown() {
        wallet.refundSucceeds = false
        makeScreen()
        screen.snoozeTapped()
        assertPending()

        backend.resolve(.failure(TestAlarmKitBackend.ScheduleRejected()))

        assertFailure(refunded: false)
        XCTAssertEqual(wallet.balance, 150)
        XCTAssertEqual(wallet.refunds, [50])
    }

    func testStopWhilePending_cancelsLateScheduledAlarmAndDoesNotDismissSummary() {
        makeScreen()
        screen.snoozeTapped()
        assertPending()

        screen.dismissTapped()
        XCTAssertTrue(screen.isStoppedByUser)
        XCTAssertTrue(screen.summary is WokeMorningViewController)
        XCTAssertEqual(backend.cancelledIDs, [screen.viewModel.alarm.id])
        backend.resolve(.success(()))

        XCTAssertEqual(backend.cancelledIDs, [screen.viewModel.alarm.id, screen.viewModel.alarm.id],
                       "A trigger created after Stop's first cancel must be cancelled too")
        XCTAssertEqual(screen.dismissals, 0, "Late success must not remove the user's summary")
        XCTAssertNil(screen.viewModel.nextRingDate())
        XCTAssertFalse(screen.viewModel.snooze(), "A stopped firing session cannot start another debit")
        XCTAssertEqual(wallet.charges, [50])
        XCTAssertTrue(wallet.refunds.isEmpty, "Stop must preserve the existing charge/refund policy")
    }

    private func makeScreen(loadView: Bool = true) {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        let model = AlarmFiringViewModel(
            alarm: Alarm(penaltyAmount: 50), balanceService: wallet,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler), scheduler: scheduler,
            wakeStore: WakeEventStore(defaults: defaults), ledger: TransactionRepository(defaults: defaults)
        )
        screen = HandoffScreen(viewModel: model)
        screen.criticalWarnings = warnings
        if loadView { screen.loadViewIfNeeded(); screen.updateUI() }
    }

    private func assertPending(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(screen.viewModel.isSnoozeScheduling, file: file, line: line)
        XCTAssertEqual(screen.dismissals, 0, file: file, line: line)
        XCTAssertFalse(screen.isSnoozedStateActive, file: file, line: line)
        XCTAssertNil(screen.viewModel.nextRingDate(), file: file, line: line)
        XCTAssertNil(screen.snoozedCountdownLabel, file: file, line: line)
        XCTAssertTrue(screen.snoozeCTA?.isEnabled == false, file: file, line: line)
        XCTAssertTrue(screen.dismissButton.isEnabled, file: file, line: line)
    }

    private func assertFailure(refunded: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(screen.dismissals, 0, file: file, line: line)
        XCTAssertFalse(screen.isSnoozedStateActive, file: file, line: line)
        XCTAssertFalse(screen.viewModel.isSnoozeScheduling, file: file, line: line)
        XCTAssertNil(screen.viewModel.snoozeAnchor, file: file, line: line)
        XCTAssertNil(screen.viewModel.nextRingDate(), file: file, line: line)
        XCTAssertNil(screen.snoozedCountdownLabel, file: file, line: line)
        XCTAssertTrue(screen.dismissButton.isEnabled, file: file, line: line)
        XCTAssertEqual(warnings.pending.count, 1, file: file, line: line)
        XCTAssertEqual(warnings.pending.first?.refundLanded, refunded, file: file, line: line)
        XCTAssertEqual(CriticalWarningCenter(defaults: defaults).pending, warnings.pending, file: file, line: line)
        XCTAssertEqual(wallet.charges, [50], file: file, line: line)
    }
}

private final class HandoffScreen: AlarmFiringViewController {
    var dismissals = 0
    var summary: UIViewController?
    override func dismiss(animated: Bool, completion: (() -> Void)?) { dismissals += 1 }
    override func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?) {
        summary = viewControllerToPresent
    }
}

private final class HandoffBackend: AlarmKitScheduling {
    var isAuthorized = true
    var snoozeCalls = 0
    var stoppedIDs: [UUID] = []
    var cancelledIDs: [UUID] = []
    private var completion: ((Result<Void, Error>) -> Void)?
    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(isAuthorized) }
    func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) { completion(.success(())) }
    func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        snoozeCalls += 1
        self.completion = completion
    }
    func resolve(_ result: Result<Void, Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }
    func cancelOriginal(_ alarmID: UUID) {}
    func cancel(_ alarmID: UUID) { cancelledIDs.append(alarmID) }
    func stop(_ alarmID: UUID) { stoppedIDs.append(alarmID) }
}

private final class HandoffWallet: AlarmFiringBalancing {
    let walletCurrency: Currency = .rub
    var balance: Double = 200
    var charges: [Double] = []
    var refunds: [Double] = []
    var refundSucceeds = true
    func acceptsPurchase(in currency: Currency) -> Bool { false }
    func canAfford(_ amount: Double) -> Bool { balance >= amount }
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        charges.append(amount)
        balance -= amount
        return Transaction(type: .charge, amount: amount, alarmID: alarmID?.uuidString)
    }
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool {
        refunds.append(amount)
        guard refundSucceeds else { return false }
        balance += amount
        return true
    }
}
