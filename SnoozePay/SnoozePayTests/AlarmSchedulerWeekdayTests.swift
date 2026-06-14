import XCTest
import UserNotifications
@testable import SnoozePay

/// Pins the legacy `0 = Monday … 6 = Sunday` repeat-day convention used in
/// `Alarm.repeatDays` to Apple's `Calendar.weekday` (`1 = Sunday … 7 = Saturday`).
///
/// An off-by-one in `AlarmScheduler.makeTriggers(for:)` would mean "alarm on
/// Saturday rings on Sunday" — a critical regression for the core product.
/// These tests deliberately do NOT touch `UNUserNotificationCenter`; they only
/// assert on the trigger components produced by the pure mapping.
final class AlarmSchedulerWeekdayTests: XCTestCase {

    private let scheduler = AlarmScheduler.shared

    // MARK: - Helpers

    /// Build an alarm whose `time` is exactly the given hour:minute today.
    private func alarm(hour: Int, minute: Int, repeatDays: [Int]) -> Alarm {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        let time = Calendar.current.date(from: components) ?? Date()
        return Alarm(time: time, repeatDays: repeatDays)
    }

    private func calendarTrigger(_ trigger: AlarmScheduler.TriggerWithLabel) -> UNCalendarNotificationTrigger? {
        trigger.trigger as? UNCalendarNotificationTrigger
    }

    /// The primary (non-burst) triggers. The lock-screen fallback burst (#19)
    /// appends `_burstN` follow-ups whose presence depends on the global
    /// `criticalAlertsAvailable` flag (mutated by other tests via
    /// `requestPermission`). These weekday-mapping assertions only care about
    /// the primary calendar triggers, so filter the bursts out to stay
    /// deterministic regardless of suite ordering. Burst behaviour itself is
    /// pinned by `AlarmSchedulerFallbackBurstTests` /
    /// `AlarmSchedulerBurstCancellationTests`.
    private func primaries(for alarm: Alarm) -> [AlarmScheduler.TriggerWithLabel] {
        scheduler.makeTriggers(for: alarm).filter { !$0.label.contains("_burst") }
    }

    // MARK: - Empty repeatDays → single one-shot trigger

    func testMakeTriggers_emptyRepeatDays_producesSingleNonRepeatingTrigger() {
        let alarm = self.alarm(hour: 7, minute: 30, repeatDays: [])

        let triggers = primaries(for: alarm)

        XCTAssertEqual(triggers.count, 1, "Empty repeatDays should produce one one-shot trigger")
        XCTAssertEqual(triggers.first?.label, "once",
                       "Single-fire trigger must be labelled 'once' (used by cancel)")
        let calendarTrigger = self.calendarTrigger(triggers[0])
        XCTAssertNotNil(calendarTrigger)
        XCTAssertEqual(calendarTrigger?.repeats, false,
                       "One-shot alarm must not repeat")
        XCTAssertEqual(calendarTrigger?.dateComponents.hour, 7)
        XCTAssertEqual(calendarTrigger?.dateComponents.minute, 30)
        XCTAssertEqual(calendarTrigger?.dateComponents.second, 0)
        XCTAssertNil(calendarTrigger?.dateComponents.weekday,
                     "One-shot trigger must not pin a weekday — fires at next occurrence of HH:MM")
    }

    // MARK: - All 7 days → 7 repeating calendar triggers

    func testMakeTriggers_allSevenDays_producesSevenRepeatingTriggers() {
        let alarm = self.alarm(hour: 6, minute: 0, repeatDays: [0, 1, 2, 3, 4, 5, 6])

        let triggers = primaries(for: alarm)

        XCTAssertEqual(triggers.count, 7,
                       "All-day alarm must produce one trigger per weekday — separate triggers " +
                       "let cancel(_:) remove them by alarm ID prefix")

        // Every trigger must be a repeating calendar trigger pinned to the alarm's HH:MM.
        for entry in triggers {
            let trigger = calendarTrigger(entry)
            XCTAssertNotNil(trigger)
            XCTAssertEqual(trigger?.repeats, true)
            XCTAssertEqual(trigger?.dateComponents.hour, 6)
            XCTAssertEqual(trigger?.dateComponents.minute, 0)
            XCTAssertNotNil(trigger?.dateComponents.weekday)
        }

        // Labels must cover every day0…day6 exactly once.
        let labels = Set(triggers.map { $0.label })
        XCTAssertEqual(labels, Set((0...6).map { "day\($0)" }))

        // Calendar weekdays must cover the full 1…7 range exactly once.
        let weekdays = triggers.compactMap { calendarTrigger($0)?.dateComponents.weekday }
        XCTAssertEqual(Set(weekdays), Set(1...7))
    }

