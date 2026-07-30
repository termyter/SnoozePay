import XCTest
import UserNotifications
@testable import SnoozePay

/// Issue #400 — the WokeMorning summary («сегодня списано N ₽» + the snooze
/// count) and the firing-screen history ticker must report what the LEDGER
/// says was billed, not `snoozeCount` × the doubling rule.
///
/// The gap: `snooze()` bumps `snoozeCount` as soon as the charge lands, but a
/// scheduler rejection refunds that penalty without rolling the counter back —
/// so a derived total claimed money the user had already got back. These tests
/// pin the ledger-derived figures, including the refusal to show ANY number
/// when the ledger can't be trusted.
final class AlarmFiringBilledSnoozesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AlarmFiringBilledSnoozesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAlarm(penalty: Double = 50, progressive: Bool = true) -> Alarm {
        Alarm(penaltyAmount: penalty, progressiveScale: progressive)
    }

    /// Scheduler whose notification center rejects `add(_:)` — `scheduleSnooze`
    /// resolves to `.failure`, which triggers the refund path.
    private func makeFailingScheduler() -> AlarmScheduler {
        let center = BilledMockNotificationCenter()
        center.addError = NSError(
            domain: "UNErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Notifications are not allowed"]
        )
        return AlarmScheduler(notificationCenter: center)
    }

    private func makeSucceedingScheduler() -> AlarmScheduler {
        AlarmScheduler(notificationCenter: BilledMockNotificationCenter())
    }

    /// Writes `transactions` straight into the ledger's UserDefaults key so a
    /// test can pin `createdAt` / `type` values the service API won't mint.
    private func seedLedger(_ transactions: [Transaction], file: StaticString = #filePath, line: UInt = #line) {
        do {
            let data = try JSONEncoder().encode(transactions)
            defaults.set(data, forKey: "stored_transactions")
        } catch {
            XCTFail("Ledger fixture must encode: \(error)", file: file, line: line)
        }
    }

    // MARK: - Refunded snooze must not be billed (the #400 regression)

    func testFailedSnooze_isRefunded_soChargedTotalStaysZero() {
        let repo = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repo)
        balance.topUp(amount: 500)

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: balance,
            scheduler: makeFailingScheduler(),
            ledger: repo
        )

        let exp = expectation(description: "schedule outcome")
        XCTAssertTrue(vm.snooze { _ in exp.fulfill() })
        wait(for: [exp], timeout: 10)

        XCTAssertEqual(vm.snoozeCount, 1, "The attempt still counts — it drives the next price")
        XCTAssertEqual(vm.chargedThisMorning, 0,
                       "A refunded snooze must not appear in «сегодня списано»")
        XCTAssertEqual(vm.billedSnoozeCount, 0,
                       "…and must not inflate the snooze count on the summary either")
        XCTAssertEqual(vm.pastPenalties, [], "…nor leave a chip in the history ticker")
    }

    func testSuccessfulSnooze_isBilled() {
        let repo = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repo)
        balance.topUp(amount: 500)

        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(penalty: 50),
            balanceService: balance,
            scheduler: makeSucceedingScheduler(),
            ledger: repo
        )

        let exp = expectation(description: "schedule outcome")
        XCTAssertTrue(vm.snooze { _ in exp.fulfill() })
        wait(for: [exp], timeout: 10)

        XCTAssertEqual(vm.billedSnoozeCount, 1)
        XCTAssertEqual(vm.chargedThisMorning, 50)
        XCTAssertEqual(vm.pastPenalties, [50])
    }

    // MARK: - Mixed history

    func testSeveralSnoozes_oneRefunded_countsAndSumsOnlyTheSurvivors() {
        let alarm = makeAlarm(penalty: 50)
        let repo = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repo)
        balance.topUp(amount: 1000)

        // 50 (kept) → 100 (reversed) → 200 (kept): the doubling rule would say
        // 350 ₽ over three snoozes; the ledger says 250 ₽ over two.
        _ = balance.chargeWithReceipt(amount: 50, alarmID: alarm.id)
        let reversed = balance.chargeWithReceipt(amount: 100, alarmID: alarm.id)
        _ = balance.chargeWithReceipt(amount: 200, alarmID: alarm.id)
        balance.refund(amount: 100, refundsTransactionID: reversed?.id)

        let vm = AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: 3,
            balanceService: balance,
            scheduler: makeSucceedingScheduler(),
            ledger: repo
        )

        XCTAssertEqual(vm.billedSnoozeCount, 2)
        XCTAssertEqual(vm.chargedThisMorning, 250)
        XCTAssertEqual(vm.pastPenalties, [50, 200], "Chronological, reversed charge dropped")
    }

    func testChargesAreOrderedOldestFirst() {
        let alarm = makeAlarm()
        let now = Date()
        seedLedger([
            Transaction(type: .charge, amount: 200, alarmID: alarm.id.uuidString,
                        createdAt: now.addingTimeInterval(-60)),
            Transaction(type: .charge, amount: 50, alarmID: alarm.id.uuidString,
                        createdAt: now.addingTimeInterval(-600))
        ])
        let vm = makeViewModel(alarm: alarm, snoozeCount: 2)

        XCTAssertEqual(vm.pastPenalties, [50, 200],
                       "The ticker reads left-to-right in charge order")
    }

    // MARK: - Scoping

    func testChargesFromAnotherAlarmAreExcluded() {
        let alarm = makeAlarm()
        seedLedger([
            Transaction(type: .charge, amount: 50, alarmID: alarm.id.uuidString),
            Transaction(type: .charge, amount: 300, alarmID: UUID().uuidString)
        ])
        let vm = makeViewModel(alarm: alarm, snoozeCount: 1)

        XCTAssertEqual(vm.chargedThisMorning, 50)
        XCTAssertEqual(vm.billedSnoozeCount, 1)
    }

    func testChargesOlderThanTheWakeWindowAreExcluded() {
        let alarm = makeAlarm()
        let startedAt = Date()
        seedLedger([
            // Yesterday's wake of the SAME alarm — outside the 12 h window.
            Transaction(type: .charge, amount: 400, alarmID: alarm.id.uuidString,
                        createdAt: startedAt.addingTimeInterval(-AlarmFiringViewModel.wakeWindow - 60)),
            Transaction(type: .charge, amount: 50, alarmID: alarm.id.uuidString,
                        createdAt: startedAt.addingTimeInterval(-300))
        ])
        let vm = makeViewModel(alarm: alarm, snoozeCount: 1, firingStartedAt: startedAt)

        XCTAssertEqual(vm.chargedThisMorning, 50,
                       "Only this wake's charges belong in «сегодня списано»")
    }

    func testSnoozesChargedBeforeThisFiringSessionStillCount() {
        // Notification-action snoozes are charged while the firing screen is
        // down; the re-ring builds a fresh VM with the carried count.
        let alarm = makeAlarm()
        let startedAt = Date()
        seedLedger([
            Transaction(type: .charge, amount: 50, alarmID: alarm.id.uuidString,
                        createdAt: startedAt.addingTimeInterval(-1800)),
            Transaction(type: .charge, amount: 100, alarmID: alarm.id.uuidString,
                        createdAt: startedAt.addingTimeInterval(-900))
        ])
        let vm = makeViewModel(alarm: alarm, snoozeCount: 2, firingStartedAt: startedAt)

        XCTAssertEqual(vm.chargedThisMorning, 150)
        XCTAssertEqual(vm.billedSnoozeCount, 2)
    }

    // MARK: - Empty ledger

    func testEmptyLedgerReportsZeroNotUnavailable() {
        let vm = makeViewModel(alarm: makeAlarm(), snoozeCount: 0)

        XCTAssertEqual(vm.billedSnoozes, .known([]))
        XCTAssertEqual(vm.chargedThisMorning, 0, "A brand-new ledger is a real zero, not a failure")
        XCTAssertEqual(vm.billedSnoozeCount, 0)
        XCTAssertEqual(vm.pastPenalties, [])
    }

    func testLedgerWithoutChargesReportsZero() {
        seedLedger([Transaction(type: .topup, amount: 500)])
        let vm = makeViewModel(alarm: makeAlarm(), snoozeCount: 0)

        XCTAssertEqual(vm.chargedThisMorning, 0)
    }

    // MARK: - Unreadable ledger

    func testCorruptLedgerReportsUnavailableInsteadOfZero() {
        defaults.set(Data("{not valid json".utf8), forKey: "stored_transactions")
        let vm = makeViewModel(alarm: makeAlarm(), snoozeCount: 2)

        XCTAssertEqual(vm.billedSnoozes, .unavailable)
        XCTAssertNil(vm.chargedThisMorning,
                     "A number we can't verify must not be rendered — not even 0 ₽")
        XCTAssertNil(vm.billedSnoozeCount)
        XCTAssertEqual(vm.pastPenalties, [], "The ticker hides rather than guesses")
    }

    func testUnrecognizedTransactionTypeReportsUnavailable() {
        let alarm = makeAlarm()
        // A row this build can't classify is skipped by every aggregate, so the
        // total would be silently short (#358).
        seedLedger([
            Transaction(type: .charge, amount: 50, alarmID: alarm.id.uuidString),
            Transaction(type: .unknown("voucher"), amount: 70, alarmID: alarm.id.uuidString)
        ])
        let vm = makeViewModel(alarm: alarm, snoozeCount: 1)

        XCTAssertEqual(vm.billedSnoozes, .unavailable)
        XCTAssertNil(vm.chargedThisMorning)
    }

    func testNonFiniteChargeAmountReportsUnavailable() {
        // Legacy rows predate the finite-amount guard (#441); a NaN would
        // otherwise render as "списано nan ₽". Injected through a stub because
        // `JSONEncoder` refuses to write a NaN in the first place.
        let alarm = makeAlarm()
        let vm = AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: 1,
            balanceService: StubBilledBalance(),
            scheduler: makeSucceedingScheduler(),
            ledger: FixedLedger(transactions: [
                Transaction(type: .charge, amount: .nan, alarmID: alarm.id.uuidString)
            ])
        )

        XCTAssertEqual(vm.billedSnoozes, .unavailable)
        XCTAssertNil(vm.chargedThisMorning)
    }

    func testNegativeChargeAmountReportsUnavailable() {
        let alarm = makeAlarm()
        let vm = AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: 1,
            balanceService: StubBilledBalance(),
            scheduler: makeSucceedingScheduler(),
            ledger: FixedLedger(transactions: [
                Transaction(type: .charge, amount: -50, alarmID: alarm.id.uuidString)
            ])
        )

        XCTAssertEqual(vm.billedSnoozes, .unavailable)
        XCTAssertNil(vm.chargedThisMorning)
    }

    func testThrowingLedgerReportsUnavailable() {
        let vm = AlarmFiringViewModel(
            alarm: makeAlarm(),
            snoozeCount: 1,
            balanceService: StubBilledBalance(),
            scheduler: makeSucceedingScheduler(),
            ledger: ThrowingLedger()
        )

        XCTAssertEqual(vm.billedSnoozes, .unavailable)
        XCTAssertNil(vm.chargedThisMorning)
        XCTAssertNil(vm.billedSnoozeCount)
    }

    // MARK: - Summary copy wiring

    func testSummaryCopyUsesBilledFiguresNotAttempts() {
        let content = WokeMorningContent(snoozes: 1, charged: 50)
        XCTAssertEqual(content.variant, .recovered)
        XCTAssertEqual(content.headline, "Удержались после 1 откладывания")
        XCTAssertEqual(content.subtitle, "Сегодня списано 50 ₽. Завтра попробуем не списать ничего.")
    }

    func testSummaryCopyForUnreadableLedgerStatesNoNumbers() {
        let content = WokeMorningContent(chargesUnavailableAfter: 3)

        XCTAssertEqual(content.variant, .chargesUnavailable)
        XCTAssertFalse(content.headline.contains("3"), "No count we couldn't verify")
        XCTAssertFalse(content.subtitle.contains("₽"), "No sum we couldn't verify")
        XCTAssertEqual(content.charged, 0)
    }

    func testSummaryCopyForUnreadableLedgerWithNoAttemptsStaysClean() {
        // Nothing was ever charged in this session (a snooze only bumps the
        // counter once its charge lands), so "баланс в сохранности" is a fact
        // we hold independently of the ledger.
        XCTAssertEqual(WokeMorningContent(chargesUnavailableAfter: 0).variant, .clean)
    }

    // MARK: - VM factory

    private func makeViewModel(
        alarm: Alarm,
        snoozeCount: Int,
        firingStartedAt: Date = Date()
    ) -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: alarm,
            snoozeCount: snoozeCount,
            balanceService: StubBilledBalance(),
            scheduler: makeSucceedingScheduler(),
            ledger: TransactionRepository(defaults: defaults),
            firingStartedAt: firingStartedAt
        )
    }
}

