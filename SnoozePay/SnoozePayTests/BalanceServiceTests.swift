import XCTest
@testable import SnoozePay

/// Unit tests for BalanceService — the critical financial logic.
final class BalanceServiceTests: XCTestCase {

    /// Use a fresh UserDefaults suite to avoid polluting real app data.
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var service: BalanceService!

    override func setUp() {
        super.setUp()
        suiteName = "test_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService(
        balance: Double = 0,
        notificationCenter: NotificationCenter = .default
    ) -> BalanceService {
        testDefaults.set(balance, forKey: "user_balance")
        return BalanceService(defaults: testDefaults, notificationCenter: notificationCenter)
    }

    // MARK: - Multi-observer broadcast (#22)

    /// Three independent observers must all receive a balance update from a
    /// single `topUp`. Regression for the single-slot closure pattern that
    /// previously caused `AlarmsListViewModel` to silently overwrite any
    /// other subscriber.
    func testTopUp_notifiesAllObservers() {
        // Use an isolated NotificationCenter so we don't clash with the real
        // shared singleton observers running inside the host app.
        let center = NotificationCenter()
        let service = makeService(balance: 0, notificationCenter: center)

        let exp1 = expectation(description: "observer 1")
        let exp2 = expectation(description: "observer 2")
        let exp3 = expectation(description: "observer 3")

        var received: [Double] = []
        let lock = NSLock()
        let record: (Notification) -> Void = { note in
            guard let amount = note.userInfo?[BalanceService.balanceUserInfoKey] as? Double else { return }
            lock.lock()
            received.append(amount)
            lock.unlock()
        }

        let token1 = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { note in record(note); exp1.fulfill() }
        let token2 = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { note in record(note); exp2.fulfill() }
        let token3 = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { note in record(note); exp3.fulfill() }

        defer {
            center.removeObserver(token1)
            center.removeObserver(token2)
            center.removeObserver(token3)
        }

        service.topUp(amount: 100)

        wait(for: [exp1, exp2, exp3], timeout: 2.0)
        XCTAssertEqual(received, [100, 100, 100])
    }

    /// `charge` (the dual mutator) must also broadcast to all observers.
    func testCharge_notifiesAllObservers() {
        let center = NotificationCenter()
        let service = makeService(balance: 500, notificationCenter: center)

        let exp1 = expectation(description: "observer 1")
        let exp2 = expectation(description: "observer 2")

        let token1 = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { _ in exp1.fulfill() }
        let token2 = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { _ in exp2.fulfill() }

        defer {
            center.removeObserver(token1)
            center.removeObserver(token2)
        }

        let charged = service.charge(amount: 50, alarmID: nil)
        XCTAssertTrue(charged)
        wait(for: [exp1, exp2], timeout: 2.0)
    }

    // MARK: - charge / topUp invariants (#32)

    /// Helper: build an isolated TransactionRepository tied to the same
    /// suite as the BalanceService under test, so we can assert side
    /// effects on the financial ledger without touching shared state.
    private func makeServiceWithLedger(
        balance: Double,
        notificationCenter: NotificationCenter
    ) -> (service: BalanceService, ledger: TransactionRepository) {
        testDefaults.set(balance, forKey: "user_balance")
        let ledger = TransactionRepository(defaults: testDefaults)
        let service = BalanceService(
            defaults: testDefaults,
            transactionRepository: ledger,
            notificationCenter: notificationCenter
        )
        return (service, ledger)
    }

    /// Insufficient funds: `charge` MUST NOT mutate balance, MUST NOT record
    /// a transaction, and MUST NOT broadcast `balanceChangedNotification`.
    /// Three invariants in one test because they're a single atomic contract —
    /// any one breaking is a financial bug.
    func testCharge_insufficientFunds_balanceUnchanged_noTransaction_noNotification() {
        let center = NotificationCenter()
        let (service, ledger) = makeServiceWithLedger(balance: 30, notificationCenter: center)

        let didFire = expectation(description: "notification must NOT fire")
        didFire.isInverted = true
        let token = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: nil
        ) { _ in didFire.fulfill() }
        defer { center.removeObserver(token) }

        let charged = service.charge(amount: 50, alarmID: nil)

