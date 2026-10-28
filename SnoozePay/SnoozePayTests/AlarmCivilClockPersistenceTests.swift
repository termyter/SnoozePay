import XCTest
@testable import SnoozePay

final class AlarmCivilClockPersistenceTests: XCTestCase {
    // Literal wire records: the Date is 2026-10-25T04:00Z, not a civil-time encoding.
    private static let legacyPayload = """
    {
      "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
      "time": 814593600,
      "repeatDays": [0, 6],
      "name": "Travel",
      "nameIsDefault": false,
      "soundID": "radar",
      "vibrationEnabled": true,
      "snoozeMinutes": 9,
      "penaltyAmount": 50,
      "progressiveScale": true,
      "enabled": true,
      "volume": 0.5,
      "volumeFadeIn": false,
      "theme": {"id": "forest"},
      "repeatMode": "weekly"
    }
    """

    private static let civilPayload = """
    {
      "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
      "time": 814593600,
      "clockTime": {"hour": 7, "minute": 0},
      "repeatDays": [0, 6],
      "name": "Travel",
      "nameIsDefault": false,
      "soundID": "radar",
      "vibrationEnabled": true,
      "snoozeMinutes": 9,
      "penaltyAmount": 50,
      "progressiveScale": true,
      "enabled": true,
      "volume": 0.5,
      "volumeFadeIn": false,
      "theme": {"id": "forest"},
      "repeatMode": "weekly"
    }
    """

