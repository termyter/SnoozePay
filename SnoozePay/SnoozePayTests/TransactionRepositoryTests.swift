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

    // MARK: - Refunded charges (issue #133)

    /// A snooze that fails to schedule is rolled back via a `topup` carrying
    /// `refundsTransactionID` pointing at the original charge. The streak must
    /// treat the day as clean — the user did not actually snooze, so penalising
    /// their streak would punish a permission/system failure they can't avoid.
    func testCurrentStreak_chargeRefundedSameDay_doesNotResetStreak() {
        // 5 days ago a charge was attempted and refunded; nothing else.
        let originalCharge = charge(amount: 50, daysAgo: 5)
        let refund = Transaction(
            type: .topup,
            amount: 50,
            createdAt: originalCharge.createdAt,
            refundsTransactionID: originalCharge.id
        )
        repo.record(originalCharge)
        repo.record(refund)

        // Streak should walk back to the day BEFORE the refunded charge
        // without halting on the refunded entry.
        let streak = repo.currentStreak()
        XCTAssertGreaterThanOrEqual(streak, 5,
            "Refunded charge must not interrupt the streak — the snooze never actually fired")
    }

    /// A real (non-refunded) charge alongside a refunded one still ends the
    /// streak on the real charge's day. Guards against the filter being too
    /// aggressive — only charges with a matching refund row are excluded.
    func testCurrentStreak_realChargePresent_stillResetsStreak() {
        let realCharge = charge(amount: 50, daysAgo: 0)
        let refundedCharge = charge(amount: 50, daysAgo: 1)
        let refund = Transaction(
            type: .topup,
            amount: 50,
            createdAt: refundedCharge.createdAt,
            refundsTransactionID: refundedCharge.id
        )
        repo.record(realCharge)
        repo.record(refundedCharge)
        repo.record(refund)

        XCTAssertEqual(repo.currentStreak(), 0,
            "Real charge today must end the streak even when an older charge was refunded")
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

    // MARK: - Corrupted persistence (issue #23)

    /// When stored JSON can't be decoded, the read must return `[]`
    /// without silently overwriting the corrupted blob — the raw bytes stay
    /// on disk so we can diagnose what got broken.
    func testFetchAll_corruptedJSON_returnsEmptyAndPreservesRawData() {
        let corruptBytes = Data("{ this is not valid json".utf8)
        testDefaults.set(corruptBytes, forKey: "stored_transactions")

        XCTAssertTrue(repo.fetchAll().isEmpty, "Decode failure yields empty list to caller")

        let onDisk = testDefaults.data(forKey: "stored_transactions")
        XCTAssertEqual(onDisk, corruptBytes,
                       "Corrupt JSON must remain untouched on disk for debugging")
    }

    func testFetchAll_corruptedJSON_repeatedReadDoesNotMutateStorage() {
        let corruptBytes = Data("not json".utf8)
        testDefaults.set(corruptBytes, forKey: "stored_transactions")

        _ = repo.fetchAll()
        _ = repo.fetchAll()
        _ = repo.fetchCharges(since: Date.distantPast)

        XCTAssertEqual(testDefaults.data(forKey: "stored_transactions"), corruptBytes,
                       "Reading corrupt data must never write back")
    }

    func testFetchAll_keyAbsent_returnsEmptyAndDoesNotCreateKey() {
        testDefaults.removeObject(forKey: "stored_transactions")

        XCTAssertTrue(repo.fetchAll().isEmpty)
        XCTAssertNil(testDefaults.data(forKey: "stored_transactions"),
                     "Read on missing key must not materialize an empty value")
    }

    /// After the user has acknowledged data loss via `clearCorruptState()`,
    /// the next record replaces the wiped slot with valid JSON. Before #72
    /// `record()` would silently clobber the corrupt blob from a partial
    /// in-memory snapshot — now it refuses until the lock is released.
    func testRecordAfterCorruption_overwritesWithValidData() {
        testDefaults.set(Data("garbage".utf8), forKey: "stored_transactions")

        // Trigger the lock by attempting a checked read.
        XCTAssertThrowsError(try repo.fetchAllChecked())
        XCTAssertTrue(repo.lastLoadFailed)

        // Before recovery the record must be refused to preserve diagnostics.
        XCTAssertFalse(repo.record(charge(amount: 1)),
                       "record() must be refused while the store is locked")

        repo.clearCorruptState()
        XCTAssertFalse(repo.lastLoadFailed)

        XCTAssertTrue(repo.record(charge(amount: 99)),
                      "record() must succeed once the lock is cleared")

        let all = repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.amount, 99)
    }

    // MARK: - Issue #72: surfaced decode failure + corrupt backup + persist lock

    func testFetchAllChecked_corruptedJSON_throwsDecodeFailure() {
        let corrupt = Data("definitely not json".utf8)
        testDefaults.set(corrupt, forKey: "stored_transactions")

        XCTAssertThrowsError(try repo.fetchAllChecked()) { error in
            guard case TransactionRepository.RepositoryError.decodeFailure = error else {
                XCTFail("Expected decodeFailure, got \(error)")
                return
            }
        }
        XCTAssertTrue(repo.lastLoadFailed,
                      "lastLoadFailed must latch on decode failure so writes refuse to clobber the corrupt blob")
    }

    func testFetchAllChecked_corruptedJSON_copiesBackupOnce() {
        let corrupt = Data("not json v1".utf8)
        testDefaults.set(corrupt, forKey: "stored_transactions")

        _ = try? repo.fetchAllChecked()

        XCTAssertEqual(testDefaults.data(forKey: TransactionRepository.corruptBackupKey), corrupt,
                       "First decode failure must snapshot the corrupt bytes for diagnosis")

        let differentCorrupt = Data("not json v2".utf8)
        testDefaults.set(differentCorrupt, forKey: "stored_transactions")
        _ = try? repo.fetchAllChecked()

        XCTAssertEqual(testDefaults.data(forKey: TransactionRepository.corruptBackupKey), corrupt,
                       "Backup must capture the FIRST failure, not the latest one")
    }

    func testRecord_whileStoreLocked_isRefused() {
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_transactions")
        _ = try? repo.fetchAllChecked()

        XCTAssertFalse(repo.record(charge(amount: 1)),
                       "record() must return false while the store is locked")
        XCTAssertEqual(testDefaults.data(forKey: "stored_transactions"), Data("corrupt".utf8),
                       "Locked store must not be overwritten by a partial snapshot")
    }

    func testClearCorruptState_releasesLockAndRemovesKey() {
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_transactions")
        _ = try? repo.fetchAllChecked()
        XCTAssertTrue(repo.lastLoadFailed)

        repo.clearCorruptState()

        XCTAssertFalse(repo.lastLoadFailed)
        XCTAssertNil(testDefaults.data(forKey: "stored_transactions"),
                     "clearCorruptState must wipe the live key (the diagnostic backup is a separate slot)")
    }

    /// On corrupted data, currentStreak() must not crash and must report 0
    /// (matching the new-user fallback) rather than returning a misleading value.
    func testCurrentStreak_corruptedJSON_returnsZero() {
        testDefaults.set(Data("nope".utf8), forKey: "stored_transactions")

        XCTAssertEqual(repo.currentStreak(), 0)
    }

    // MARK: - Issue #117: caller-supplied streak variant

    /// `currentStreak(from:)` lets callers that already paid the cost of a
    /// checked read share the result so a transient decode glitch can't
    /// produce a banner + a contradicting "0 days" elsewhere on the same
    /// screen (issue #117).
    func testCurrentStreakFromTransactions_matchesInternalImplementation() {
        repo.record(charge(amount: 50, daysAgo: 3))
        repo.record(topup(amount: 500, daysAgo: 0))

        let allTransactions = repo.fetchAll()

        XCTAssertEqual(repo.currentStreak(from: allTransactions), repo.currentStreak(),
                       "Pre-loaded variant must match the internal-read variant on identical data")
        XCTAssertEqual(repo.currentStreak(from: allTransactions), 3)
    }

    func testCurrentStreakFromTransactions_emptyArray_returnsZero() {
        XCTAssertEqual(repo.currentStreak(from: []), 0)
    }

    /// Even if the persisted store is corrupt, passing a healthy in-memory
    /// snapshot to `currentStreak(from:)` must yield the right answer —
    /// proves the pure variant doesn't secretly re-read.
    func testCurrentStreakFromTransactions_ignoresPersistedStore() {
        testDefaults.set(Data("garbage".utf8), forKey: "stored_transactions")

        let calendar = Calendar.current
        let snapshot = [
            Transaction(type: .charge, amount: 50,
                        createdAt: calendar.date(byAdding: .day, value: -2, to: Date())!),
            Transaction(type: .topup, amount: 100, createdAt: Date())
        ]
        XCTAssertEqual(repo.currentStreak(from: snapshot), 2,
                       "Pre-loaded variant must compute against the supplied list, not re-read storage")
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
