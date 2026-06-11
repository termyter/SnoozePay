import XCTest
import UserNotifications
@testable import SnoozePay

/// Unit tests for the weekly / one-shot repeat mode added in #229:
/// - `Alarm.repeatMode` defaults, `with(...)` mutator, and the
///   backwards-compatible / sanitizing Codable decode (legacy alarms without
///   the key, unknown raw values).
/// - `AlarmScheduler.makeTriggers` planning: `.never` produces non-repeating
///   per-day triggers, `.weekly` keeps the historical repeating ones.
/// - `AlarmFiringViewModel.dismiss` auto-disables one-shot alarms and keeps
///   weekly alarms enabled.
/// - `CreateAlarmViewModel` seeding + persistence of the new field.
final class AlarmRepeatModeTests: XCTestCase {

    // MARK: - Model defaults + with(...)

    func testDefaultInit_repeatModeIsWeekly() {
        XCTAssertEqual(Alarm().repeatMode, .weekly,
                       "New alarms must default to the historical weekly behaviour")
    }

    func testValidatingInit_acceptsNeverMode() {
        let alarm = Alarm(validating: UUID(), repeatDays: [0, 2], repeatMode: .never)
        XCTAssertEqual(alarm?.repeatMode, .never)
    }

    func testWith_repeatMode_changesOnlyRepeatMode() {
        let original = Alarm(repeatDays: [0, 4], name: "Утро", penaltyAmount: 100)

        let oneShot = original.with(repeatMode: .never)

        XCTAssertEqual(oneShot.repeatMode, .never)
        XCTAssertEqual(oneShot.id, original.id, "with(...) must preserve identity")
        XCTAssertEqual(oneShot.repeatDays, original.repeatDays)
        XCTAssertEqual(oneShot.name, original.name)
        XCTAssertEqual(oneShot.penaltyAmount, original.penaltyAmount)
    }

    func testWith_otherField_preservesRepeatMode() {
        let oneShot = Alarm(repeatDays: [1], repeatMode: .never)
        XCTAssertEqual(oneShot.with(enabled: false).repeatMode, .never)
    }

    // MARK: - Codable round-trip

    func testEncodeDecode_roundTripsNeverMode() throws {
        let alarm = Alarm(repeatDays: [0, 3], repeatMode: .never)

        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)