    func testLegacyLiteralPreservesRawDateAndReaderTimezoneBehavior() throws {
        let alarm = try decode(Self.legacyPayload)
        XCTAssertNil(alarm.clockTime)
        XCTAssertEqual(alarm.time, Date(timeIntervalSinceReferenceDate: 814_593_600))
        XCTAssertEqual(alarm.resolvedTimeOfDay(calendar: calendar(offset: 3)), TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(alarm.resolvedTimeOfDay(calendar: calendar(offset: 1)), TimeOfDay(hour: 5, minute: 0))
        XCTAssertNil(try json(JSONEncoder().encode(alarm))["clockTime"])
    }

    func testCivilLiteralSurvivesRestartAndTimezoneWithoutReinterpretingRawDate() throws {
        let original = try decode(Self.civilPayload)
        let reloaded = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(reloaded, original)
        XCTAssertEqual(reloaded.time, Date(timeIntervalSinceReferenceDate: 814_593_600))
        for offset in [-8, 1, 3, 14] {
            XCTAssertEqual(reloaded.resolvedTimeOfDay(calendar: calendar(offset: offset)),
                           TimeOfDay(hour: 7, minute: 0))
        }
        let clock = try XCTUnwrap(try json(JSONEncoder().encode(reloaded))["clockTime"] as? [String: Int])
        XCTAssertEqual(clock, ["hour": 7, "minute": 0])
    }

    func testBothInitializersDefaultToLegacyAndAcceptAnExplicitClock() throws {
        let clock = try XCTUnwrap(TimeOfDay(hour: 23, minute: 59))
        XCTAssertNil(Alarm().clockTime)
        XCTAssertNil(Alarm(validating: UUID())?.clockTime)
        XCTAssertEqual(Alarm(clockTime: clock).clockTime, clock)
        XCTAssertEqual(Alarm(validating: UUID(), clockTime: clock)?.clockTime, clock)
    }

    func testUnrelatedCopiesPreserveLegacyAndCivilAuthority() throws {
        for payload in [Self.legacyPayload, Self.civilPayload] {
            let original = try decode(payload)
            let changed = original.with(name: "Edited", enabled: false, theme: .ocean)
            XCTAssertEqual(changed.id, original.id)
            XCTAssertEqual(changed.time, original.time)
            XCTAssertEqual(changed.clockTime, original.clockTime)
            XCTAssertEqual(changed.repeatDays, original.repeatDays)
            XCTAssertEqual(changed.penaltyAmount, original.penaltyAmount)
            XCTAssertEqual(changed.snoozeMinutes, original.snoozeMinutes)
            XCTAssertEqual(changed.name, "Edited")
            XCTAssertFalse(changed.enabled)
            XCTAssertEqual(changed.theme, .ocean)
        }
    }

    func testExplicitDateRetimingEstablishesClockInTheSuppliedCalendar() throws {
        let legacy = try decode(Self.legacyPayload)
        let selected = legacy.time.addingTimeInterval(75 * 60)
        let retimed = legacy.with(time: selected, calendar: calendar(offset: 3))
        XCTAssertEqual(retimed.clockTime, TimeOfDay(hour: 8, minute: 15))
        XCTAssertEqual(retimed.time, selected)
        XCTAssertEqual(retimed.id, legacy.id)
        XCTAssertEqual(retimed.resolvedTimeOfDay(calendar: calendar(offset: 1)), TimeOfDay(hour: 8, minute: 15))
        XCTAssertEqual(legacy.with(time: selected, calendar: calendar(offset: 1)).clockTime,
                       TimeOfDay(hour: 6, minute: 15))
    }

    func testIdentityDateCopiesPreserveLegacyAndCivilAuthorityAfterTravel() throws {
        for payload in [Self.legacyPayload, Self.civilPayload] {
            let original = try decode(payload)
            XCTAssertEqual(original.with(time: original.time, calendar: calendar(offset: 1)), original)
        }
        let civil = try decode(Self.civilPayload)
        XCTAssertEqual(civil.with(time: civil.time, calendar: calendar(offset: 1)).clockTime,
                       TimeOfDay(hour: 7, minute: 0))
    }

    func testDateOnlyOrSecondsOnlyCopiesDoNotAdoptACivilInterpretation() throws {
        for payload in [Self.legacyPayload, Self.civilPayload] {
            let original = try decode(payload)
            for shift in [30.0, 86_400.0] {
                let date = original.time.addingTimeInterval(shift)
                let copied = original.with(time: date, calendar: calendar(offset: 1))
                XCTAssertEqual(copied.time, date)
                XCTAssertEqual(copied.clockTime, original.clockTime)
            }
        }
    }

    func testExplicitClockWinsOverDateProjectionAndNilArgumentsKeepAuthority() throws {
        let original = try decode(Self.civilPayload)
        let selected = try XCTUnwrap(TimeOfDay(hour: 9, minute: 15))
        let retimed = original.with(time: original.time, clockTime: selected, calendar: calendar(offset: 1))
        XCTAssertEqual(retimed.clockTime, selected)
        XCTAssertEqual(retimed.time, original.time)
        XCTAssertEqual(retimed.resolvedTimeOfDay(calendar: calendar(offset: -8)), selected)
        XCTAssertEqual(original.with(time: nil, clockTime: nil, calendar: calendar(offset: 1)), original)
        XCTAssertEqual(original.timeOfDay, original.resolvedTimeOfDay())
    }

    func testPresentInvalidClockPayloadsThrowInsteadOfBecomingLegacyOrMidnight() {
        let invalidClocks = [
            "null", "{}", "{\"hour\":7}", "{\"minute\":0}",
            "{\"hour\":null,\"minute\":0}", "{\"hour\":24,\"minute\":0}",
            "{\"hour\":-1,\"minute\":0}", "{\"hour\":7,\"minute\":60}",
            "{\"hour\":7,\"minute\":-1}", "{\"hour\":7.5,\"minute\":0}",
            "{\"hour\":\"7\",\"minute\":0}", "[]"
        ]
        for clock in invalidClocks {
            let payload = Self.civilPayload.replacingOccurrences(of: "{\"hour\": 7, \"minute\": 0}", with: clock)
            XCTAssertThrowsError(try decode(payload), "Invalid clock must not be accepted: \(clock)")
        }
    }

    func testUnknownKeysDoNotOverrideTheValidatedClockOrLegacyInstant() throws {
        let payload = Self.civilPayload.replacingOccurrences(
            of: "{\"hour\": 7, \"minute\": 0}",
            with: "{\"hour\":7,\"minute\":0,\"timezone\":\"invented\",\"time\":null}"
        ).replacingOccurrences(of: "\"repeatMode\": \"weekly\"", with: "\"repeatMode\":\"weekly\",\"futureField\":null")
        let decoded = try decode(payload)
        XCTAssertEqual(decoded, try decode(Self.civilPayload))
        let encoded = try json(JSONEncoder().encode(decoded))
        XCTAssertEqual(encoded["clockTime"] as? [String: Int], ["hour": 7, "minute": 0])
        XCTAssertNil(encoded["futureField"])
    }

    func testCivilComponentsStayUnchangedInANamedDSTTimezone() throws {
        let alarm = try decode(Self.civilPayload).with(clockTime: TimeOfDay(hour: 2, minute: 30))
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        XCTAssertEqual(alarm.resolvedTimeOfDay(calendar: berlin), TimeOfDay(hour: 2, minute: 30))
        // Component persistence only: this does not establish AlarmKit's gap/repeat firing policy.
        XCTAssertEqual(try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(alarm)).clockTime,
                       TimeOfDay(hour: 2, minute: 30))
    }

    func testLegacyRepositoryReadDoesNotWriteAnImplicitMigration() throws {
        try withRepository { defaults, repository, scheduler in
            let raw = Data("[\(Self.legacyPayload)]".utf8)
            defaults.set(raw, forKey: "stored_alarms")
            let loaded = try XCTUnwrap(try repository.fetchAllChecked().first)
            XCTAssertNil(loaded.clockTime)
            XCTAssertEqual(defaults.data(forKey: "stored_alarms"), raw)
            XCTAssertNil(defaults.object(forKey: AlarmRepository.corruptBackupKey))
            XCTAssertTrue(scheduler.calls.isEmpty)
        }
    }

