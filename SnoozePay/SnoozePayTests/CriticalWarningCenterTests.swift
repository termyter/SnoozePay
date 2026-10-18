import UIKit
import XCTest
import os
@testable import SnoozePay

@MainActor
final class CriticalWarningCenterTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var center: CriticalWarningCenter!

    override func setUp() {
        super.setUp()
        suite = "critical-warnings-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        center = makeCenter()
    }

    override func tearDown() {
        center = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func makeCenter() -> CriticalWarningCenter {
        let result = CriticalWarningCenter(defaults: defaults)
        result.isForegroundActive = { false }
        return result
    }

    func testBackgroundRelaunchAndAcknowledgement_preserveFIFOAndRefundDistinction() throws {
        let alarmID = UUID()
        center.record(detail: "refund failed", refundLanded: false, alarmID: alarmID)
        center.record(detail: "refunded", refundLanded: true, alarmID: UUID())
        let reloaded = makeCenter()
        XCTAssertEqual(reloaded.pending, center.pending)
        let first = try XCTUnwrap(reloaded.pending.first)
        XCTAssertEqual(first.alarmID, alarmID)
        XCTAssertEqual(first.title, Localized.text("alarm_failure.snooze.title"))
        XCTAssertEqual(first.message, Localized.format("alarm_failure.snooze.body_charged", "refund failed"))
        reloaded.acknowledge(first.id)
        let nextLaunch = makeCenter()
        XCTAssertEqual(nextLaunch.pending.count, 1)
        XCTAssertTrue(try XCTUnwrap(nextLaunch.pending.first).refundLanded)
        XCTAssertEqual(
            nextLaunch.pending.first?.message, Localized.format("alarm_failure.snooze.body_refunded", "refunded")
        )
        nextLaunch.acknowledge(try XCTUnwrap(nextLaunch.pending.first).id)
        XCTAssertTrue(makeCenter().pending.isEmpty)
    }

    func testFiringOutcome_successIsSilent_andRefundFailureRetainsTheStrongerCopy() {
        center.record(.scheduled, alarmID: UUID())
        XCTAssertTrue(center.pending.isEmpty)
        center.record(.scheduleFailedAndRefundFailed(.system(message: "refund")), alarmID: UUID())
        center.record(.scheduleFailed(.system(message: "schedule")), alarmID: UUID())
        XCTAssertEqual(makeCenter().pending.map(\.refundLanded), [false, true])
    }

    func testMissingSplashBusyAndRefusedHosts_doNotAcknowledgeOrDismissAnything() throws {
        center.record(detail: "no re-fire", refundLanded: true, alarmID: nil)
        center.isForegroundActive = { true }
        center.locateRoot = { nil }
        center.flush()
        let splash = SplashViewController()
        center.locateRoot = { splash }
        center.flush()
        let host = Host()
        let window = UIWindow()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        center.locateRoot = { [weak host] in host }
        host.busy = true
        center.flush()
        XCTAssertEqual(host.attempts, 0)
        host.busy = false
        host.refuses = true
        center.flush()
        XCTAssertEqual(host.attempts, 1)
        XCTAssertEqual(host.dismissals, 0)
        XCTAssertEqual(makeCenter().pending.count, 1)
        host.refuses = false
        center.isForegroundActive = { false }
        center.flush()
        XCTAssertEqual(host.attempts, 1, "background delivery must wait for an active scene")
        center.isForegroundActive = { true }
        center.flush()
        let alert = try XCTUnwrap(host.screen as? UIAlertController)
        XCTAssertEqual(alert.message, center.pending.first?.message)
        XCTAssertEqual(alert.actions.map(\.title), [Localized.text("common.button.ok")])
        center.flush()
        XCTAssertEqual(host.attempts, 2, "only one accepted alert may be in flight")
        XCTAssertEqual(makeCenter().pending.count, 1, "presentation is not acknowledgement")
        host.screen = nil // Root replacement/system dismissal without OK.
        center.flush()
        XCTAssertEqual(host.attempts, 3, "an unacknowledged warning must be offered again")
        center.isForegroundActive = { false }
    }

    func testOldScheduleWarning_doesNotHideNewCorruption_forTheSameAlarm() {
        defaults.set(Data("unreadable alarms".utf8), forKey: "stored_alarms")
        let alarmID = UUID()
        center.record(.scheduleFailedAndRefundFailed(.system(message: "old schedule failure")), alarmID: alarmID)
        let presenter = AlarmFiringPresenter(alarmRepository: AlarmRepository(defaults: defaults))
        presenter.criticalWarnings = center
        var genericReports = 0
        presenter.reportDataCorrupted = { _ in genericReports += 1 }
        XCTAssertTrue(presenter.present(alarmID: alarmID))
        XCTAssertEqual(genericReports, 1, "the old scheduling/refund warning does not explain this new corruption")
        center.record(detail: "decode failed", refundLanded: true, alarmID: alarmID, cause: .alarmLoadFailed)
        XCTAssertTrue(presenter.present(alarmID: alarmID))
        XCTAssertEqual(genericReports, 1, "only a load-failure warning owns this corruption diagnostic")
        XCTAssertTrue(presenter.present(alarmID: UUID()))
        XCTAssertEqual(genericReports, 2, "unrelated alarm corruption still has its diagnostic")
        XCTAssertEqual(makeCenter().pending.count, 2)
    }

    func testLegacyWarning_withoutCause_remainsReadableAndDoesNotSuppressCorruption() throws {
        let alarmID = UUID()
        let legacy: [String: Any] = [
            "id": UUID().uuidString, "alarmID": alarmID.uuidString,
            "detail": "previous warning format", "refundLanded": false
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: [legacy]), forKey: "pending_critical_warnings")
        let reloaded = makeCenter()
        XCTAssertEqual(reloaded.pending.count, 1)
        XCTAssertNil(reloaded.pending.first?.cause)
        XCTAssertFalse(reloaded.containsAlarmLoadFailure(alarmID: alarmID))
    }

    func testRestoredDefaultReporter_keepsDeferredAlarmIdentity_andDoesNotSuppressIdenticalUnrelatedError() {
        let delegate = AppDelegate()
        delegate.criticalWarnings = center
        let host = Host()
        let window = UIWindow()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        delegate.locateCorruptionAlertRoot = { [weak host] in
            host.map { .success($0) } ?? .failure(.noHostingWindow)
        }
        let saved = delegate.reportAlarmDataCorrupted
        var overrides = 0
        delegate.reportAlarmDataCorrupted = { _ in overrides += 1 }
        let error = NSError(domain: "same decode error", code: 1)
        let alarmID = UUID()
        delegate.reportAlarmCorruption(error, alarmID: alarmID)
        XCTAssertEqual(overrides, 1)
        delegate.reportAlarmDataCorrupted = saved
        center.record(detail: "earlier scheduling failure", refundLanded: false, alarmID: alarmID)
        AppDelegate.forwardAlarmDataCorrupted(error, alarmID: alarmID, to: delegate)
        drainMainQueue()
        XCTAssertEqual(host.attempts, 1, "an older scheduling warning does not replace this corruption cause")
        host.screen = nil
        AppDelegate.forwardAlarmDataCorrupted(error, alarmID: alarmID, to: delegate)
        center.record(
            detail: error.localizedDescription, refundLanded: true, alarmID: alarmID, cause: .alarmLoadFailed
        )
        drainMainQueue()
        XCTAssertEqual(host.attempts, 1, "the restored default must retain this alarm's deferred context")
        AppDelegate.forwardAlarmDataCorrupted(error, alarmID: UUID(), to: delegate)
        drainMainQueue()
        XCTAssertEqual(host.attempts, 2, "identical text for another alarm must not suppress its alert")
    }

    func testUnreadableQueue_newWarningSurvivesRelaunch_andOriginalBackupsRemainIntact() {
        let bytes = Data("unreadable warning queue".utf8)
        defaults.set(bytes, forKey: "pending_critical_warnings")
        let olderBackupKey = "pending_critical_warnings_unreadable_existing"
        let olderBackup = Data("different earlier corruption".utf8)
        defaults.set(olderBackup, forKey: olderBackupKey)
        var faults: [String] = []
        AppLogger.withTestSink({ _, level, message in
            if level == .fault { faults.append(message) }
        }, perform: {
            center = makeCenter()
            center.record(detail: "new failure", refundLanded: false, alarmID: nil)
        })
        XCTAssertEqual(makeCenter().pending, center.pending, "the new warning must survive process restart")
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(defaults.data(forKey: olderBackupKey), olderBackup)
        let backups = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("pending_critical_warnings_unreadable_")
        }
        XCTAssertTrue(backups.values.contains { ($0 as? Data) == bytes }, "preserve the unreadable original")
        XCTAssertEqual(faults.count, 1)
    }

    func testFiringFailure_afterVCAndItsModelOwnerDisappear_stillRefundsAndPersistsOnce() throws {
        let backend = DeferredBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        let ledger = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: ledger)
        balance.topUp(amount: 100)
        var model: AlarmFiringViewModel? = AlarmFiringViewModel(
            alarm: Alarm(penaltyAmount: 50), balanceService: balance,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler), scheduler: scheduler,
            wakeStore: WakeEventStore(defaults: defaults), ledger: ledger
        )
        var screen: AlarmFiringViewController? = AlarmFiringViewController(viewModel: try XCTUnwrap(model))
        screen?.criticalWarnings = center
        weak var releasedScreen = screen
        weak var retainedOperation = model
        screen?.snoozeTapped()
        screen = nil
        model = nil
        XCTAssertNil(releasedScreen, "the operation must not retain its VC")
        XCTAssertNotNil(retainedOperation, "keep the original refund/outcome callback alive")
        let completion = try XCTUnwrap(backend.completion)
        backend.completion = nil
        completion(.failure(NSError(domain: "schedule rejected", code: 1)))
        XCTAssertEqual(balance.balance, 100)
        let transactionsBeforeReplay = try ledger.fetchAllChecked()
        XCTAssertEqual(transactionsBeforeReplay.filter { $0.type == .charge }.count, 1)
        XCTAssertEqual(transactionsBeforeReplay.filter { $0.type == .refund }.count, 1)
        let ledgerBeforeReplay = defaults.data(forKey: "stored_transactions")
        let balanceBeforeReplay = balance.balance
        let replay = makeCenter()
        let host = Host()
        let window = UIWindow()
        window.rootViewController = host
        window.isHidden = false
        defer { replay.isForegroundActive = { false }; window.isHidden = true; window.rootViewController = nil }
        replay.locateRoot = { [weak host] in host }
        replay.isForegroundActive = { true }
        replay.flush()
        let alert = try XCTUnwrap(host.screen as? UIAlertController)
        XCTAssertEqual(host.attempts, 1, "the reconstructed warning must actually be presented in foreground")
        XCTAssertEqual(alert.message, replay.pending.first?.message)
        replay.flush()
        XCTAssertEqual(host.attempts, 1, "a repeated foreground flush must not duplicate the in-flight alert")
        // Exercise the store acknowledgement used by OK; this is not a UIKit button-tap test.
        replay.acknowledge(try XCTUnwrap(replay.pending.first).id)
        host.screen = nil
        replay.flush()
        XCTAssertTrue(makeCenter().pending.isEmpty)
        XCTAssertEqual(host.attempts, 1)
        XCTAssertEqual(defaults.data(forKey: "stored_transactions"), ledgerBeforeReplay)
        XCTAssertEqual(balance.balance, balanceBeforeReplay)
        XCTAssertEqual(backend.snoozeCalls, 1, "foreground replay and acknowledgement must not reschedule")
    }

    private final class Host: UIViewController {
        var busy = false
        var refuses = false
        var screen: UIViewController?
        var attempts = 0
        var dismissals = 0
        override var isBeingPresented: Bool { busy }
        override var presentedViewController: UIViewController? { screen }
        override func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
            attempts += 1
            if !refuses { screen = viewController }
        }
        override func dismiss(animated: Bool, completion: (() -> Void)?) { dismissals += 1 }
    }

    private final class DeferredBackend: AlarmKitScheduling {
        var authorization: AlarmKitAuthorization { .authorized }
        var isAuthorized: Bool { true }
        var completion: ((Result<Void, Error>) -> Void)?
        var snoozeCalls = 0
        func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
        func schedule(_ alarm: Alarm, completion: @escaping (Result<Void, Error>) -> Void) { completion(.success(())) }
        func scheduleSnooze(_ alarm: Alarm, fireDate: Date, completion: @escaping (Result<Void, Error>) -> Void) {
            snoozeCalls += 1
            self.completion = completion
        }
        func cancel(_ alarmID: UUID) {}
        func stop(_ alarmID: UUID) {}
    }
}
