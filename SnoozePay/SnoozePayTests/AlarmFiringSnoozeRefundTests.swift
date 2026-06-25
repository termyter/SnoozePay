import XCTest
import UserNotifications
@testable import SnoozePay

/// Issue #197 — the in-app (firing VC) snooze path must refund the penalty when
/// the scheduler rejects the next trigger, mirroring `AlarmFiringCoordinator`'s
/// notification-action path. Covers both the clean-refund and the degraded
/// "refund also failed" branches.
final class AlarmFiringSnoozeRefundTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AlarmFiringSnoozeRefundTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeAlarm(penalty: Double = 50) -> Alarm {
        Alarm(penaltyAmount: penalty)
    }

    /// A scheduler whose underlying notification center rejects `add(_:)`, so
    /// `scheduleSnooze` resolves to `.failure(.system)`.
    private func makeFailingScheduler() -> AlarmScheduler {
        let center = FiringMockNotificationCenter()
        center.addError = NSError(
            domain: "UNErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Notifications are not allowed"]
        )
        return AlarmScheduler(notificationCenter: center)
    }

    /// A scheduler that registers the trigger successfully.
    private func makeSucceedingScheduler() -> AlarmScheduler {
        AlarmScheduler(notificationCenter: FiringMockNotificationCenter())
    }

    // MARK: - Clean refund (real ledger)

    func testForegroundSnooze_scheduleFails_refundsBalanceAndReportsScheduleFailed() {
        let balance = BalanceService(defaults: defaults)
        balance.topUp(amount: 200)
        let preCharge = balance.balance

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: balance,
            scheduler: makeFailingScheduler()
        )

        let exp = expectation(description: "schedule outcome")
        var captured: AlarmFiringViewModel.SnoozeScheduleOutcome?
        let charged = vm.snooze { outcome in
            captured = outcome
            exp.fulfill()
        }
        XCTAssertTrue(charged, "Snooze charges when the balance covers the penalty")
        wait(for: [exp], timeout: 10)

        guard case .scheduleFailed = captured else {
            return XCTFail("Expected .scheduleFailed, got \(String(describing: captured))")
        }
        XCTAssertEqual(balance.balance, preCharge, accuracy: 0.001,
                       "Penalty must be refunded so the user isn't billed for a snooze that won't fire")
    }

    func testForegroundSnooze_scheduleFails_ledgerRecordsChargeAndRefund() {
        let repo = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repo)
        balance.topUp(amount: 200)
        let preCount = repo.fetchAll().count

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: balance,
            scheduler: makeFailingScheduler()
        )

        let exp = expectation(description: "schedule outcome")
        vm.snooze { _ in exp.fulfill() }
        wait(for: [exp], timeout: 10)

        // Charge + offsetting refund = two new ledger entries, so stats can
        // reconcile the failed snooze.
        XCTAssertEqual(repo.fetchAll().count, preCount + 2,
                       "Both the charge and the refund must be recorded")
    }

    // MARK: - Degraded refund failure (stub billing)

    func testForegroundSnooze_scheduleFails_refundFails_reportsDegradedOutcome() {
        let billing = StubFiringBalance(balanceValue: 200, chargeResult: true, topUpResult: false)

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: billing,
            scheduler: makeFailingScheduler()
        )

        let exp = expectation(description: "schedule outcome")
        var captured: AlarmFiringViewModel.SnoozeScheduleOutcome?
        vm.snooze { outcome in
            captured = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)

        guard case .scheduleFailedAndRefundFailed = captured else {
            return XCTFail("Expected .scheduleFailedAndRefundFailed, got \(String(describing: captured))")
        }
        XCTAssertEqual(billing.topUpCalls, [50], "A refund of the charged penalty must be attempted")
        XCTAssertEqual(billing.chargeCalls, [50], "The penalty was charged before scheduling")
    }

    // MARK: - Refund linkage (#366)

    func testForegroundSnooze_scheduleFails_refundLinksToChargeTransaction() {
        let billing = StubFiringBalance(balanceValue: 200, chargeResult: true, topUpResult: true)

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: billing,
            scheduler: makeFailingScheduler()
        )

        let exp = expectation(description: "schedule outcome")
        vm.snooze { _ in exp.fulfill() }
        wait(for: [exp], timeout: 10)

        XCTAssertEqual(billing.topUpRefundLinks, [billing.lastChargeID],
                       "Foreground refund must link to the charge it offsets (#366)")
        XCTAssertNotNil(billing.lastChargeID)
    }

    /// End-to-end: a failed foreground snooze must NOT count toward snooze stats,
    /// because the refund links to the charge so `realCharges(from:)` drops it.
    func testForegroundSnooze_scheduleFails_chargeExcludedFromRealCharges() {
        let repo = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repo)
        balance.topUp(amount: 200)

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: balance,
            scheduler: makeFailingScheduler()
        )

        let exp = expectation(description: "schedule outcome")
        vm.snooze { _ in exp.fulfill() }
        wait(for: [exp], timeout: 10)

        let realCharges = TransactionRepository.realCharges(from: repo.fetchAll())
        XCTAssertTrue(realCharges.isEmpty,
                      "A refunded foreground snooze must be excluded from real charges (#366)")
    }

    // MARK: - Success path

    func testForegroundSnooze_scheduleSucceeds_reportsScheduledNoRefund() {
        let billing = StubFiringBalance(balanceValue: 200, chargeResult: true, topUpResult: true)

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: billing,
            scheduler: makeSucceedingScheduler()
        )

        let exp = expectation(description: "schedule outcome")
        var captured: AlarmFiringViewModel.SnoozeScheduleOutcome?
        vm.snooze { outcome in
            captured = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)

        XCTAssertEqual(captured, .scheduled)
        XCTAssertTrue(billing.topUpCalls.isEmpty, "No refund when the snooze schedules successfully")
    }
}