    func testInvalidPresentClockPreservesCorruptBytesBackupAndWriteLock() throws {
        try withRepository { defaults, repository, scheduler in
            let invalid = Self.civilPayload.replacingOccurrences(of: "{\"hour\": 7, \"minute\": 0}", with: "null")
            let raw = Data("[\(invalid)]".utf8)
            defaults.set(raw, forKey: "stored_alarms")
            XCTAssertThrowsError(try repository.fetchAllChecked())
            XCTAssertTrue(repository.lastLoadFailed)
            XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), raw)
            XCTAssertFalse(repository.save(Alarm()))
            XCTAssertFalse(repository.setEnabled(false, id: try decode(Self.civilPayload).id))
            XCTAssertEqual(defaults.data(forKey: "stored_alarms"), raw)
            XCTAssertTrue(scheduler.calls.isEmpty)
        }
    }

    func testWholeArraySaveKeepsOtherLegacyAndCivilRecordsDistinct() throws {
        try withRepository { defaults, repository, _ in
            let civil = try decode(Self.civilPayload)
            let legacyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
            let legacy = try decode(Self.legacyPayload.replacingOccurrences(of: civil.id.uuidString,
                                                                           with: legacyID.uuidString))
            defaults.set(try JSONEncoder().encode([legacy, civil]), forKey: "stored_alarms")
            XCTAssertTrue(repository.save(civil.with(name: "Renamed")))
            let reloaded = try repository.fetchAllChecked()
            XCTAssertNil(try XCTUnwrap(reloaded.first { $0.id == legacyID }).clockTime)
            XCTAssertEqual(try XCTUnwrap(reloaded.first { $0.id == civil.id }).clockTime, civil.clockTime)
            let rows = try XCTUnwrap(try JSONSerialization.jsonObject(
                with: XCTUnwrap(defaults.data(forKey: "stored_alarms"))) as? [[String: Any]])
            XCTAssertNil(try XCTUnwrap(rows.first { ($0["id"] as? String) == legacyID.uuidString })["clockTime"])
        }
    }

    func testOldWriterDropsCivilAuthorityAndReopensWithTheDocumentedLegacyFallback() throws {
        let original = try decode(Self.civilPayload)
        let oldBuild = try JSONDecoder().decode(PreCivilAlarmWire.self, from: Data(Self.civilPayload.utf8))
        let oldWritten = try JSONEncoder().encode(oldBuild)
        let reloaded = try JSONDecoder().decode(Alarm.self, from: oldWritten)
        XCTAssertNil(try json(oldWritten)["clockTime"])
        XCTAssertNil(reloaded.clockTime)
        XCTAssertEqual(reloaded, try decode(Self.legacyPayload))
        XCTAssertEqual(reloaded.time, original.time)
        XCTAssertEqual(reloaded.resolvedTimeOfDay(calendar: calendar(offset: 1)), TimeOfDay(hour: 5, minute: 0))
        XCTAssertEqual(original.resolvedTimeOfDay(calendar: calendar(offset: 1)), TimeOfDay(hour: 7, minute: 0))
    }

    private func decode(_ literal: String) throws -> Alarm {
        try JSONDecoder().decode(Alarm.self, from: Data(literal.utf8))
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func calendar(offset hours: Int) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: hours * 3_600)!
        return result
    }

    private func withRepository(
        _ body: (UserDefaults, AlarmRepository, CivilClockSchedulerSpy) throws -> Void
    ) throws {
        let suite = "test.civil-clock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scheduler = CivilClockSchedulerSpy()
        try body(defaults, AlarmRepository(defaults: defaults, scheduler: scheduler), scheduler)
    }
}

private final class CivilClockSchedulerSpy: AlarmScheduling {
    var calls: [UUID] = []
    func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
        calls.append(alarm.id)
        completion?(.success(()))
    }
    func cancel(_ alarmID: UUID) { calls.append(alarmID) }
}

/// The actual pre-civil field shape: synthesized decoding ignores clockTime,
/// and its encoder cannot retain a field that the old model does not store.
private struct PreCivilAlarmWire: Codable {
    let id: UUID
    let time: Date
    let repeatDays: [Int]
    let name: String
    let nameIsDefault: Bool
    let soundID: String
    let vibrationEnabled: Bool
    let snoozeMinutes: Int
    let penaltyAmount: Double
    let progressiveScale: Bool
    let enabled: Bool
    let volume: Float
    let volumeFadeIn: Bool
    let theme: AlarmTheme
    let repeatMode: AlarmRepeatMode
}
