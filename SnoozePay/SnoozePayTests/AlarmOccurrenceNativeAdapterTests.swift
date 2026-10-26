import AlarmKit
import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
@MainActor
final class AlarmOccurrenceNativeAdapterTests: XCTestCase {
    private let alarmID = UUID()
    private let date = Date(timeIntervalSince1970: 1_800_000_037)
    private let weekly = NativeOccurrenceSnapshot.Weekly(hour: 7, minute: 15, mondayFirstDays: [0, 6])

    func testWeeklyFinishStopsOnlyOriginalAndRemovesOnlyDerivedWithoutRearming() {
        let fixture = inventory()
        assertSuccess(fixture.backend.finishOccurrence(request()))
        XCTAssertEqual(fixture.stopped, [alarmID])
        XCTAssertEqual(fixture.cancelled, [derivedID])
        XCTAssertEqual(fixture.entries, [snapshot(alarmID, .scheduled, weekly: weekly)])
        XCTAssertEqual(fixture.reads, 2)
    }

    func testAlreadyScheduledWeeklyOriginalRequiresNoNativeMutation() {
        let fixture = FinishInventory(entries: [snapshot(alarmID, .scheduled, weekly: weekly)])
        assertSuccess(fixture.backend.finishOccurrence(request()))
        XCTAssertTrue(fixture.stopped.isEmpty)
        XCTAssertTrue(fixture.cancelled.isEmpty)
    }

    func testMissingOrMismatchedWeeklyOriginalCannotConfirmFinish() {
        for entries in [[], [snapshot(alarmID, .scheduled)],
                        [snapshot(alarmID, .scheduled, weekly: .init(hour: 8, minute: 15, mondayFirstDays: [0, 6]))],
                        [snapshot(alarmID, .scheduled, weekly: .init(hour: 7, minute: 15, mondayFirstDays: [0]))]] {
            let fixture = FinishInventory(entries: entries)
            assertFailure(fixture.backend.finishOccurrence(request()), .nativeUnconfirmed)
            XCTAssertTrue(fixture.cancelled.isEmpty)
        }
    }

    func testCountdownPausedAlertingAndUnknownAreNotScheduledProof() {
        for phase in [NativeOccurrenceSnapshot.Phase.countdown, .paused, .alerting, .unknown] {
            let fixture = FinishInventory(entries: [snapshot(alarmID, phase, weekly: weekly)])
            fixture.stopMode = .ignore
            assertFailure(fixture.backend.finishOccurrence(request()), .nativeUnconfirmed)
        }
    }

    func testOneShotRemovesBothIDsAndAlreadyAbsentIsConfirmed() {
        let fixture = inventory()
        assertSuccess(fixture.backend.finishOccurrence(request(weekly: false)))
        XCTAssertEqual(fixture.cancelled, [alarmID, derivedID])
        XCTAssertTrue(fixture.stopped.isEmpty)
        XCTAssertTrue(fixture.entries.isEmpty)
        assertSuccess(fixture.backend.finishOccurrence(request(weekly: false)))
        XCTAssertEqual(fixture.cancelled.count, 2)
    }

    func testDuplicateInventoryRefusesBeforeAnyMutation() {
        let fixture = inventory()
        fixture.entries.append(fixture.entries[0])
        assertFailure(fixture.backend.finishOccurrence(request()), .nativeUnconfirmed)
        XCTAssertTrue(fixture.stopped.isEmpty)
        XCTAssertTrue(fixture.cancelled.isEmpty)
    }

    func testReadFailureBeforeOrAfterNativeActionsNeverConfirmsFinish() {
        for failedRead in [1, 2] {
            let fixture = inventory()
            fixture.failedRead = failedRead
            assertFailure(fixture.backend.finishOccurrence(request()), .inventoryUnavailable)
            XCTAssertEqual(fixture.stopped.count, failedRead == 1 ? 0 : 1)
        }
    }

    func testThrowingStopRequiresMatchingFreshReadback() {
        let failed = inventory()
        failed.stopMode = .throwBefore
        assertFailure(failed.backend.finishOccurrence(request()), .nativeUnconfirmed)
        XCTAssertEqual(failed.cancelled, [derivedID], "other owned cleanup is still attempted")
        let applied = inventory()
        applied.stopMode = .throwAfter
        assertSuccess(applied.backend.finishOccurrence(request()))
        XCTAssertEqual(applied.reads, 2)
    }

    func testThrowingCancelCanBeConfirmedOnlyByCheckedAbsence() {
        let fixture = inventory()
        fixture.cancelModes[derivedID] = .throwAfter
        assertSuccess(fixture.backend.finishOccurrence(request()))
        XCTAssertFalse(fixture.entries.contains { $0.id == derivedID })
    }

