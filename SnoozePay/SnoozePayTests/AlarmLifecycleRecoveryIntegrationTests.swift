import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
@MainActor
final class AlarmLifecycleRecoveryIntegrationTests: XCTestCase {
    func testOrdinaryHealthyWrongTypeAndDuplicateCivilSnapshotsRefuseRecoveryWithoutChangingAnyEvidence() throws {
        for wrongType in [true, false] {
            for priorFailure in [false, true] {
                let fixture = try OccurrenceVMFixture()
                defer { fixture.close() }
                let ticket = try fixture.recoveryTrackedTicket()
                let native = LifecycleNativeInventory(entries: [NativeOccurrenceSnapshot(
                    id: fixture.alarm.id, phase: .scheduled,
                    weekly: .init(hour: 6, minute: 40, mondayFirstDays: [0, 2])
                )])
                let scheduler = makeScheduler(fixture, native: native)
                let repository = AlarmRepository(defaults: fixture.defaults, scheduler: scheduler)
                let backup = Data("pre-existing diagnostic evidence".utf8)
                fixture.defaults.set(backup, forKey: AlarmRepository.corruptBackupKey)
                if priorFailure {
                    fixture.defaults.set(Data("prime the failed-read flag".utf8), forKey: "stored_alarms")
                    XCTAssertThrowsError(try repository.fetchAllChecked())
                }
                let civil = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
                if wrongType {
                    fixture.defaults.set("unknown legacy representation", forKey: "stored_alarms")
                } else {
                    fixture.defaults.set(try JSONEncoder().encode([civil, civil]), forKey: "stored_alarms")
                }
                // A separate reader demonstrates the ordinary/strict mismatch
                // without resetting this repository instance's prior flag.
                let observer = AlarmRepository(defaults: fixture.defaults, scheduler: scheduler)
                XCTAssertEqual(try observer.fetchAllChecked().count, wrongType ? 0 : 2)
                XCTAssertThrowsError(try observer.fetchOccurrenceFinishAlarms())
                XCTAssertEqual(repository.lastLoadFailed, priorFailure)
                let before = domain(fixture)
                let inventory = native.entries

                XCTAssertThrowsError(try repository.clearCorruptState().get()) {
                    XCTAssertEqual($0 as? AlarmRecoveryError, .alarmDataUnavailable)
                }

                XCTAssertEqual(domain(fixture), before)
                XCTAssertEqual(repository.lastLoadFailed, priorFailure)
                XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), backup)
                XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id), ticket)
                XCTAssertEqual(native.entries, inventory)
                XCTAssertEqual(native.registeredReads, 0)
                XCTAssertEqual(native.occurrenceReads, 0)
                XCTAssertTrue(native.cancelled.isEmpty)
                XCTAssertTrue(native.stopped.isEmpty)
                XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
            }
        }
    }

    func testHealthyUniqueCivilAndAbsentStoresRemainNonDestructiveEvenWithPendingFinishAndNativeRegistrations() throws {
        for absent in [false, true] {
            let fixture = try OccurrenceVMFixture()
            defer { fixture.close() }
            let ticket = try fixture.recoveryTrackedTicket()
            let current = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
            if absent {
                fixture.defaults.removeObject(forKey: "stored_alarms")
            } else {
                XCTAssertTrue(fixture.seedRepository.save(current))
            }
            let native = LifecycleNativeInventory(entries: [NativeOccurrenceSnapshot(
                id: current.id, phase: .scheduled,
                weekly: .init(hour: 6, minute: 40, mondayFirstDays: [0, 2])
            )])
            let repository = AlarmRepository(
                defaults: fixture.defaults, scheduler: makeScheduler(fixture, native: native)
            )
            let before = domain(fixture)
            let inventory = native.entries

            try repository.clearCorruptState().get()

            XCTAssertEqual(domain(fixture), before)
            XCTAssertFalse(repository.lastLoadFailed)
            XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: current.id), ticket)
            XCTAssertEqual(native.entries, inventory)
            XCTAssertEqual(native.registeredReads, 0)
            XCTAssertTrue(native.cancelled.isEmpty)
            XCTAssertTrue(native.stopped.isEmpty)
        }
    }

    func testMalformedCivilRecoverySweepsAllNativeIDsBeforeEraseAndKeepsTheTicketForQuietMissingRowFinish() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let derived = AlarmKitScheduler.snoozeID(for: fixture.alarm.id)
        let unrelated = UUID()
        let native = LifecycleNativeInventory(entries: [
            NativeOccurrenceSnapshot(id: fixture.alarm.id, phase: .scheduled,
                                     weekly: .init(hour: 6, minute: 40, mondayFirstDays: [0, 2])),
            NativeOccurrenceSnapshot(id: derived, phase: .countdown, weekly: nil),
            NativeOccurrenceSnapshot(id: unrelated, phase: .alerting, weekly: nil)
        ])
        native.blockedCancellation = [unrelated]
        let scheduler = makeScheduler(fixture, native: native)
        let repository = AlarmRepository(defaults: fixture.defaults, scheduler: scheduler)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.alarm))
                                   as? [String: Any])
        payload["clockTime"] = ["hour": 24, "minute": 0]
        let corrupt = try JSONSerialization.data(withJSONObject: [payload], options: [.sortedKeys])
        fixture.defaults.set(corrupt, forKey: "stored_alarms")
        let sessions = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let ledger = try fixture.ledger.fetchAllChecked().map(\.id)
        native.onRegisteredRead = {
            XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), corrupt,
                           "The checked empty native read must precede removal of the corrupt alarm key")
        }

        XCTAssertThrowsError(try repository.clearCorruptState().get()) {
            XCTAssertEqual($0 as? AlarmRecoveryError, .registrationsRemain)
        }

        XCTAssertEqual(Set(native.cancelled), [fixture.alarm.id, derived, unrelated])
        XCTAssertEqual(native.cancelled.count, 3)
        XCTAssertEqual(native.entries.map(\.id), [unrelated])
        XCTAssertEqual(native.registeredReads, 2)
        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), corrupt)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessions)
        XCTAssertTrue(repository.lastLoadFailed)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)

        native.blockedCancellation = []
        try repository.clearCorruptState().get()

        XCTAssertEqual(Array(native.cancelled.dropFirst(3)), [unrelated])
        XCTAssertEqual(native.registeredReads, 4)
        XCTAssertTrue(native.entries.isEmpty)
        XCTAssertNil(fixture.defaults.object(forKey: "stored_alarms"))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessions)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id), ticket)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        let service = AlarmOccurrenceRecovery(repository: repository, scheduler: scheduler,
                                              sessions: fixture.store(), wakes: fixture.wakes)
        XCTAssertEqual(try service.pendingFinishes(), [.init(ticket: ticket, alarmName: nil)])

        XCTAssertEqual(service.resume(ticket), .success(.completedNow))

        XCTAssertNil(fixture.defaults.object(forKey: "stored_alarms"),
                     "Quiet completion must not recreate the removed row")
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(native.cancelled.count, 4, "Quiet proof performs no additional native cancellation")
        XCTAssertTrue(native.stopped.isEmpty)
        XCTAssertEqual(fixture.wallet.balance, 150)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().map(\.id), ledger)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testRecoveryBetweenQuietVerificationAndCommitCannotResurrectTheCapturedCivilOneShot() throws {
        let fixture = try OccurrenceVMFixture(oneShot: true)
        defer { fixture.close() }
        let current = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        XCTAssertTrue(fixture.seedRepository.save(current))
        let ticket = try fixture.recoveryTrackedTicket()
        let native = LifecycleNativeInventory(entries: [NativeOccurrenceSnapshot(
            id: current.id, phase: .scheduled, weekly: nil
        )])
        let repository = AlarmRepository(defaults: fixture.defaults, scheduler: makeScheduler(fixture, native: native))
        let verifier = RecoveryTestVerifier()
        let corrupt = Data("concurrent alarm-store corruption".utf8)
        verifier.onVerify = {
            fixture.defaults.set(corrupt, forKey: "stored_alarms")
            if case .failure(let error) = repository.clearCorruptState() {
                XCTFail("Expected checked native recovery to commit before verification returns: \(error)")
            }
        }
        let service = AlarmOccurrenceRecovery(repository: repository, scheduler: verifier,
                                              sessions: fixture.store(), wakes: fixture.wakes)
        let sessions = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        XCTAssertEqual(service.resume(ticket), .failure(.ownershipUnavailable))

        XCTAssertEqual(verifier.tickets, [ticket])
        XCTAssertNil(fixture.defaults.object(forKey: "stored_alarms"))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessions)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: current.id), ticket)
        XCTAssertTrue(native.entries.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertEqual(fixture.wallet.balance, 150)
    }

    private func makeScheduler(_ fixture: OccurrenceVMFixture, native: LifecycleNativeInventory) -> AlarmScheduler {
        AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: native.backend,
                       snoozeSessions: fixture.store())
    }

    private func domain(_ fixture: OccurrenceVMFixture) -> NSDictionary {
        NSDictionary(dictionary: fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
    }
}