// MARK: - Test doubles

/// Billing stub — these tests exercise the READ path, so charging is a no-op
/// with a balance high enough to keep `canSnooze` true.
private final class StubBilledBalance: AlarmFiringBalancing {
    var balance: Double = 1000
    func canAfford(_ amount: Double) -> Bool { balance >= amount }
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        balance -= amount
        return Transaction(type: .charge, amount: amount, alarmID: alarmID?.uuidString)
    }
    @discardableResult
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool {
        balance += amount
        return true
    }
}

/// Ledger whose checked read always throws — stands in for a locked/corrupt
/// store without needing byte-level fixtures.
private final class ThrowingLedger: AlarmFiringLedgerReading {
    struct ReadFailure: Error {}
    var lastLoadHadUnrecognizedTypes = false
    func fetchAllChecked() throws -> [Transaction] { throw ReadFailure() }
}

/// Ledger returning a fixed row set — for amounts `JSONEncoder` won't persist
/// (NaN) or that the service API would reject on write (negative).
private final class FixedLedger: AlarmFiringLedgerReading {
    private let transactions: [Transaction]
    var lastLoadHadUnrecognizedTypes = false

    init(transactions: [Transaction]) {
        self.transactions = transactions
    }

    func fetchAllChecked() throws -> [Transaction] { transactions }
}

/// Minimal `NotificationScheduling` stub. `addError` forces `add(_:)` to fail so
/// `scheduleSnooze` resolves to `.failure`.
private final class BilledMockNotificationCenter: NotificationScheduling {
    var addError: Error?

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: ((Error?) -> Void)?
    ) {
        completion?(addError)
    }
    func getPendingNotificationRequests(
        completionHandler: @escaping ([UNNotificationRequest]) -> Void
    ) {
        completionHandler([])
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
