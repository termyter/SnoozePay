import AlarmKit
import XCTest
@testable import SnoozePay

private typealias AppAlarm = SnoozePay.Alarm

/// Consumer contracts for persisted civil clocks; no native firing-time claim.
@available(iOS 26.0, *)
@MainActor
final class AlarmCivilClockIntegrationTests: XCTestCase {
    private let rawFourUTC = Date(timeIntervalSinceReferenceDate: 814_593_600)
    private let weekdays = [0, 1, 2, 3, 4]

    func testRestartedCivilAlarmKeepsSevenAcrossReaderOffsetsInFormatterAndNativeSchedule() throws {
        try withStore { store in
            let original = try civilAlarm()
            let bytes = try JSONEncoder().encode([original])
            store.defaults.set(bytes, forKey: "stored_alarms")
            let restarted = AlarmRepository(defaults: store.defaults, scheduler: store.scheduler)
            let loaded = try XCTUnwrap(try restarted.fetchChecked(id: original.id))

            for offset in [3, 1, 14, -8] {
                let reader = calendar(offset: offset)
                XCTAssertEqual(WallClockFormatter.string(
                    from: loaded, style: .padded, locale: Locale(identifier: "ru_RU"), calendar: reader
                ), "07:00")
                assertNativeClock(loaded, calendar: reader, hour: 7, minute: 0)
            }
            XCTAssertEqual(loaded.time, rawFourUTC)
            XCTAssertEqual(store.defaults.data(forKey: "stored_alarms"), bytes)
            XCTAssertTrue(store.scheduler.calls.isEmpty)
        }
    }

    func testLegacyConsumerClockStillMovesFromSevenToFiveWithoutAdoptingCivilAuthority() throws {
        try withStore { store in
            let original = AppAlarm(time: rawFourUTC, repeatDays: weekdays, name: "Morning")
            let bytes = try JSONEncoder().encode([original])
            store.defaults.set(bytes, forKey: "stored_alarms")
            let loaded = try XCTUnwrap(try store.repository.fetchChecked(id: original.id))

            for (offset, hour, text) in [(3, 7, "07:00"), (1, 5, "05:00")] {
                let reader = calendar(offset: offset)
                XCTAssertEqual(WallClockFormatter.string(
                    from: loaded, style: .padded, locale: Locale(identifier: "ru_RU"), calendar: reader
                ), text)
                XCTAssertEqual(TransactionAlarmContext.caption(for: loaded, calendar: reader), "Будни · \(text)")
                XCTAssertEqual(deleteContext(loaded, calendar: reader), "Будни · Пн–Пт · \(text)")
                assertNativeClock(loaded, calendar: reader, hour: hour, minute: 0)
            }
            XCTAssertNil(loaded.clockTime)
            XCTAssertEqual(store.defaults.data(forKey: "stored_alarms"), bytes)
            XCTAssertNil(store.defaults.object(forKey: AlarmRepository.corruptBackupKey))
        }
    }

    func testNativeWeeklyAndNeverRecurrencesKeepCivilClockAndSelectedDayChipsDistinct() throws {
        let weekly = try civilAlarm(repeatDays: [0, 6])
        let reader = calendar(offset: -8)
        guard case let .relative(relative) = AlarmKitScheduler.makeSchedule(for: weekly, calendar: reader),
              case let .weekly(days) = relative.repeats else {
            return XCTFail("Monday/Sunday must produce a relative weekly schedule")
        }
        XCTAssertEqual(relative.time.hour, 7)
        XCTAssertEqual(relative.time.minute, 0)
        XCTAssertEqual(days.count, 2)
        XCTAssertTrue(days.contains(.monday))
        XCTAssertTrue(days.contains(.sunday))

        let once = weekly.with(repeatMode: .never)
        guard case let .relative(oneShot) = AlarmKitScheduler.makeSchedule(for: once, calendar: reader),
              case .never = oneShot.repeats else {
            return XCTFail("Never mode must stay one-shot even when day chips remain selected")
        }
        XCTAssertEqual(once.repeatDays, [0, 6])
        XCTAssertEqual(oneShot.time.hour, 7)
        XCTAssertEqual(oneShot.time.minute, 0)
    }

