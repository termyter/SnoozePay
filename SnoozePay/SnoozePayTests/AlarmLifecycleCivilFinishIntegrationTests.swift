import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
@MainActor
final class AlarmCivilFinishLifecycleTests: XCTestCase {
    func testSameDateCivilEditRefusesStaleNormalFinishBeforeTicketOrNativeMutationAndFreshEditCanFinish() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let captured = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        let current = fixture.alarm.with(clockTime: TimeOfDay(hour: 8, minute: 25))
        XCTAssertEqual(captured.time, current.time)
        XCTAssertNotEqual(captured.clockTime, current.clockTime)
        XCTAssertTrue(fixture.seedRepository.save(current))
        let stale = fixture.model(captured)
        let before = domain(fixture)

        XCTAssertEqual(stale.dismiss(), .failure(.ownershipUnavailable))

        XCTAssertEqual(domain(fixture), before)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: current.id))
        assertNoMutation(fixture)
        XCTAssertEqual(try fixture.repository.fetchChecked(id: current.id), current)
        XCTAssertEqual(fixture.model(current).dismiss(), .success(.completedNow))
        let request = try XCTUnwrap(fixture.backend.occurrenceFinishRequests.last)
        XCTAssertEqual(request.weekly?.hour, 8)
        XCTAssertEqual(request.weekly?.minute, 25)
        XCTAssertEqual(request.weekly?.mondayFirstDays, [0, 2])
        XCTAssertEqual(try fixture.repository.fetchChecked(id: current.id), current)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testSameDateLegacyAndExplicitCivilAuthorityCannotBorrowEachOthersNormalFinish() throws {
        for capturedIsCivil in [false, true] {
            let fixture = try OccurrenceVMFixture()
            defer { fixture.close() }
            let legacy = fixture.alarm
            let civil = fixture.alarm.with(clockTime: TimeOfDay(from: legacy.time))
            XCTAssertNil(legacy.clockTime)
            XCTAssertNotNil(civil.clockTime)
            XCTAssertEqual(legacy.time, civil.time)
            let captured = capturedIsCivil ? civil : legacy
            let current = capturedIsCivil ? legacy : civil
            XCTAssertTrue(fixture.seedRepository.save(current))
            let model = fixture.model(captured)
            let before = domain(fixture)

            XCTAssertEqual(model.dismiss(), .failure(.ownershipUnavailable))

            XCTAssertEqual(domain(fixture), before)
            XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: current.id))
            XCTAssertEqual(try fixture.repository.fetchChecked(id: current.id), current)
            assertNoMutation(fixture)
        }
    }

    func testQuietFinishUsesCurrentCivilClockForRealReadOnlyNativeProofWithoutChangingCompatibilityDate() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let current = fixture.alarm.with(clockTime: TimeOfDay(hour: 8, minute: 25))
        XCTAssertEqual(current.time, fixture.alarm.time)
        XCTAssertTrue(fixture.seedRepository.save(current))
        let ticket = try fixture.recoveryTrackedTicket()
        let native = LifecycleNativeInventory(entries: [NativeOccurrenceSnapshot(
            id: current.id, phase: .scheduled,
            weekly: .init(hour: 8, minute: 25, mondayFirstDays: [0, 2])
        )])
        let service = recovery(fixture, native: native)
        let alarmBytes = fixture.defaults.data(forKey: "stored_alarms")
        let ledger = try fixture.ledger.fetchAllChecked().map(\.id)

        XCTAssertEqual(service.resume(ticket), .success(.completedNow))

        XCTAssertGreaterThan(native.occurrenceReads, 0)
        XCTAssertTrue(native.cancelled.isEmpty)
        XCTAssertTrue(native.stopped.isEmpty)
        XCTAssertEqual(native.entries.first?.weekly?.hour, 8)
        XCTAssertEqual(native.entries.first?.weekly?.minute, 25)
        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), alarmBytes)
        XCTAssertEqual(try fixture.repository.fetchChecked(id: current.id), current)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: current.id))
        XCTAssertEqual(fixture.wallet.balance, 150)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().map(\.id), ledger)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testQuietReadOnlyProofCannotCommitOrOverwriteAnInterveningSameDateCivilEdit() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let captured = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        let changed = fixture.alarm.with(clockTime: TimeOfDay(hour: 8, minute: 25))
        XCTAssertTrue(fixture.seedRepository.save(captured))
        let ticket = try fixture.recoveryTrackedTicket()
        let native = LifecycleNativeInventory(entries: [NativeOccurrenceSnapshot(
            id: captured.id, phase: .scheduled,
            weekly: .init(hour: 6, minute: 40, mondayFirstDays: [0, 2])
        )])
        native.onOccurrenceRead = { XCTAssertTrue(fixture.seedRepository.save(changed)) }
        let service = recovery(fixture, native: native)
        let sessions = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let ledger = try fixture.ledger.fetchAllChecked().map(\.id)

        XCTAssertEqual(service.resume(ticket), .failure(.ownershipUnavailable))

        XCTAssertGreaterThan(native.occurrenceReads, 0)
        XCTAssertTrue(native.cancelled.isEmpty)
        XCTAssertTrue(native.stopped.isEmpty)
        XCTAssertEqual(try fixture.repository.fetchChecked(id: changed.id), changed)
        XCTAssertEqual(changed.time, captured.time)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), sessions)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: changed.id), ticket)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().map(\.id), ledger)
        XCTAssertEqual(fixture.wallet.balance, 150)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
    }

    func testQuietOneShotPersistOnlyDisablePreservesCivilClockAndMixedRepositorySort() throws {
        let fixture = try OccurrenceVMFixture(oneShot: true)
        defer { fixture.close() }
        let nine = try XCTUnwrap(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
                                                      of: fixture.alarm.time))
        let seven = try XCTUnwrap(Calendar.current.date(bySettingHour: 7, minute: 0, second: 0,
                                                       of: fixture.alarm.time))
        let current = fixture.alarm.with(time: nine, clockTime: TimeOfDay(hour: 6, minute: 0))
        let legacy = Alarm(time: seven, name: "Legacy seven")
        let later = Alarm(time: seven, clockTime: TimeOfDay(hour: 8, minute: 0), name: "Civil eight")
        fixture.defaults.set(try JSONEncoder().encode([later, legacy, current]), forKey: "stored_alarms")
        XCTAssertEqual(try fixture.repository.fetchOccurrenceFinishAlarms().map(\.id),
                       [current.id, legacy.id, later.id])
        let ticket = try fixture.recoveryTrackedTicket()
        let native = LifecycleNativeInventory()

        XCTAssertEqual(recovery(fixture, native: native).resume(ticket), .success(.completedNow))

        let rows = try fixture.repository.fetchOccurrenceFinishAlarms()
        XCTAssertEqual(rows.map(\.id), [current.id, legacy.id, later.id])
        XCTAssertEqual(rows.first, current.with(enabled: false))
        XCTAssertEqual(rows.first?.clockTime, TimeOfDay(hour: 6, minute: 0))
        XCTAssertEqual(rows.first?.time, nine)
        XCTAssertEqual(rows.first { $0.id == legacy.id }, legacy)
        XCTAssertNil(rows.first { $0.id == legacy.id }?.clockTime)
        XCTAssertEqual(rows.first { $0.id == later.id }, later)
        XCTAssertTrue(native.cancelled.isEmpty)
        XCTAssertTrue(native.stopped.isEmpty)
        assertNoMutation(fixture)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testPersistOnlyOneShotRefusesSameDateClockChangeAndDoesNotAdoptAClockForLegacyDisable() throws {
        let fixture = try OccurrenceVMFixture(oneShot: true)
        defer { fixture.close() }
        let captured = fixture.alarm.with(clockTime: TimeOfDay(hour: 6, minute: 40))
        let changed = fixture.alarm.with(clockTime: TimeOfDay(hour: 8, minute: 25))
        XCTAssertTrue(fixture.seedRepository.save(changed))
        let before = domain(fixture)

        XCTAssertThrowsError(try fixture.repository.persistFinishedOneShot(captured)) {
            XCTAssertEqual($0 as? AlarmOccurrenceFinishError, .ownershipUnavailable)
        }

        XCTAssertEqual(domain(fixture), before)
        XCTAssertTrue(fixture.seedRepository.save(fixture.alarm))
        try fixture.repository.persistFinishedOneShot(fixture.alarm)
        let disabled = try XCTUnwrap(fixture.repository.fetchChecked(id: fixture.alarm.id))
        XCTAssertEqual(disabled, fixture.alarm.with(enabled: false))
        XCTAssertNil(disabled.clockTime)
        XCTAssertEqual(disabled.time, fixture.alarm.time)
        assertNoMutation(fixture)
    }

    private func recovery(_ fixture: OccurrenceVMFixture, native: LifecycleNativeInventory) -> AlarmOccurrenceRecovery {
        AlarmOccurrenceRecovery(
            repository: fixture.repository,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: native.backend,
                                      snoozeSessions: fixture.store()),
            sessions: fixture.store(), wakes: fixture.wakes
        )
    }

    private func domain(_ fixture: OccurrenceVMFixture) -> NSDictionary {
        NSDictionary(dictionary: fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
    }

    private func assertNoMutation(_ fixture: OccurrenceVMFixture) {
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledOriginalIDs.isEmpty)
        XCTAssertTrue(fixture.backend.stoppedIDs.isEmpty)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)
        XCTAssertTrue(fixture.backend.scheduledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.snoozedIDs.isEmpty)
    }
}
