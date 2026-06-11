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
        let alarm = makeAlarm(name: "Original")
        repo.save(alarm)

        repo.save(alarm.with(name: "Updated"))

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

    /// After the user has acknowledged data loss via `clearCorruptState()`,
    /// the next save replaces the wiped slot with valid JSON. Before #72
    /// `save()` would silently overwrite corrupt bytes from a partial
    /// in-memory snapshot — now it refuses until the lock is released.
    func testSaveAfterCorruption_overwritesWithValidData() {
        testDefaults.set(Data("garbage".utf8), forKey: "stored_alarms")

        // Trigger the lock by attempting a checked read.
        XCTAssertThrowsError(try repo.fetchAllChecked())
        XCTAssertTrue(repo.lastLoadFailed)

        // Before recovery the save must be refused so we don't lose the
        // corrupt blob behind a partial snapshot.
        let blocked = makeAlarm(name: "Blocked")
        XCTAssertFalse(repo.save(blocked),
                       "Save must be refused while the store is locked")

        // User acknowledges the data loss via the recovery flow.
        repo.clearCorruptState()
        XCTAssertFalse(repo.lastLoadFailed)

        let alarm = makeAlarm(name: "Recovery")
        XCTAssertTrue(repo.save(alarm), "Save must succeed once the lock is cleared")

        let stored = repo.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, "Recovery")
    }

    // MARK: - Issue #72: surfaced decode failure + corrupt backup + persist lock

    func testFetchAllChecked_corruptedJSON_throwsDecodeFailure() {
        let corrupt = Data("definitely not json".utf8)
        testDefaults.set(corrupt, forKey: "stored_alarms")

        XCTAssertThrowsError(try repo.fetchAllChecked()) { error in
            guard case AlarmRepository.RepositoryError.decodeFailure = error else {
                XCTFail("Expected decodeFailure, got \(error)")
                return
            }
        }
        XCTAssertTrue(repo.lastLoadFailed,
                      "lastLoadFailed must latch on decode failure so writes refuse to clobber the corrupt blob")
    }

    func testFetchAllChecked_corruptedJSON_copiesBackupOnce() {
        let corrupt = Data("not json v1".utf8)
        testDefaults.set(corrupt, forKey: "stored_alarms")

        _ = try? repo.fetchAllChecked()

        XCTAssertEqual(testDefaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt,
                       "First decode failure must snapshot the corrupt bytes for diagnosis")

        // Subsequent failures must NOT overwrite the original snapshot — we
        // want the first observed corruption preserved, not a stale view.
        let differentCorrupt = Data("not json v2".utf8)
        testDefaults.set(differentCorrupt, forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked()

        XCTAssertEqual(testDefaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt,
                       "Backup must capture the FIRST failure, not the latest one")
    }

    func testSave_whileStoreLocked_isRefused() {
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked() // arms the lock

        let alarm = makeAlarm(name: "Should not land")
        XCTAssertFalse(repo.save(alarm),
                       "save() must return false while lastLoadFailed == true")

        // The corrupt blob on disk MUST be untouched — that's the whole point.
        XCTAssertEqual(testDefaults.data(forKey: "stored_alarms"), Data("corrupt".utf8),
                       "Locked store must not be overwritten by a partial snapshot")
    }

    func testDelete_whileStoreLocked_isRefused() {
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked()

        XCTAssertFalse(repo.delete(id: UUID()),
                       "delete() must return false while the store is locked")
        XCTAssertEqual(testDefaults.data(forKey: "stored_alarms"), Data("corrupt".utf8))
    }

    func testSetEnabled_whileStoreLocked_isRefused() {
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked()

        XCTAssertFalse(repo.setEnabled(true, id: UUID()),
                       "setEnabled() must return false while the store is locked")
    }

    func testClearCorruptState_releasesLockAndRemovesKey() {
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked()
        XCTAssertTrue(repo.lastLoadFailed)

        repo.clearCorruptState()

        XCTAssertFalse(repo.lastLoadFailed)
        XCTAssertNil(testDefaults.data(forKey: "stored_alarms"),
                     "clearCorruptState must wipe the live key (the diagnostic backup is a separate slot)")
    }

    func testSuccessfulFetchAfterTransientFailure_clearsLock() {
        // Arm the lock with corrupt bytes, then replace them with valid JSON
        // (e.g. a different process recovered) — a subsequent successful
        // checked read must clear the lock so writes proceed.
        testDefaults.set(Data("corrupt".utf8), forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked()
        XCTAssertTrue(repo.lastLoadFailed)

        let emptyAlarmsData = (try? JSONEncoder().encode([Alarm]())) ?? Data()
        testDefaults.set(emptyAlarmsData, forKey: "stored_alarms")
        _ = try? repo.fetchAllChecked()

        XCTAssertFalse(repo.lastLoadFailed,
                       "A subsequent successful read must clear the lock")
    }

    // MARK: - Coverage gaps surfaced by pr-test-analyzer (#32)

    /// `save` is upsert: re-saving the same id MUST replace in place rather
    /// than appending a duplicate. The previous `testSave_updatesExistingAlarm`
    /// covers data-replacement; this one specifically pins down the array-shape
    /// invariant so a future regression that switched to "always append" would
    /// fail loudly here even if the last-write-wins on the field comparison.
    func testSave_upsertsExistingAlarmInPlace() {
        let alarm = makeAlarm(name: "v1")
        repo.save(alarm)
        repo.save(alarm) // same id, second time
        repo.save(alarm.with(name: "v2")) // changed copy, same id

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
                self.repo.save(alarm.with(enabled: false))
            }
        }

        XCTAssertEqual(repo.fetchAll().count, 1, "Concurrent ops must not duplicate or drop the alarm")
        let final = repo.fetch(id: alarm.id)
        XCTAssertNotNil(final)
        // Final state must match one of the writers, not torn (penaltyAmount preserved).
        XCTAssertEqual(final?.penaltyAmount, alarm.penaltyAmount)
    }

    // MARK: - Issue #117: fetchChecked(id:) surfaces decode failures

    /// Happy path: a known id returns the matching alarm via the checked variant.
    func testFetchCheckedById_returnsAlarmWhenPresent() throws {
        let alarm = makeAlarm(name: "Found")
        repo.save(alarm)

        let fetched = try repo.fetchChecked(id: alarm.id)
        XCTAssertEqual(fetched?.id, alarm.id)
    }

    /// Happy path: a missing id returns nil rather than throwing — the
    /// decode succeeded, the alarm just isn't there. Callers distinguish
    /// "decode failed" (catch) from "doesn't exist" (nil).
    func testFetchCheckedById_returnsNilWhenAbsent() throws {
        let fetched = try repo.fetchChecked(id: UUID())
        XCTAssertNil(fetched)
    }

    /// Sad path: a corrupt blob throws `decodeFailure` instead of silently
    /// returning nil — without this, AppDelegate / AlarmFiringCoordinator
    /// would treat corruption as "alarm not found" and bail with no
    /// diagnostic trail (issue #117).
    func testFetchCheckedById_corruptedJSON_throwsDecodeFailure() {
        testDefaults.set(Data("not json".utf8), forKey: "stored_alarms")

        XCTAssertThrowsError(try repo.fetchChecked(id: UUID())) { error in
            guard case AlarmRepository.RepositoryError.decodeFailure = error else {
                XCTFail("Expected decodeFailure, got \(error)")
                return
            }
        }
        XCTAssertTrue(repo.lastLoadFailed,
                      "Checked single-id fetch must arm the persistence lock just like fetchAllChecked")
    }
}