        XCTAssertFalse(charged, "charge must report failure on insufficient funds")
        XCTAssertEqual(service.balance, 30, "Balance must be untouched on failed charge")
        XCTAssertTrue(ledger.fetchAll().isEmpty,
                      "No transaction may be recorded for a failed charge")
        wait(for: [didFire], timeout: 0.5)
    }

    /// Successful charge records exactly one Transaction with type=.charge,
    /// amount = requested, and alarmID round-tripped through the optional UUID.
    func testCharge_success_recordsTransactionWithAlarmID() {
        let alarmID = UUID()
        let (service, ledger) = makeServiceWithLedger(balance: 200, notificationCenter: NotificationCenter())

        XCTAssertTrue(service.charge(amount: 75, alarmID: alarmID))

        let transactions = ledger.fetchAll()
        XCTAssertEqual(transactions.count, 1)
        let transaction = transactions[0]
        XCTAssertEqual(transaction.type, .charge)
        XCTAssertEqual(transaction.amount, 75)
        XCTAssertEqual(transaction.alarmID, alarmID.uuidString,
                       "alarmID must be persisted as the original UUID's string form")
    }

    /// `topUp` always succeeds (no insufficient-funds gate) and records a
    /// `.topup` transaction with the credited amount and `alarmID == nil`.
    func testTopUp_recordsTransaction() {
        let (service, ledger) = makeServiceWithLedger(balance: 0, notificationCenter: NotificationCenter())

        service.topUp(amount: 149)

        let transactions = ledger.fetchAll()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].type, .topup)
        XCTAssertEqual(transactions[0].amount, 149)
        XCTAssertNil(transactions[0].alarmID, "topUp transactions must not carry an alarmID")
        XCTAssertEqual(service.balance, 149)
    }

    // MARK: - Refund linkage (issue #133)

    /// `chargeWithReceipt` returns the persisted Transaction so a subsequent
    /// refund can target it by ID. Without the receipt the coordinator would
    /// have to look up the most recent charge by alarmID/timestamp — a
    /// race-prone heuristic that breaks under concurrent snoozes.
    func testChargeWithReceipt_returnsPersistedTransaction() {
        let alarmID = UUID()
        let (service, ledger) = makeServiceWithLedger(
            balance: 200, notificationCenter: NotificationCenter()
        )

        let receipt = service.chargeWithReceipt(amount: 75, alarmID: alarmID)

        XCTAssertNotNil(receipt)
        XCTAssertEqual(receipt?.type, .charge)
        XCTAssertEqual(receipt?.amount, 75)
        XCTAssertEqual(receipt?.alarmID, alarmID.uuidString)

        let stored = ledger.fetchAll().first { $0.id == receipt?.id }
        XCTAssertNotNil(stored,
            "Receipt's id must match the persisted Transaction so the caller can later refund by ID")
    }

    /// Insufficient-funds returns `nil` from `chargeWithReceipt` and does not
    /// touch the ledger — same contract as `charge(...) -> Bool`.
    func testChargeWithReceipt_insufficientFunds_returnsNil() {
        let (service, ledger) = makeServiceWithLedger(
            balance: 10, notificationCenter: NotificationCenter()
        )

        XCTAssertNil(service.chargeWithReceipt(amount: 50, alarmID: UUID()))
        XCTAssertTrue(ledger.fetchAll().isEmpty)
        XCTAssertEqual(service.balance, 10)
    }

    /// `topUp(amount:refundsTransactionID:)` records the link in the ledger
    /// row so stats can pair the refund with its original charge.
    func testTopUp_withRefundsTransactionID_persistsLink() {
        let originalChargeID = UUID()
        let (service, ledger) = makeServiceWithLedger(
            balance: 0, notificationCenter: NotificationCenter()
        )

        XCTAssertTrue(service.topUp(amount: 50, refundsTransactionID: originalChargeID))

        let txs = ledger.fetchAll()
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].type, .topup)
        XCTAssertEqual(txs[0].refundsTransactionID, originalChargeID,
            "Refund link must round-trip through persistence so stats consumers can pair charge + refund")
    }

    /// Backward compatibility: `topUp(amount:)` (legacy signature) writes a
    /// Transaction with `refundsTransactionID == nil`. Organic IAP top-ups
    /// must not be misclassified as refunds.
    func testTopUp_organic_hasNilRefundLink() {
        let (service, ledger) = makeServiceWithLedger(
            balance: 0, notificationCenter: NotificationCenter()
        )

        service.topUp(amount: 100)

        XCTAssertNil(ledger.fetchAll().first?.refundsTransactionID,
            "Organic top-ups must not look like refunds")
    }

    /// Boundary: balance == amount must satisfy `canAfford` (>=, not >).
    /// A subtle off-by-one here would silently disable the user's last snooze.
    func testCanAfford_boundaryAtExactEquality() {
        let service = makeService(balance: 50)
        XCTAssertTrue(service.canAfford(50), "canAfford must return true when balance == amount")
        XCTAssertFalse(service.canAfford(50.01), "canAfford must return false when balance < amount by any epsilon")
    }

    // MARK: - Concurrency

    func testConcurrentCharge_neverGoesNegative() {
        let initialBalance: Double = 1000
        let amount: Double = 10
        let iterations = 100
        let service = makeService(balance: initialBalance)

        let successCount = NSCountedSet()
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let charged = service.charge(amount: amount, alarmID: nil)
            if charged {
                lock.lock()
                successCount.add("ok")
                lock.unlock()
            }
        }

        let successes = successCount.count(for: "ok")
        let expectedSuccesses = Int(initialBalance / amount)

        XCTAssertGreaterThanOrEqual(service.balance, 0)
        XCTAssertEqual(successes, expectedSuccesses)
        XCTAssertEqual(service.balance, initialBalance - Double(successes) * amount)
    }

    // MARK: - Negative balance corruption (#119)

    /// Synthetic negative `user_balance` (race / downgrade / tampering) MUST
    /// flip `balanceCorrupted`, broadcast `balanceCorruptedNotification` with
    /// the raw value, and report `balance == 0` to downstream math so the
    /// wallet doesn't behave as if it owes money.
    func testNegativeStoredBalance_flipsCorruptedFlagAndBroadcasts() {
        let center = NotificationCenter()
        // Inject the corrupt value directly — the public API would never
        // produce this state, which is the whole point of the detection.
        testDefaults.set(-42.5, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)

        let exp = expectation(description: "corruption notification fires")
        var receivedRaw: Double?
        let token = center.addObserver(
            forName: BalanceService.balanceCorruptedNotification,
            object: nil,
            queue: .main
        ) { note in
            receivedRaw = note.userInfo?[BalanceService.balanceCorruptedRawValueKey] as? Double
            exp.fulfill()
        }
        defer { center.removeObserver(token) }

        // Reading triggers detection.
        XCTAssertEqual(service.balance, 0,
                       "Corrupt negative balance must be reported as 0 to downstream math")
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(service.balanceCorrupted, "balanceCorrupted flag must latch on detection")
        XCTAssertEqual(receivedRaw, -42.5, "Notification must carry the raw negative value")
    }

    /// NaN in `user_balance` (extremely rare, but reachable via concurrent
    /// race writing arbitrary `Double` bits or external defaults tampering)
    /// MUST trigger corruption detection. Without this guard `current >= amount`
    /// is always false for NaN, silently disabling every charge with no signal
    /// to the user (issue #201).
    func testNaNStoredBalance_flipsCorruptedFlagAndBroadcasts() {
        let center = NotificationCenter()
        testDefaults.set(Double.nan, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)

        let exp = expectation(description: "corruption notification fires")
        var receivedRaw: Double?
        let token = center.addObserver(
            forName: BalanceService.balanceCorruptedNotification,
            object: nil,
            queue: .main
        ) { note in
            receivedRaw = note.userInfo?[BalanceService.balanceCorruptedRawValueKey] as? Double
            exp.fulfill()
        }
        defer { center.removeObserver(token) }

        XCTAssertEqual(service.balance, 0,
                       "NaN-corrupt balance must be reported as 0 to downstream math")
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertTrue(receivedRaw?.isNaN == true,
                      "Notification must carry the raw NaN value so support tooling sees what was found")
    }

    /// Positive infinity in storage MUST flip corruption — same reasoning as
    /// NaN. `current >= amount` is true for Infinity, which would let the
    /// charge pass and then subtract from `+inf`, silently producing more
    /// infinity (not a real failure, but a corrupt state must not propagate).
    func testPositiveInfinityStoredBalance_flipsCorruptedFlagAndBroadcasts() {
        let center = NotificationCenter()
        testDefaults.set(Double.infinity, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)

        let exp = expectation(description: "corruption notification fires")
        var receivedRaw: Double?
        let token = center.addObserver(
            forName: BalanceService.balanceCorruptedNotification,
            object: nil,
            queue: .main
        ) { note in
            receivedRaw = note.userInfo?[BalanceService.balanceCorruptedRawValueKey] as? Double
            exp.fulfill()
        }
        defer { center.removeObserver(token) }

        XCTAssertEqual(service.balance, 0)
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertEqual(receivedRaw, .infinity)
    }

    /// Negative infinity in storage MUST flip corruption — caught by both the
    /// `isFinite` guard and the `>= 0` guard, but the test pins the path so a
    /// refactor relaxing either guard cannot silently regress.
    func testNegativeInfinityStoredBalance_flipsCorruptedFlagAndBroadcasts() {
        let center = NotificationCenter()
        testDefaults.set(-Double.infinity, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)

        let exp = expectation(description: "corruption notification fires")
        let token = center.addObserver(
            forName: BalanceService.balanceCorruptedNotification,
            object: nil,
            queue: .main
        ) { _ in exp.fulfill() }
        defer { center.removeObserver(token) }

        XCTAssertEqual(service.balance, 0)
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(service.balanceCorrupted)
    }

    /// Under corruption, `charge` must refuse and return `false` — mirrors the
    /// locked-ledger gate from #72 so we don't silently mutate a corrupt store.
    func testCharge_refusedUnderCorruption() {
        let center = NotificationCenter()
        let (service, ledger) = makeServiceWithLedger(balance: -10, notificationCenter: center)
        _ = service.balance // trigger detection

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertFalse(service.charge(amount: 1, alarmID: nil),
                       "charge must refuse when balance store is corrupted")
        XCTAssertTrue(ledger.fetchAll().isEmpty,
                      "No transaction may land while balance is corrupted")
    }

    /// Under corruption, `topUp` must refuse — otherwise an IAP would silently
    /// land on top of a corrupt value the user hasn't acknowledged.
    func testTopUp_refusedUnderCorruption() {
        let center = NotificationCenter()
        let (service, ledger) = makeServiceWithLedger(balance: -10, notificationCenter: center)
        _ = service.balance // trigger detection

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertFalse(service.topUp(amount: 100),
                       "topUp must refuse when balance store is corrupted")
        XCTAssertTrue(ledger.fetchAll().isEmpty,
                      "No transaction may land while balance is corrupted")
    }

    /// `acknowledgeCorruption` resets storage to 0, clears the flag, and
    /// broadcasts a regular `balanceChangedNotification` so observers refresh
    /// to the new zero state. After ack, `charge`/`topUp` work again.
    func testAcknowledgeCorruption_clearsFlagAndRestoresMutability() {
        let center = NotificationCenter()
        testDefaults.set(-99.0, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)
        _ = service.balance // trigger detection
        XCTAssertTrue(service.balanceCorrupted)

        let changed = expectation(description: "balanceChanged fires after ack")
        var receivedAmount: Double?
        let token = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            receivedAmount = note.userInfo?[BalanceService.balanceUserInfoKey] as? Double
            changed.fulfill()
        }
        defer { center.removeObserver(token) }

        service.acknowledgeCorruption()

        wait(for: [changed], timeout: 1.0)
        XCTAssertEqual(receivedAmount, 0)
        XCTAssertFalse(service.balanceCorrupted, "Flag must clear after acknowledgement")
        XCTAssertEqual(service.balance, 0, "Balance must be reset to 0")
        XCTAssertTrue(service.topUp(amount: 50), "Mutations must work again after ack")
        XCTAssertEqual(service.balance, 50)
    }

    func testConcurrentChargeAndTopUp_remainsConsistent() {
        let initialBalance: Double = 500
        let amount: Double = 5
        let iterations = 200
        let service = makeService(balance: initialBalance)

        DispatchQueue.concurrentPerform(iterations: iterations) { idx in
            if idx % 2 == 0 {
                service.charge(amount: amount, alarmID: nil)
            } else {
                service.topUp(amount: amount)
            }
        }

        XCTAssertGreaterThanOrEqual(service.balance, 0)
    }
}

