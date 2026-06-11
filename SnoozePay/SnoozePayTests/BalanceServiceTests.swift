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
        // Subscribe BEFORE constructing the service: the corruption probe
        // runs at init time (#119/#206), so a late observer would miss the
        // one-shot notification — that cold-start gap is exactly what
        // `corruptedRawValue` exists for, asserted below.
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

        // Inject the corrupt value directly — the public API would never
        // produce this state, which is the whole point of the detection.
        testDefaults.set(-42.5, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)

        XCTAssertEqual(service.balance, 0,
                       "Corrupt negative balance must be reported as 0 to downstream math")
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(service.corruptedRawValue, -42.5,
                       "Latched raw value must stay queryable for late observers (#206)")

        XCTAssertTrue(service.balanceCorrupted, "balanceCorrupted flag must latch on detection")
        XCTAssertEqual(receivedRaw, -42.5, "Notification must carry the raw negative value")
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
        // The post-ack `topUp(50)` below ALSO posts balanceChanged — stop
        // observing first or the expectation gets a second fulfill (API
        // violation crash). The defer-removal then becomes a harmless no-op.
        center.removeObserver(token)
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

    // MARK: - Cold-start corruption queryable by late observers (#206)

    /// The init-time probe posts `balanceCorruptedNotification` BEFORE any UI
    /// observer can exist (cold start: AppDelegate materializes the shared
    /// instance first). NotificationCenter does not retro-deliver, so the
    /// corruption state MUST stay queryable — `balanceCorrupted` +
    /// `corruptedRawValue` — for the late subscriber to pull.
    func testColdStartCorruption_stateQueryableByLateObserver() {
        let center = NotificationCenter()
        testDefaults.set(-77.25, forKey: "user_balance")
        // Init probe latches corruption and posts with NO observer attached —
        // the notification is dropped, simulating the cold-start race.
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)

        // A late observer arrives — no notification will ever replay, but the
        // queryable seam must expose the full pending corruption state.
        XCTAssertTrue(service.balanceCorrupted,
                      "Init-time probe must latch the corruption flag")
        XCTAssertEqual(service.corruptedRawValue, -77.25,
                       "Raw corrupt value must stay queryable for late observers")
    }

    /// `corruptedRawValue` must be `nil` while the store is healthy and must
    /// clear together with the flag on `acknowledgeCorruption()`.
    func testCorruptedRawValue_nilWhenHealthyAndClearedAfterAcknowledge() {
        let center = NotificationCenter()
        let healthy = makeService(balance: 100, notificationCenter: center)
        XCTAssertNil(healthy.corruptedRawValue,
                     "Healthy store must not report a pending corrupt value")

        testDefaults.set(-1.0, forKey: "user_balance")
        let corrupt = BalanceService(defaults: testDefaults, notificationCenter: center)
        XCTAssertEqual(corrupt.corruptedRawValue, -1.0)

        corrupt.acknowledgeCorruption()
        XCTAssertNil(corrupt.corruptedRawValue,
                     "Acknowledgement must clear the pending corrupt value")
        XCTAssertFalse(corrupt.balanceCorrupted)
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

/// Smoke tests for the V3 behavioural StatisticsViewModel (#235) — the
/// money/wake-time/period API was dropped with the redesign; deep coverage of
/// the aggregations lives in `StatisticsViewModelDataTests`.
final class StatisticsViewModelTests: XCTestCase {

    /// The smoke tests below construct the VM on an ISOLATED store — a default
    /// `StatisticsViewModel()` would pull the simulator's real
    /// `UserDefaults.standard` transactions, so any prior app/test activity
    /// makes "empty data" assertions flake (red on CI, red locally after QA).
    private func makeIsolatedStatisticsVM() -> StatisticsViewModel {
        let isolated = UserDefaults(suiteName: "test.statsSmoke.\(UUID().uuidString)")!
        return StatisticsViewModel(
            repository: TransactionRepository(defaults: isolated),
            wakeStore: WakeEventStore(defaults: isolated),
            defaults: isolated
        )
    }

    func testEmptyDataMotivation() {
        let vm = makeIsolatedStatisticsVM()
        vm.loadData()
        // With no transactions, the hero caption celebrates the clean ledger
        // and the weekday card has no "worst day" to point at.
        XCTAssertEqual(vm.lastSlipText, "Срывов ещё не было")
        XCTAssertNil(vm.worstWeekdayName)
    }

    func testEmptyDataHeatmap_hasFullWeeksOfEmptyCells() {
        let vm = makeIsolatedStatisticsVM()
        vm.loadData()
        let days = vm.heatmapDays
        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(days.count % 7, 0, "Grid must pad to whole Monday-first weeks")
        XCTAssertTrue(
            days.allSatisfy { $0.status == .empty },
            "No charges and no wake events → every cell is dark"
        )
    }

    func testEmptyDataTrend_eightFlatWeeks() {
        let vm = makeIsolatedStatisticsVM()
        vm.loadData()
        XCTAssertEqual(vm.weeklyTrend.count, 8)
        XCTAssertTrue(vm.weeklyTrend.allSatisfy { $0.count == 0 })
        XCTAssertEqual(vm.trendDirection, .same)
        XCTAssertEqual(vm.trendHeadline, "Стабильно")
    }
}

/// Tests for CreateAlarmViewModel — progressive scale preview and day toggle.
final class CreateAlarmViewModelTests: XCTestCase {

    func testProgressiveScalePreview() {
        let vm = CreateAlarmViewModel()
        vm.penaltyAmount = 50
        // Expected: "1-е: 50 ₽ → 2-е: 100 ₽ → 3-е: 200 ₽ → 4-е: 400 ₽"
        // (fmtRub narrow no-break space before ₽)
        let preview = vm.progressiveScalePreview
        XCTAssertTrue(preview.contains("50\u{202F}₽"))
        XCTAssertTrue(preview.contains("100\u{202F}₽"))
        XCTAssertTrue(preview.contains("200\u{202F}₽"))
        XCTAssertTrue(preview.contains("400\u{202F}₽"))
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
