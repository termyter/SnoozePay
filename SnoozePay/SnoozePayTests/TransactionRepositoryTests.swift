import XCTest
@testable import SnoozePay

/// Unit tests for TransactionRepository — persistence, filtering, streak calculation.
final class TransactionRepositoryTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: TransactionRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.txRepo.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = TransactionRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func charge(amount: Double = 50, daysAgo: Int = 0) -> Transaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Transaction(type: .charge, amount: amount, createdAt: date)
    }

    private func topup(amount: Double = 500, daysAgo: Int = 0) -> Transaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Transaction(type: .topup, amount: amount, createdAt: date)
    }

    // MARK: - record & persistence

    func testRecord_persistsTransaction() {
        let tx = charge(amount: 100)
        let result = repo.record(tx)

        XCTAssertTrue(result)

        let all = repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.amount, 100)
        XCTAssertEqual(all.first?.type, .charge)
        XCTAssertEqual(all.first?.id, tx.id)
    }

    func testRecord_multipleTransactions() {
        repo.record(charge(amount: 50))
        repo.record(topup(amount: 300))
        repo.record(charge(amount: 100))

        XCTAssertEqual(repo.fetchAll().count, 3)
    }

    func testFetchAll_sortedByDateDescending() {
        repo.record(charge(amount: 50, daysAgo: 5))
        repo.record(charge(amount: 100, daysAgo: 1))
        repo.record(charge(amount: 200, daysAgo: 10))

        let all = repo.fetchAll()
        XCTAssertEqual(all.count, 3)
        // Should be sorted newest first
        XCTAssertEqual(all[0].amount, 100) // 1 day ago
        XCTAssertEqual(all[1].amount, 50)  // 5 days ago
        XCTAssertEqual(all[2].amount, 200) // 10 days ago
    }

    // MARK: - fetchCharges

    func testFetchCharges_filtersByDate() {
        repo.record(charge(amount: 50, daysAgo: 1))   // within 7 days
        repo.record(charge(amount: 100, daysAgo: 3))  // within 7 days
        repo.record(charge(amount: 200, daysAgo: 10)) // outside 7 days
        repo.record(topup(amount: 500, daysAgo: 0))   // topup, should be excluded

        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let charges = repo.fetchCharges(since: since)

        XCTAssertEqual(charges.count, 2)
    }

    func testFetchCharges_excludesTopups() {
        repo.record(topup(amount: 500, daysAgo: 0))
        repo.record(topup(amount: 300, daysAgo: 1))

        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let charges = repo.fetchCharges(since: since)

        XCTAssertEqual(charges.count, 0)
    }

    func testFetchCharges_emptyWhenNoData() {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let charges = repo.fetchCharges(since: since)
        XCTAssertTrue(charges.isEmpty)
    }

    // MARK: - Streak calculation

    func testCurrentStreak_noTransactions_returnsZero() {
        XCTAssertEqual(repo.currentStreak(), 0)
    }

    func testCurrentStreak_withRecentCharge_returnsZero() {
        // Charge today -> streak = 0
        repo.record(charge(amount: 50, daysAgo: 0))
        XCTAssertEqual(repo.currentStreak(), 0)
    }

    func testCurrentStreak_withOldCharge_countsCorrectly() {
        // Charge 3 days ago, topup today -> streak should be 3
        // (today, yesterday, day before yesterday = 3 clean days)
        repo.record(charge(amount: 50, daysAgo: 3))
        repo.record(topup(amount: 500, daysAgo: 0)) // non-charge tx to establish today

        let streak = repo.currentStreak()
        XCTAssertEqual(streak, 3, "3 days without charges (today, yesterday, day before)")
    }

    func testCurrentStreak_chargeYesterday_streakIsOne() {
        // Charge yesterday, topup today -> streak = 1 (only today is clean)
        repo.record(charge(amount: 50, daysAgo: 1))
        repo.record(topup(amount: 100, daysAgo: 0))

        XCTAssertEqual(repo.currentStreak(), 1)
    }

    func testCurrentStreak_onlyTopups_allDaysClean() {
        // Topups 5 days ago and today -> streak = 6 (day 0 through 5)
        repo.record(topup(amount: 500, daysAgo: 5))
        repo.record(topup(amount: 100, daysAgo: 0))

        let streak = repo.currentStreak()
        XCTAssertEqual(streak, 6, "All days from first tx to today should be clean")
    }

    func testCurrentStreak_intermittentCharges() {
        // Day 0: clean (topup), Day 1: clean, Day 2: charge -> streak = 2
        repo.record(charge(amount: 50, daysAgo: 2))
        repo.record(topup(amount: 100, daysAgo: 0))

        XCTAssertEqual(repo.currentStreak(), 2)
    }

    // MARK: - Edge cases

    func testFetchAll_emptyByDefault() {
        XCTAssertTrue(repo.fetchAll().isEmpty)
    }

    func testRecord_preservesAlarmID() {
        let tx = Transaction(type: .charge, amount: 50, alarmID: "alarm-123")
        repo.record(tx)

        let fetched = repo.fetchAll().first
        XCTAssertEqual(fetched?.alarmID, "alarm-123")
    }

    func testRecord_preservesNilAlarmID() {
        let tx = Transaction(type: .charge, amount: 50, alarmID: nil)
        repo.record(tx)

        let fetched = repo.fetchAll().first
        XCTAssertNil(fetched?.alarmID)
    }

    func testIsolation_separateSuites() {
        // Verify that our test UserDefaults suite is isolated
        let otherSuiteName = "test.txRepo.other.\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)!
        let otherRepo = TransactionRepository(defaults: otherDefaults)

        repo.record(charge(amount: 50))

        XCTAssertEqual(repo.fetchAll().count, 1)
        XCTAssertEqual(otherRepo.fetchAll().count, 0, "Different suites should be isolated")

        otherDefaults.removePersistentDomain(forName: otherSuiteName)
    }

    // MARK: - Concurrency

    func testConcurrentRecord_allTransactionsLanded() {
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { idx in
            let tx = Transaction(
                type: idx % 2 == 0 ? .charge : .topup,
                amount: Double(idx + 1)
            )
            self.repo.record(tx)
        }

        XCTAssertEqual(repo.fetchAll().count, iterations,
                       "All concurrently-recorded transactions must be persisted")
    }
}