    func testPartialOneShotFailureRemainsRetryable() {
        let fixture = inventory()
        fixture.cancelModes[alarmID] = .throwBefore
        assertFailure(fixture.backend.finishOccurrence(request(weekly: false)), .nativeUnconfirmed)
        XCTAssertEqual(fixture.cancelled, [alarmID, derivedID])
        XCTAssertEqual(fixture.entries.map(\.id), [alarmID])
        fixture.cancelModes[alarmID] = .apply
        assertSuccess(fixture.backend.finishOccurrence(request(weekly: false)))
        XCTAssertTrue(fixture.entries.isEmpty)
    }

    func testExactTrackedReceiptIsRequiredBeforeDeletingPresentDerived() {
        for expected in [Date?.none, date.addingTimeInterval(1)] {
            let fixture = inventory()
            let tracked = AlarmOccurrenceFinishRequest(alarmID: alarmID, weekly: weekly,
                                                       expectedDerivedFireDate: expected,
                                                       allowsUntrackedDerived: false)
            assertFailure(fixture.backend.finishOccurrence(tracked), .ownershipUnavailable)
            XCTAssertTrue(fixture.cancelled.isEmpty)
            XCTAssertTrue(fixture.stopped.isEmpty)
        }
        assertSuccess(inventory().backend.finishOccurrence(request(untracked: false)))
    }

    func testTrackedUnknownReceiptAllowsCheckedAbsenceButNotPresentDerived() {
        let fixture = FinishInventory(entries: [snapshot(alarmID, .scheduled, weekly: weekly)])
        let tracked = AlarmOccurrenceFinishRequest(alarmID: alarmID, weekly: weekly,
                                                   expectedDerivedFireDate: nil, allowsUntrackedDerived: false)
        assertSuccess(fixture.backend.finishOccurrence(tracked))
        XCTAssertTrue(fixture.cancelled.isEmpty)
    }

    func testUntrackedWrongOrMissingFixedSchedulePreservesEveryRecordWithoutNativeOperations() {
        let invalidDerived = [snapshot(derivedID, .scheduled, weekly: weekly),
                              snapshot(derivedID, .scheduled),
                              snapshot(derivedID, .scheduled, fixed: Date(timeIntervalSince1970: .infinity)),
                              snapshot(derivedID, .scheduled, weekly: weekly, fixed: date)]
        for derived in invalidDerived {
            let records = [snapshot(alarmID, .alerting, weekly: weekly), derived]
            let fixture = FinishInventory(entries: records)
            assertFailure(fixture.backend.finishOccurrence(request()), .ownershipUnavailable)
            assertFailure(fixture.backend.cleanUpLateSnooze(request()), .ownershipUnavailable)
            XCTAssertEqual(fixture.entries, records)
            XCTAssertTrue(fixture.stopped.isEmpty)
            XCTAssertTrue(fixture.cancelled.isEmpty)
        }
    }

    func testLateCleanupDoesNotStopCancelOrRequireScheduledOriginal() {
        let fixture = inventory()
        assertSuccess(fixture.backend.cleanUpLateSnooze(request()))
        XCTAssertTrue(fixture.stopped.isEmpty)
        XCTAssertEqual(fixture.cancelled, [derivedID])
        XCTAssertEqual(fixture.entries, [snapshot(alarmID, .alerting, weekly: weekly)])
    }

    func testLateCleanupMismatchAndUnreadableReadbackRemainFailures() {
        let mismatch = inventory()
        let wrong = AlarmOccurrenceFinishRequest(alarmID: alarmID, weekly: weekly,
                                                 expectedDerivedFireDate: date.addingTimeInterval(1),
                                                 allowsUntrackedDerived: false)
        assertFailure(mismatch.backend.cleanUpLateSnooze(wrong), .ownershipUnavailable)
        XCTAssertTrue(mismatch.cancelled.isEmpty)
        let unreadable = inventory()
        unreadable.failedRead = 2
        assertFailure(unreadable.backend.cleanUpLateSnooze(request()), .inventoryUnavailable)
        XCTAssertTrue(unreadable.stopped.isEmpty)
    }

    func testBestEffortStopTargetsOnlyKnownOriginalAndReportsThrow() {
        let fixture = inventory()
        fixture.stopMode = .throwBefore
        assertFailure(fixture.backend.stopOriginalForFinish(alarmID), .nativeUnconfirmed)
        XCTAssertEqual(fixture.stopped, [alarmID])
        XCTAssertTrue(fixture.cancelled.isEmpty)
    }