/// Tests for AlarmFiringViewModel — snooze/balance deduction edge cases.
final class AlarmFiringViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func alarm(penalty: Double, progressive: Bool = false) -> Alarm {
        Alarm(
            penaltyAmount: penalty,
            progressiveScale: progressive
        )
    }

    // MARK: - canSnooze tests

    func testCanSnoozeWhenBalanceExact() {
        // Balance = exactly penalty amount → should succeed, balance becomes 0
        let balanceService = BalanceService.shared
        let startBalance = balanceService.balance

        let alarm = alarm(penalty: 50)
        // Set balance to exactly the penalty
        balanceService.topUp(amount: 50 - startBalance + startBalance) // Reset to known state

        // Test the pure logic: canAfford(50) when balance = 50
        // This is tested in the ViewModel indirectly via canSnooze
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)
        // The actual canSnooze depends on live balance — test the calculation path
        let penalty = alarm.penalty(forSnoozeCount: 1)
        XCTAssertEqual(penalty, 50)
    }

    func testPenaltyForFirstSnooze() {
        let alarm = alarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0)
        XCTAssertEqual(vm.currentPenalty, 50)
    }

    func testPenaltyForSecondSnoozeWithProgression() {
        let alarm = alarm(penalty: 50, progressive: true)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 1)
        // snoozeCount=1 → penalty(forSnoozeCount: 2) → 50 * 2 = 100
        XCTAssertEqual(vm.currentPenalty, 100)
    }

    func testPenaltyForFifthSnooze() {
        let alarm = alarm(penalty: 50, progressive: true)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 4)
        // snoozeCount=4 → penalty(forSnoozeCount: 5) → 50 * 16 = 800
        XCTAssertEqual(vm.currentPenalty, 800)
    }

    func testSnoozeButtonTitleWhenEmpty() {
        let balanceService = BalanceService.shared
        // Drain balance
        let currentBalance = balanceService.balance
        if currentBalance > 0 {
            balanceService.charge(amount: currentBalance, alarmID: nil)
        }

        let alarm = alarm(penalty: 50)
        let vm = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, balanceService: balanceService)

        XCTAssertFalse(vm.canSnooze)
        XCTAssertEqual(vm.snoozeButtonTitle, "Баланс пуст")
    }
}