    func testDSTGapAndRepeatedDayKeepConfiguredTwoThirtyInNativeAndDisplayConsumers() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        for instant in ["2026-03-29T00:30:00Z", "2026-10-25T00:30:00Z"] {
            let original = try civilAlarm(hour: 2, minute: 30, time: date(instant))
            let loaded = try JSONDecoder().decode(AppAlarm.self, from: JSONEncoder().encode(original))
            assertNativeClock(loaded, calendar: berlin, hour: 2, minute: 30)
            XCTAssertEqual(WallClockFormatter.string(
                from: loaded, style: .padded, locale: Locale(identifier: "ru_RU"), calendar: berlin
            ), "02:30")
        }
        // These are configured components, not evidence of AlarmKit's gap/repeat firing policy.
    }

    func testCivilOriginalDoesNotChangeAbsoluteSnoozeSecondsOrTheTwoSecondFloor() throws {
        let alarm = try civilAlarm()
        let anchor = try date("2100-01-15T12:34:37Z")
        let target = AlarmScheduler.scheduledFireDate(now: anchor, snoozeMinutes: alarm.snoozeMinutes)
        XCTAssertEqual(target, anchor.addingTimeInterval(540))
        guard case let .fixed(fireDate) = AlarmKitScheduler.makeSnoozeSchedule(fireDate: target) else {
            return XCTFail("Paid snooze must retain its absolute fixed schedule")
        }
        XCTAssertEqual(fireDate, target)
        XCTAssertEqual(calendar(offset: 0).component(.second, from: fireDate), 37)
        XCTAssertEqual(AlarmKitScheduler.flooredSnoozeFireDate(anchor.addingTimeInterval(-60), now: anchor),
                       anchor.addingTimeInterval(2))
        XCTAssertEqual(AlarmKitScheduler.flooredSnoozeFireDate(anchor.addingTimeInterval(2), now: anchor),
                       anchor.addingTimeInterval(2))
        XCTAssertEqual(AlarmKitScheduler.flooredSnoozeFireDate(anchor.addingTimeInterval(3), now: anchor),
                       anchor.addingTimeInterval(3))
    }

    func testCivilFormatterRetainsLocaleHourCycleAndDesignWidth() throws {
        let alarm = try civilAlarm(hour: 7, minute: 4)
        var twelveHour = Locale.Components(identifier: "ru_RU")
        twelveHour.hourCycle = .oneToTwelve
        for offset in [14, -8] {
            let reader = calendar(offset: offset)
            XCTAssertEqual(WallClockFormatter.string(
                from: alarm, style: .padded, locale: Locale(identifier: "ru_RU"), calendar: reader
            ), "07:04")
            XCTAssertEqual(WallClockFormatter.string(
                from: alarm, style: .compact, locale: Locale(identifier: "ru_RU"), calendar: reader
            ), "7:04")
            for style in [WallClockFormatter.HourStyle.padded, .compact] {
                let rendered = WallClockFormatter.string(
                    from: alarm, style: style, locale: Locale(components: twelveHour), calendar: reader
                )
                XCTAssertEqual(normalisedSpaces(rendered), "7:04 AM")
            }
        }
    }

    func testRestartedCivilClockAgreesInActualListHeroCaptionAndDeletionConsumers() throws {
        try withStore { store in
            let alarm = try civilAlarm()
            store.defaults.set(try JSONEncoder().encode([alarm]), forKey: "stored_alarms")
            let loaded = try XCTUnwrap(try store.repository.fetchChecked(id: alarm.id))
            let list = store.makeListViewModel()
            list.loadData()
            XCTAssertEqual(list.alarms.map(\.id), [alarm.id])
            XCTAssertEqual(list.alarmTimeString(at: 0), "7:00")
            XCTAssertEqual(store.makeFiringViewModel(loaded).heroTitle, "Morning · 07:00")
            XCTAssertEqual(TransactionAlarmContext.caption(
                for: loaded.id.uuidString, calendar: calendar(offset: 1),
                lookup: { try? store.repository.fetchChecked(id: $0) }
            ), "Будни · 07:00")
            XCTAssertEqual(deleteContext(loaded, calendar: calendar(offset: 1)), "Будни · Пн–Пт · 07:00")
            XCTAssertTrue(store.scheduler.calls.isEmpty)
        }
    }

    func testMixedRepositoryAndActualListSortCivilSixBeforeLegacySevenWithoutReadMigration() throws {
        try withStore { store in
            let reader = Calendar.current
            let day = try date("2026-01-15T12:00:00Z")
            let rawNine = try XCTUnwrap(reader.date(bySettingHour: 9, minute: 0, second: 0, of: day))
            let rawSeven = try XCTUnwrap(reader.date(bySettingHour: 7, minute: 0, second: 0, of: day))
            let civil = try civilAlarm(hour: 6, time: rawNine)
            let legacy = AppAlarm(time: rawSeven, name: "Legacy")
            let bytes = try JSONEncoder().encode([legacy, civil])
            store.defaults.set(bytes, forKey: "stored_alarms")
            let list = store.makeListViewModel()
            list.loadData()
            XCTAssertEqual(list.alarms.map(\.id), [civil.id, legacy.id])
            XCTAssertEqual(list.alarmTimeString(at: 0), "6:00")
            XCTAssertEqual(list.alarmTimeString(at: 1), "7:00")
            let reopened = AlarmRepository(defaults: store.defaults, scheduler: store.scheduler)
            let rows = try reopened.fetchAllChecked()
            XCTAssertEqual(rows.map(\.id), [civil.id, legacy.id])
            XCTAssertNil(try XCTUnwrap(rows.first { $0.id == legacy.id }).clockTime)
            XCTAssertEqual(store.defaults.data(forKey: "stored_alarms"), bytes)
            XCTAssertNil(store.defaults.object(forKey: AlarmRepository.corruptBackupKey))
            XCTAssertTrue(store.scheduler.calls.isEmpty)
        }
    }

    func testMalformedCivilClockMakesActualListSurfaceCorruptionAndPreserveLockedBytes() throws {
        try withStore { store in
            let candidate = try civilAlarm()
            var payload = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(candidate)
            ) as? [String: Any])
            payload["clockTime"] = ["hour": 24, "minute": 0]
            let bytes = try JSONSerialization.data(withJSONObject: [payload], options: [.sortedKeys])
            store.defaults.set(bytes, forKey: "stored_alarms")
            let list = store.makeListViewModel()
            var errors: [LocalizedError] = []
            list.onLoadError = { errors.append($0) }
            list.loadData()
            XCTAssertTrue(list.alarms.isEmpty)
            XCTAssertEqual(errors.count, 1)
            guard let error = errors.first as? AlarmRepository.RepositoryError,
                  case .decodeFailure = error else {
                return XCTFail("A malformed present clock must reach the list's corruption callback")
            }
            XCTAssertTrue(store.repository.lastLoadFailed)
            XCTAssertEqual(store.defaults.data(forKey: AlarmRepository.corruptBackupKey), bytes)
            XCTAssertFalse(store.repository.save(candidate))
            XCTAssertEqual(store.defaults.data(forKey: "stored_alarms"), bytes)
            XCTAssertTrue(store.scheduler.calls.isEmpty)
        }
    }

    private func civilAlarm(
        hour: Int = 7, minute: Int = 0,
        time: Date = Date(timeIntervalSinceReferenceDate: 814_593_600),
        repeatDays: [Int] = [0, 1, 2, 3, 4]
    ) throws -> AppAlarm {
        AppAlarm(time: time, clockTime: try XCTUnwrap(TimeOfDay(hour: hour, minute: minute)),
                 repeatDays: repeatDays, name: "Morning")
    }

    private func calendar(offset hours: Int) -> Calendar {
        var reader = Calendar(identifier: .gregorian)
        reader.timeZone = TimeZone(secondsFromGMT: hours * 3_600)!
        return reader
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private func assertNativeClock(
        _ alarm: AppAlarm, calendar: Calendar, hour: Int, minute: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case let .relative(relative) = AlarmKitScheduler.makeSchedule(for: alarm, calendar: calendar) else {
            return XCTFail("Original alarms must use a relative schedule", file: file, line: line)
        }
        XCTAssertEqual(relative.time.hour, hour, file: file, line: line)
        XCTAssertEqual(relative.time.minute, minute, file: file, line: line)
    }

    private func deleteContext(_ alarm: AppAlarm, calendar: Calendar) -> String {
        AlarmDeletionCopy.contextLine(repeatDays: alarm.repeatDays, repeatMode: alarm.repeatMode,
                                      time: alarm.time, clockTime: alarm.clockTime, calendar: calendar)
    }

    private func normalisedSpaces(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.whitespaces.contains($0) ? " " : $0
        }))
    }

    private func withStore(_ body: (CivilClockIntegrationStore) throws -> Void) throws {
        let domainGuard = AppDefaultsDomainGuard()
        let suite = "test.civil-clock.integration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            domainGuard.assertUntouched()
        }
        try body(CivilClockIntegrationStore(defaults: defaults))
    }
}