        XCTAssertEqual(decoded.repeatMode, .never)
        XCTAssertEqual(decoded.id, alarm.id)
        XCTAssertEqual(decoded.repeatDays, alarm.repeatDays)
    }

    func testEncodeDecode_roundTripsWeeklyMode() throws {
        let alarm = Alarm(repeatDays: [5, 6], repeatMode: .weekly)

        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)

        XCTAssertEqual(decoded.repeatMode, .weekly)
    }

    // MARK: - Legacy decode (pre-#229 payloads)

    /// Strip the `repeatMode` key from an encoded alarm to simulate a
    /// pre-#229 persisted payload, then decode it back.
    private func decodeWithoutRepeatModeKey(_ alarm: Alarm) throws -> Alarm {
        let data = try JSONEncoder().encode(alarm)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json.removeValue(forKey: "repeatMode")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Alarm.self, from: legacyData)
    }

    func testDecode_missingRepeatModeKey_defaultsToWeekly() throws {
        let legacy = try decodeWithoutRepeatModeKey(Alarm(repeatDays: [0, 1, 2, 3, 4]))
        XCTAssertEqual(legacy.repeatMode, .weekly,
                       "Pre-#229 alarms must keep their historical weekly behaviour")
    }

    func testDecode_missingRepeatModeKey_preservesOtherFields() throws {
        let original = Alarm(repeatDays: [2], name: "Зал", penaltyAmount: 75)
        let legacy = try decodeWithoutRepeatModeKey(original)
        XCTAssertEqual(legacy.id, original.id)
        XCTAssertEqual(legacy.repeatDays, original.repeatDays)
        XCTAssertEqual(legacy.name, original.name)
        XCTAssertEqual(legacy.penaltyAmount, original.penaltyAmount)
    }

    func testDecode_unknownRepeatModeRawValue_sanitizesToWeekly() throws {
        // Corrupt storage / rolled-back future mode must not throw — a throw
        // would lock the entire persisted store (#72 / #117).
        let data = try JSONEncoder().encode(Alarm(repeatDays: [0]))
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json["repeatMode"] = "monthly"
        let corruptData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Alarm.self, from: corruptData)

        XCTAssertEqual(decoded.repeatMode, .weekly)
    }

    // MARK: - Trigger planning (UNNotificationRequest для never-режима)

    private let scheduler = AlarmScheduler.shared

    private func calendarTrigger(
        _ trigger: AlarmScheduler.TriggerWithLabel
    ) -> UNCalendarNotificationTrigger? {
        trigger.trigger as? UNCalendarNotificationTrigger
    }

    func testMakeTriggers_neverMode_producesNonRepeatingPerDayTriggers() {
        let alarm = Alarm(repeatDays: [0, 2], repeatMode: .never)

        let triggers = scheduler.makeTriggers(for: alarm)

        XCTAssertEqual(triggers.count, 2)
        XCTAssertEqual(triggers.map(\.label).sorted(), ["day0", "day2"],
                       "Per-day labels must survive so cancel(_:) removes them")
        for trigger in triggers {
            let calendar = self.calendarTrigger(trigger)
            XCTAssertNotNil(calendar)
            XCTAssertEqual(calendar?.repeats, false,
                           "One-shot alarm must not re-arm itself a week later")
            XCTAssertNotNil(calendar?.dateComponents.weekday,
                            "Each one-shot trigger still pins its weekday")
        }
    }

    func testMakeTriggers_weeklyMode_keepsRepeatingTriggers() {
        let alarm = Alarm(repeatDays: [0, 2], repeatMode: .weekly)

        let triggers = scheduler.makeTriggers(for: alarm)

        XCTAssertEqual(triggers.count, 2)
        for trigger in triggers {
            XCTAssertEqual(calendarTrigger(trigger)?.repeats, true,
                           "Weekly alarms keep the historical repeating triggers")
        }
    }

    func testMakeTriggers_neverModeWithoutDays_fallsBackToOnceTrigger() {
        let alarm = Alarm(repeatDays: [], repeatMode: .never)

        let triggers = scheduler.makeTriggers(for: alarm)

        XCTAssertEqual(triggers.count, 1)
        XCTAssertEqual(triggers.first?.label, "once")
        XCTAssertEqual(triggers.first.flatMap(calendarTrigger)?.repeats, false)
    }

    // MARK: - Dismiss semantics (one-shot auto-disable)

    func testDismiss_oneShotAlarmWithDays_isDisabled() {
        let repo = AlarmRepository(defaults: .standard)
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], enabled: true, repeatMode: .never)
        repo.save(alarm)
        defer { repo.delete(id: alarm.id) }

        let viewModel = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, alarmRepository: repo)
        viewModel.dismiss()

        XCTAssertEqual(repo.fetch(id: alarm.id)?.enabled, false,
                       "One-shot alarm must auto-disable after dismiss")
    }

    func testDismiss_weeklyAlarmWithDays_staysEnabled() {
        let repo = AlarmRepository(defaults: .standard)
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4], enabled: true, repeatMode: .weekly)
        repo.save(alarm)
        defer { repo.delete(id: alarm.id) }

        let viewModel = AlarmFiringViewModel(alarm: alarm, snoozeCount: 0, alarmRepository: repo)
        viewModel.dismiss()

        XCTAssertEqual(repo.fetch(id: alarm.id)?.enabled, true,
                       "Weekly alarms keep firing every week — dismiss must not disable them")
    }

    // MARK: - CreateAlarmViewModel seeding + persistence

    func testCreateVM_newAlarm_defaultsToWeekly() {
        XCTAssertEqual(CreateAlarmViewModel().repeatMode, .weekly)
    }

    func testCreateVM_editingOneShotAlarm_seedsNever() {
        let alarm = Alarm(repeatDays: [3], repeatMode: .never)
        XCTAssertEqual(CreateAlarmViewModel(alarm: alarm).repeatMode, .never)
    }

    func testCreateVM_save_persistsRepeatMode() {
        let repo = AlarmRepository(defaults: .standard)
        let viewModel = CreateAlarmViewModel(repository: repo)
        viewModel.repeatDays = [0, 2]
        viewModel.repeatMode = .never

        XCTAssertTrue(viewModel.save())

        let saved = repo.fetchAll().first { $0.repeatDays == [0, 2] && $0.repeatMode == .never }
        XCTAssertNotNil(saved, "Saved alarm must carry the one-shot mode")
        if let saved { repo.delete(id: saved.id) }
    }

    func testCreateVM_hintMatchesMode() {
        let viewModel = CreateAlarmViewModel()

        viewModel.repeatMode = .never
        XCTAssertEqual(
            viewModel.repeatModeHint,
            "Будильник сработает в выбранные дни один раз и отключится."
        )

        viewModel.repeatMode = .weekly
        XCTAssertEqual(
            viewModel.repeatModeHint,
            "Будет повторяться каждую неделю по выбранным дням."
        )
    }
}
