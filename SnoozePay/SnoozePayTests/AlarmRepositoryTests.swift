import XCTest
@testable import SnoozePay

/// Unit tests for AlarmRepository — persistence and thread-safety.
final class AlarmRepositoryTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmRepo.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAlarm(name: String = "Test") -> Alarm {
        Alarm(name: name, penaltyAmount: 50)
    }

    /// Build an alarm at a deterministic time-of-day so sort/upsert tests
    /// don't accidentally rely on `Date()` resolution within `setUp`.
    private func makeAlarm(hour: Int, minute: Int = 0, name: String) -> Alarm {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute))!
        return Alarm(time: date, name: name, penaltyAmount: 50)
    }

    // MARK: - Basic CRUD

    func testSave_persistsAlarm() {
        let alarm = makeAlarm()
        repo.save(alarm)

        XCTAssertEqual(repo.fetchAll().count, 1)
        XCTAssertEqual(repo.fetch(id: alarm.id)?.id, alarm.id)
    }

    func testSave_updatesExistingAlarm() {
        var alarm = makeAlarm(name: "Original")
        repo.save(alarm)

        alarm.name = "Updated"
        repo.save(alarm)

        XCTAssertEqual(repo.fetchAll().count, 1)
        XCTAssertEqual(repo.fetch(id: alarm.id)?.name, "Updated")
    }

    func testDelete_removesAlarm() {
        let alarm = makeAlarm()
        repo.save(alarm)
        repo.delete(id: alarm.id)

        XCTAssertNil(repo.fetch(id: alarm.id))
        XCTAssertEqual(repo.fetchAll().count, 0)
    }

    func testSetEnabled_togglesFlag() {
        let alarm = makeAlarm()
        repo.save(alarm)

        repo.setEnabled(false, id: alarm.id)
        XCTAssertEqual(repo.fetch(id: alarm.id)?.enabled, false)

        repo.setEnabled(true, id: alarm.id)
        XCTAssertEqual(repo.fetch(id: alarm.id)?.enabled, true)
    }

    func testSetEnabled_unknownIDIsNoOp() {
        let didUpdate = repo.setEnabled(false, id: UUID())
        XCTAssertFalse(didUpdate, "setEnabled must report failure when no alarm matches the id")
        XCTAssertEqual(repo.fetchAll().count, 0)
    }

    func testSetEnabled_existingIDReturnsTrueAndPersists() {
        let alarm = makeAlarm()
        repo.save(alarm)

        let didUpdate = repo.setEnabled(false, id: alarm.id)

        XCTAssertTrue(didUpdate, "setEnabled must report success when the alarm exists")
        XCTAssertEqual(repo.fetch(id: alarm.id)?.enabled, false, "Persistence must reflect the new flag")
    }

    // MARK: - Concurrency

    func testConcurrentSave_allAlarmsLanded() {
        let iterations = 50
        let alarms = (0..<iterations).map { makeAlarm(name: "alarm-\($0)") }

        DispatchQueue.concurrentPerform(iterations: iterations) { idx in
            self.repo.save(alarms[idx])
        }

        let stored = repo.fetchAll()
        XCTAssertEqual(stored.count, iterations,
                       "All concurrently-saved alarms must be persisted")

        let storedIDs = Set(stored.map { $0.id })
        let expectedIDs = Set(alarms.map { $0.id })
        XCTAssertEqual(storedIDs, expectedIDs)
    }

    func testConcurrentSaveAndDelete_consistent() {
        // Pre-populate half the alarms so we can delete them while saving new ones.
        let toDelete = (0..<25).map { makeAlarm(name: "del-\($0)") }
        let toAdd = (0..<25).map { makeAlarm(name: "add-\($0)") }
        toDelete.forEach { repo.save($0) }

        let deleteIDs = Set(toDelete.map { $0.id })

        DispatchQueue.concurrentPerform(iterations: 50) { idx in
            if idx < 25 {
                self.repo.delete(id: toDelete[idx].id)
            } else {
                self.repo.save(toAdd[idx - 25])
            }
        }

        let stored = repo.fetchAll()
        let storedIDs = Set(stored.map { $0.id })

        XCTAssertTrue(storedIDs.isDisjoint(with: deleteIDs),
                      "No deleted ID may remain in the store")
        let addedIDs = Set(toAdd.map { $0.id })
        XCTAssertTrue(addedIDs.isSubset(of: storedIDs),
                      "All added alarms must be persisted")
    }

    // MARK: - Corrupted persistence (issue #23)

    /// When the stored JSON can't be decoded, the read must return `[]`
    /// without silently overwriting the corrupted blob — the raw bytes stay
    /// on disk so we can diagnose what got broken.
    func testFetchAll_corruptedJSON_returnsEmptyAndPreservesRawData() {
        let corruptBytes = Data("{ this is not valid json".utf8)
        testDefaults.set(corruptBytes, forKey: "stored_alarms")

        XCTAssertEqual(repo.fetchAll(), [], "Decode failure should yield empty list to caller")

        let onDisk = testDefaults.data(forKey: "stored_alarms")
        XCTAssertEqual(onDisk, corruptBytes,
                       "Corrupt JSON must remain untouched on disk for debugging")
    }

    /// fetchAll() called twice on corrupted data must NOT have overwritten
    /// the stored blob between calls — the second fetch sees the same raw bytes.
    func testFetchAll_corruptedJSON_repeatedReadDoesNotMutateStorage() {
        let corruptBytes = Data("not json".utf8)
        testDefaults.set(corruptBytes, forKey: "stored_alarms")

        _ = repo.fetchAll()
        _ = repo.fetchAll()

        XCTAssertEqual(testDefaults.data(forKey: "stored_alarms"), corruptBytes,
                       "Reading corrupt data must never write back")
    }

    /// Absent key (brand-new install) is the legitimate empty state.
    func testFetchAll_keyAbsent_returnsEmptyAndDoesNotCreateKey() {
        testDefaults.removeObject(forKey: "stored_alarms")

        XCTAssertEqual(repo.fetchAll(), [])
        XCTAssertNil(testDefaults.data(forKey: "stored_alarms"),
                     "Read on missing key must not materialize an empty value")
    }

    /// After a successful save the previously-corrupted bytes are replaced
    /// with valid JSON — proves persist() is the only path that can clobber
    /// corrupt data, and only with a healthy snapshot.
    func testSaveAfterCorruption_overwritesWithValidData() {
        testDefaults.set(Data("garbage".utf8), forKey: "stored_alarms")

        let alarm = makeAlarm(name: "Recovery")
        repo.save(alarm)

        let stored = repo.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, "Recovery")
    }

    // MARK: - Coverage gaps surfaced by pr-test-analyzer (#32)

    /// `save` is upsert: re-saving the same id MUST replace in place rather
    /// than appending a duplicate. The previous `testSave_updatesExistingAlarm`
    /// covers data-replacement; this one specifically pins down the array-shape
    /// invariant so a future regression that switched to "always append" would
    /// fail loudly here even if the last-write-wins on the field comparison.
    func testSave_upsertsExistingAlarmInPlace() {
        var alarm = makeAlarm(name: "v1")
        repo.save(alarm)
        repo.save(alarm) // same id, second time
        alarm.name = "v2"
        repo.save(alarm) // mutated, same id

        let stored = repo.fetchAll()
        XCTAssertEqual(stored.count, 1, "Repeated saves of the same id must NOT duplicate the alarm")
        XCTAssertEqual(stored.first?.name, "v2")
    }

    /// `fetchAll()` must return alarms sorted by `time` ascending so the list UI
    /// renders earliest-first. Without an explicit assertion the natural insert
    /// order would mask a regression that dropped the `sorted` call in `readAll`.
    func testFetchAll_sortsByTime() {
        let late = makeAlarm(hour: 22, name: "Late")
        let early = makeAlarm(hour: 6, name: "Early")
        let mid = makeAlarm(hour: 12, name: "Mid")

        // Insert out of order to ensure result depends on sort, not insertion order.
        repo.save(late)
        repo.save(early)
        repo.save(mid)

        let names = repo.fetchAll().map(\.name)
        XCTAssertEqual(names, ["Early", "Mid", "Late"],
                       "fetchAll must order alarms by time ascending")
    }

    /// Earlier tests cover preservation of corrupt bytes on disk. This one nails
    /// the caller-visible contract: a single `fetchAll()` against syntactically
    /// invalid JSON returns `[]` silently — no crash, no rethrow, no partial list.
    /// Listed explicitly in #32 as an acceptance-criteria bullet.
    func testCorruptJSONInDefaults_returnsEmptyArray() {
        testDefaults.set(Data("totally not json {".utf8), forKey: "stored_alarms")
        XCTAssertEqual(repo.fetchAll(), [])
    }

    func testConcurrentToggleVsSave_finalStateIsConsistent() {
        // Race a setEnabled(true) loop against save(disabledClone) on the same id.
        // On the buggy code, save() does fetch+upsert without serialization — the
        // last write seen by readers can be a torn merge of two threads' snapshots.
        // With the queue, every reader observes one of the two writers' Alarm verbatim:
        // either enabled=true (from setEnabled) or enabled=false (from the save clone).
        let alarm = makeAlarm()
        repo.save(alarm)

        DispatchQueue.concurrentPerform(iterations: 200) { idx in
            if idx % 2 == 0 {
                self.repo.setEnabled(true, id: alarm.id)
            } else {
                var disabled = alarm
                disabled.enabled = false
                self.repo.save(disabled)
            }
        }

        XCTAssertEqual(repo.fetchAll().count, 1, "Concurrent ops must not duplicate or drop the alarm")
        let final = repo.fetch(id: alarm.id)
        XCTAssertNotNil(final)
        // Final state must match one of the writers, not torn (penaltyAmount preserved).
        XCTAssertEqual(final?.penaltyAmount, alarm.penaltyAmount)
    }
}