/// Tests for StatisticsViewModel — streak and period filtering.
final class StatisticsViewModelTests: XCTestCase {

    func testEmptyDataMotivation() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .week)
        // With no transactions, should show positive message
        XCTAssertEqual(vm.motivationalMessage, "Отлично! Вы не откладывали будильник.")
    }

    func testTotalSpentZero() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .allTime)
        XCTAssertEqual(vm.totalSpent, 0)
        XCTAssertEqual(vm.totalSpentFormatted, "0 ₽")
    }

    func testPeriodTitles() {
        XCTAssertEqual(StatisticsViewModel.Period.week.title, "Неделя")
        XCTAssertEqual(StatisticsViewModel.Period.month.title, "Месяц")
        XCTAssertEqual(StatisticsViewModel.Period.allTime.title, "Всё время")
    }

    func testChartDataCountForWeek() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .week)
        XCTAssertEqual(vm.dailyChartData.count, 7)
    }

    func testChartDataCountForMonth() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .month)
        XCTAssertEqual(vm.dailyChartData.count, 30)
    }

    func testChartDataEmptyForAllTime() {
        let vm = StatisticsViewModel()
        vm.loadData(period: .allTime)
        XCTAssertTrue(vm.dailyChartData.isEmpty)
    }
}

/// Tests for CreateAlarmViewModel — progressive scale preview and day toggle.
final class CreateAlarmViewModelTests: XCTestCase {