@MainActor
private final class CivilClockIntegrationStore {
    let defaults: UserDefaults
    let scheduler: CivilClockIntegrationSchedulerSpy
    let repository: AlarmRepository
    private let center: NotificationCenter
    private let wakeStore: WakeEventStore
    private let ledger: TransactionRepository
    private let wallet: BalanceService

    init(defaults: UserDefaults) {
        let scheduler = CivilClockIntegrationSchedulerSpy()
        let center = NotificationCenter()
        let wakeStore = WakeEventStore(defaults: defaults)
        let ledger = TransactionRepository(defaults: defaults, wakeStore: wakeStore)
        self.defaults = defaults
        self.scheduler = scheduler
        self.center = center
        repository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        self.wakeStore = wakeStore
        self.ledger = ledger
        wallet = BalanceService(defaults: defaults, transactionRepository: ledger, notificationCenter: center)
    }

    func makeListViewModel() -> AlarmsListViewModel {
        AlarmsListViewModel(
            alarmRepository: repository, balanceService: wallet, transactionRepository: ledger,
            notificationCenter: center, alarmDefaults: AlarmDefaults(defaults: defaults),
            backendMonitor: AlarmBackendMonitor(
                probe: FixedAlarmBackendProbe(result: .available), notificationCenter: center
            )
        )
    }

    func makeFiringViewModel(_ alarm: AppAlarm) -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: alarm, balanceService: wallet, alarmRepository: repository,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil),
            wakeStore: wakeStore, ledger: ledger
        )
    }
}

private final class CivilClockIntegrationSchedulerSpy: AlarmScheduling {
    var calls: [UUID] = []

    func schedule(_ alarm: AppAlarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
        calls.append(alarm.id)
        completion?(.success(()))
    }

    func cancel(_ alarmID: UUID) { calls.append(alarmID) }
}