    // MARK: - Individual day mapping (legacy 0..6 → Calendar 1..7)

    private struct WeekdayMapping {
        let legacyDay: Int
        let calendarWeekday: Int
        let name: String
    }

    /// Single source of truth for the mapping — keep these expectations together
    /// so any future Calendar locale change is loud.
    private static let expectedWeekdayMapping: [WeekdayMapping] = [
        WeekdayMapping(legacyDay: 0, calendarWeekday: 2, name: "Monday"),
        WeekdayMapping(legacyDay: 1, calendarWeekday: 3, name: "Tuesday"),
        WeekdayMapping(legacyDay: 2, calendarWeekday: 4, name: "Wednesday"),
        WeekdayMapping(legacyDay: 3, calendarWeekday: 5, name: "Thursday"),
        WeekdayMapping(legacyDay: 4, calendarWeekday: 6, name: "Friday"),
        WeekdayMapping(legacyDay: 5, calendarWeekday: 7, name: "Saturday"),
        WeekdayMapping(legacyDay: 6, calendarWeekday: 1, name: "Sunday")
    ]

    func testMakeTriggers_individualDay_mapsToCorrectCalendarWeekday() {
        for entry in Self.expectedWeekdayMapping {
            let alarm = self.alarm(hour: 8, minute: 15, repeatDays: [entry.legacyDay])

            let triggers = primaries(for: alarm)

            XCTAssertEqual(triggers.count, 1, "\(entry.name): single repeat day → single trigger")
            XCTAssertEqual(triggers.first?.label, "day\(entry.legacyDay)")

            let trigger = calendarTrigger(triggers[0])
            XCTAssertEqual(trigger?.repeats, true, "\(entry.name): repeating-day trigger must repeat")
            XCTAssertEqual(trigger?.dateComponents.hour, 8, "\(entry.name): hour preserved")
            XCTAssertEqual(trigger?.dateComponents.minute, 15, "\(entry.name): minute preserved")
            XCTAssertEqual(trigger?.dateComponents.second, 0, "\(entry.name): second normalized to 0")
            XCTAssertEqual(
                trigger?.dateComponents.weekday,
                entry.calendarWeekday,
                "\(entry.name): legacy day \(entry.legacyDay) must map to Calendar.weekday \(entry.calendarWeekday)"
            )
        }
    }

    // MARK: - Critical edge cases (Saturday & Sunday boundary)

    /// The off-by-one most likely to surface in `((day + 1) % 7) + 1` is at the
    /// boundary between Saturday (legacy 5 → Cal 7) and Sunday (legacy 6 → Cal 1).
    /// Pin both explicitly so a future refactor of the formula trips this test.
    func testMakeTriggers_saturday_mapsToCalendarSaturday() {
        let alarm = self.alarm(hour: 9, minute: 0, repeatDays: [5])
        let triggers = primaries(for: alarm)
        XCTAssertEqual(calendarTrigger(triggers[0])?.dateComponents.weekday, 7,
                       "Legacy 5 (Sat) must map to Calendar.weekday 7 (Saturday)")
    }

    func testMakeTriggers_sunday_mapsToCalendarSunday() {
        let alarm = self.alarm(hour: 9, minute: 0, repeatDays: [6])
        let triggers = primaries(for: alarm)
        XCTAssertEqual(calendarTrigger(triggers[0])?.dateComponents.weekday, 1,
                       "Legacy 6 (Sun) must map to Calendar.weekday 1 (Sunday) — this is the wrap-around case")
    }
}
