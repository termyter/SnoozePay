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
        repo.setEnabled(false, id: UUID())
        XCTAssertEqual(repo.fetchAll().count, 0)
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