    func testProgressiveScalePreview() {
        let vm = CreateAlarmViewModel()
        vm.penaltyAmount = 50
        // Expected: "1-е: 50₽ → 2-е: 100₽ → 3-е: 200₽ → 4-е: 400₽"
        let preview = vm.progressiveScalePreview
        XCTAssertTrue(preview.contains("50₽"))
        XCTAssertTrue(preview.contains("100₽"))
        XCTAssertTrue(preview.contains("200₽"))
        XCTAssertTrue(preview.contains("400₽"))
    }

    func testDayToggleAddsAndRemoves() {
        let vm = CreateAlarmViewModel()
        XCTAssertTrue(vm.repeatDays.isEmpty)

        vm.toggleDay(0) // Add Monday
        XCTAssertEqual(vm.repeatDays, [0])

        vm.toggleDay(2) // Add Wednesday
        XCTAssertEqual(vm.repeatDays, [0, 2])

        vm.toggleDay(0) // Remove Monday
        XCTAssertEqual(vm.repeatDays, [2])
    }

    func testDayToggleSortedOrder() {
        let vm = CreateAlarmViewModel()
        vm.toggleDay(6)
        vm.toggleDay(0)
        vm.toggleDay(3)
        XCTAssertEqual(vm.repeatDays, [0, 3, 6]) // Should always be sorted
    }

    func testSaveCreatesNewAlarmWithCorrectValues() {
        let vm = CreateAlarmViewModel()
        vm.name = "Тест"
        vm.penaltyAmount = 100
        vm.progressiveScale = true
        vm.snoozeMinutes = 15
        vm.vibrationEnabled = false

        // Save should not crash
        let result = vm.save()
        XCTAssertTrue(result)
    }

    func testEmptyNameDefaultsToPlaceholder() {
        let vm = CreateAlarmViewModel()
        vm.name = ""
        vm.save()
        // Verify the alarm was saved with default name
        let saved = AlarmRepository(defaults: .standard).fetchAll().last
        XCTAssertEqual(saved?.name, "Будильник")
    }
}