// MARK: - Test doubles

/// Stub `AlarmFiringBalancing` that lets `charge` and `topUp` resolve
/// independently — the only way to exercise `scheduleFailedAndRefundFailed`
/// (the real services are `final` and a locked ledger fails both calls).
private final class StubFiringBalance: AlarmFiringBalancing {
    private(set) var balance: Double
    private let chargeResult: Bool
    private let topUpResult: Bool
    private(set) var chargeCalls: [Double] = []
    private(set) var topUpCalls: [Double] = []
    /// The id minted for the most recent successful `chargeWithReceipt`, so a
    /// test can assert the refund linked back to it (issue #366).
    private(set) var lastChargeID: UUID?
    /// Captures the `refundsTransactionID` passed to each `topUp` so a test can
    /// assert the foreground refund links to the charge instead of `nil`.
    private(set) var topUpRefundLinks: [UUID?] = []

    init(balanceValue: Double, chargeResult: Bool, topUpResult: Bool) {
        self.balance = balanceValue
        self.chargeResult = chargeResult
        self.topUpResult = topUpResult
    }

    func canAfford(_ amount: Double) -> Bool { balance >= amount }

    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        chargeCalls.append(amount)
        guard chargeResult else { return nil }
        balance -= amount
        let transaction = Transaction(type: .charge, amount: amount, alarmID: alarmID?.uuidString)
        lastChargeID = transaction.id
        return transaction
    }

    @discardableResult
    func topUp(amount: Double, refundsTransactionID: UUID?) -> Bool {
        topUpCalls.append(amount)
        topUpRefundLinks.append(refundsTransactionID)
        guard topUpResult else { return false }
        balance += amount
        return true
    }
}

/// Minimal `NotificationScheduling` stub. `addError` forces `add(_:)` to fail so
/// `scheduleSnooze` resolves to `.failure`.
private final class FiringMockNotificationCenter: NotificationScheduling {
    var addError: Error?
    var pendingRequests: [UNNotificationRequest] = []

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        completion?(addError)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        completionHandler(pendingRequests)
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func getDeliveredNotifications(
        completionHandler: @escaping ([UNNotification]) -> Void
    ) {
        completionHandler([])
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func removeAllPendingNotificationRequests() {}
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(false, nil)
    }
}
