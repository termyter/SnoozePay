import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
@MainActor
final class AlarmLifecycleStatisticsIntegrationTests: XCTestCase {
    func testQuietFinishPublishesOnlyConfirmedActualWakeIntoTypedFiveMorningStatistics() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let confirmedAt = try XCTUnwrap(calendar.nextDate(
            after: Date(), matching: DateComponents(hour: 8, minute: 5, second: 0), matchingPolicy: .nextTime
        ))
        let selectedClock = try XCTUnwrap(TimeOfDay(hour: 7, minute: 4))
        let current = fixture.alarm.with(clockTime: selectedClock)
        XCTAssertTrue(fixture.seedRepository.save(current))
        let prior = try seedFourMornings(fixture, before: confirmedAt, calendar: calendar)
        XCTAssertEqual(Set(prior.map { calendar.startOfDay(for: $0) }).count, 4)
        fixture.defaults.set(10, forKey: "best_streak")
        let ticket = try fixture.recoveryTrackedTicket()
        let alarmBytes = fixture.defaults.data(forKey: "stored_alarms")
        let balance = fixture.wallet.balance
        let ledgerIDs = try fixture.ledger.fetchAllChecked().map(\.id)
        let timesBeforeFailure = fixture.defaults.data(forKey: "wake_times")
        let daysBeforeFailure = fixture.defaults.data(forKey: "wake_days")
        let native = LifecycleNativeInventory(entries: [original(current, alerting: true)])
        let recovery = AlarmOccurrenceRecovery(
            repository: fixture.repository,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: native.backend,
                                      snoozeSessions: fixture.store()),
            sessions: fixture.store(), wakes: fixture.wakes, now: { confirmedAt }, calendar: calendar
        )

        XCTAssertEqual(recovery.resume(ticket), .failure(.nativeUnconfirmed))
        XCTAssertEqual(fixture.defaults.data(forKey: "wake_times"), timesBeforeFailure)
        XCTAssertEqual(fixture.defaults.data(forKey: "wake_days"), daysBeforeFailure)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: current.id), ticket)
        try assertReadProjection(fixture, times: prior, today: confirmedAt, calendar: calendar,
                                 expected: (samples: 4, median: nil))
        let failedReads = native.occurrenceReads
        XCTAssertGreaterThan(failedReads, 0)

        native.entries = [original(current, alerting: false)]
        XCTAssertEqual(recovery.resume(ticket), .success(.completedNow))
        XCTAssertGreaterThan(native.occurrenceReads, failedReads)
        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: current.id))
        let expectedTimes = (prior + [confirmedAt]).sorted()
        // Snapshot AFTER the legitimate finish write; only following reads must preserve it.
        try assertReadProjection(fixture, times: expectedTimes, today: confirmedAt, calendar: calendar,
                                 expected: (samples: 5, median: 485))
        XCTAssertEqual(try fixture.repository.fetchChecked(id: current.id), current)
        XCTAssertEqual(fixture.defaults.data(forKey: "stored_alarms"), alarmBytes)
        XCTAssertEqual(current.clockTime, selectedClock)
        XCTAssertEqual(fixture.wallet.balance, balance)
        XCTAssertEqual(try fixture.ledger.fetchAllChecked().map(\.id), ledgerIDs)
        XCTAssertTrue(native.cancelled.isEmpty)
        XCTAssertTrue(native.stopped.isEmpty)
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
    }

    private func seedFourMornings(
        _ fixture: OccurrenceVMFixture, before today: Date, calendar: Calendar
    ) throws -> [Date] {
        var times: [Date] = []
        for offset in 1...4 {
            let time = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: today))
            fixture.wakes.recordWake(on: time, calendar: calendar)
            times.append(time)
        }
        return times.sorted()
    }

    private func original(_ alarm: Alarm, alerting: Bool) -> NativeOccurrenceSnapshot {
        NativeOccurrenceSnapshot(
            id: alarm.id, phase: alerting ? .alerting : .scheduled,
            weekly: .init(hour: 7, minute: 4, mondayFirstDays: [0, 2])
        )
    }

    private func assertReadProjection(
        _ fixture: OccurrenceVMFixture, times: [Date], today: Date, calendar: Calendar,
        expected: (samples: Int, median: Int?)
    ) throws {
        let before = domain(fixture)
        let snapshot = fixture.wakes.readSnapshot()
        XCTAssertEqual(snapshot.times, .value(times))
        XCTAssertEqual(snapshot.days, .value(times.map { calendar.startOfDay(for: $0) }.sorted()))
        let statistics = StatisticsViewModel(
            repository: fixture.ledger, wakeStore: fixture.wakes, alarmRepository: fixture.repository,
            defaults: fixture.defaults, calendar: calendar
        )
        statistics.loadData()
        statistics.recomputeSnapshots(today: today)
        XCTAssertEqual(statistics.wakeHistorySnapshot, snapshot)
        XCTAssertNil(statistics.overviewUnavailableReason)
        if let median = expected.median {
            guard case .available(let stats) = statistics.wakeTimeAvailability else {
                return XCTFail("Five actual confirmed mornings must be available")
            }
            XCTAssertEqual(stats.recentSampleCount, expected.samples)
            XCTAssertEqual(stats.medianMinutes, median)
            XCTAssertEqual(stats.minimumSamples, 5)
        } else {
            guard case .accumulating(let stats) = statistics.wakeTimeAvailability else {
                return XCTFail("An unconfirmed finish must leave the four real mornings accumulating")
            }
            XCTAssertEqual(stats.recentSampleCount, expected.samples)
            XCTAssertNil(stats.medianMinutes)
            XCTAssertEqual(stats.samplesUntilReady, 1)
        }
        XCTAssertEqual(domain(fixture), before, "Typed wake reads and statistics projection must preserve raw storage")
    }

    private func domain(_ fixture: OccurrenceVMFixture) -> NSDictionary {
        NSDictionary(dictionary: fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
    }
}