    func testProjectionUsesPublicNativeScheduleAndStateWithoutConstructingAlarm() {
        let schedule = AlarmKit.Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 15), repeats: .weekly([.sunday, .monday])
        ))
        for (native, phase) in [(AlarmKit.Alarm.State.scheduled, NativeOccurrenceSnapshot.Phase.scheduled),
                                (.countdown, .countdown), (.paused, .paused), (.alerting, .alerting)] {
            let projected = AlarmKitScheduler.occurrenceSnapshot(id: alarmID, schedule: schedule, state: native)
            XCTAssertEqual(projected, snapshot(alarmID, phase, weekly: weekly))
        }
        let fixed = AlarmKitScheduler.occurrenceSnapshot(id: alarmID, schedule: .fixed(date), state: .scheduled)
        XCTAssertNil(fixed.weekly)
        XCTAssertEqual(fixed.fixedDate, date)
        for schedule in [AlarmKit.Alarm.Schedule?.none,
                         .relative(.init(time: .init(hour: 7, minute: 15), repeats: .never))] {
            let projected = AlarmKitScheduler.occurrenceSnapshot(id: alarmID, schedule: schedule, state: .scheduled)
            XCTAssertNil(projected.weekly)
            XCTAssertNil(projected.fixedDate)
        }
    }

    func testTrackedCancellationFallbackUsesInjectedReadAndFailsClosed() {
        var reads = 0
        let backend = AlarmKitScheduler(cancelAlarm: { _ in throw NativeFailure() }, readAlarms: {
            reads += 1
            return []
        })
        XCTAssertTrue(backend.cancelTrackedSnooze(alarmID))
        XCTAssertEqual(reads, 1)
        let failed = AlarmKitScheduler(cancelAlarm: { _ in throw NativeFailure() }, readAlarms: {
            throw NativeFailure()
        })
        XCTAssertFalse(failed.cancelTrackedSnooze(alarmID))
    }

    private var derivedID: UUID { AlarmKitScheduler.snoozeID(for: alarmID) }

    private func snapshot(
        _ id: UUID, _ phase: NativeOccurrenceSnapshot.Phase,
        weekly: NativeOccurrenceSnapshot.Weekly? = nil, fixed: Date? = nil
    ) -> NativeOccurrenceSnapshot {
        NativeOccurrenceSnapshot(id: id, phase: phase, weekly: weekly, fixedDate: fixed)
    }

    private func inventory() -> FinishInventory {
        FinishInventory(entries: [snapshot(alarmID, .alerting, weekly: weekly),
                                  snapshot(derivedID, .scheduled, fixed: date)])
    }

    private func request(weekly: Bool = true, untracked: Bool = true) -> AlarmOccurrenceFinishRequest {
        AlarmOccurrenceFinishRequest(alarmID: alarmID, weekly: weekly ? self.weekly : nil,
                                     expectedDerivedFireDate: untracked ? nil : date,
                                     allowsUntrackedDerived: untracked)
    }

    private func assertSuccess(_ result: Result<Void, AlarmOccurrenceFinishError>,
                               file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result { XCTFail("Unexpected finish failure: \(error)", file: file, line: line) }
    }

    private func assertFailure(
        _ result: Result<Void, AlarmOccurrenceFinishError>, _ expected: AlarmOccurrenceFinishError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .failure(let error) = result else { return XCTFail("Expected failure", file: file, line: line) }
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}

private struct NativeFailure: Error {}

@available(iOS 26.0, *)
@MainActor
private final class FinishInventory {
    enum Mode { case apply, ignore, throwBefore, throwAfter }
    var entries: [NativeOccurrenceSnapshot]
    var reads = 0
    var failedRead: Int?
    var stopped: [UUID] = []
    var cancelled: [UUID] = []
    var stopMode = Mode.apply
    var cancelModes: [UUID: Mode] = [:]

    init(entries: [NativeOccurrenceSnapshot]) { self.entries = entries }

    lazy var backend = AlarmKitScheduler(
        cancelAlarm: { [self] id in
            cancelled.append(id)
            let mode = cancelModes[id] ?? .apply
            if mode == .throwBefore { throw NativeFailure() }
            if mode != .ignore { entries.removeAll { $0.id == id } }
            if mode == .throwAfter { throw NativeFailure() }
        },
        readAuthorization: { .denied },
        readAlarms: {
            XCTFail("Finish must use the projected inventory")
            return []
        },
        stopAlarm: { [self] id in
            stopped.append(id)
            if stopMode == .throwBefore { throw NativeFailure() }
            if stopMode != .ignore, let index = entries.firstIndex(where: { $0.id == id }) {
                let previous = entries[index]
                entries[index] = NativeOccurrenceSnapshot(id: id, phase: .scheduled,
                                                          weekly: previous.weekly, fixedDate: previous.fixedDate)
            }
            if stopMode == .throwAfter { throw NativeFailure() }
        },
        readOccurrenceSnapshots: { [self] in
            reads += 1
            if failedRead == reads { throw NativeFailure() }
            return entries
        }
    )
}
