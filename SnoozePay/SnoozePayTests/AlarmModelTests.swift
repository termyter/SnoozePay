import XCTest
@testable import SnoozePay

/// Unit tests for the Alarm domain model — penalty calculation and day description.
final class AlarmModelTests: XCTestCase {

    // MARK: - Penalty calculation

    func testBasePenaltyNoProgression() {
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: false)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 1), 50)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 2), 50)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 5), 50)
    }

    func testProgressivePenaltyDoubles() {
        // Design: exactly 4 steps — base, ×2, ×4, ×8 (50 → 100 → 200 → 400).
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 1), 50)   // ×1 (base)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 2), 100)  // ×2
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 3), 200)  // ×4
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 4), 400)  // ×8 (ceiling)
    }

    func testProgressivePenaltyCapsAtBaseTimesEight() {
        // Once the ladder hits base × 8 it never escalates further: counts
        // 4, 5, 10 all return the ceiling (#274).
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 4), 400, "4th snooze = base × 8")
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 5), 400, "5th snooze stays at ceiling")
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 10), 400, "10th snooze stays at ceiling")
    }

    func testProgressivePenaltyCeilingWithLargeBase() {
        // The cap scales with base: base=1000 → ceiling 8000, not 16000.
        let alarm = Alarm(penaltyAmount: 1000, progressiveScale: true)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 4), 8000)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 5), 8000)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 10), 8000)
    }

    func testIsPenaltyAtCeiling() {
        let progressive = Alarm(penaltyAmount: 50, progressiveScale: true)
        XCTAssertFalse(progressive.isPenaltyAtCeiling(forSnoozeCount: 3))
        XCTAssertTrue(progressive.isPenaltyAtCeiling(forSnoozeCount: 4))
        XCTAssertTrue(progressive.isPenaltyAtCeiling(forSnoozeCount: 9))

        // Non-progressive alarms are never "at the ceiling" — there is no ladder.
        let flat = Alarm(penaltyAmount: 50, progressiveScale: false)
        XCTAssertFalse(flat.isPenaltyAtCeiling(forSnoozeCount: 10))
    }

    // MARK: - Repeat days description

    func testRepeatDaysEmpty() {
        let alarm = Alarm(repeatDays: [])
        XCTAssertEqual(alarm.repeatDaysDescription, "Единожды")
    }

    func testRepeatDaysAllWeek() {
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(alarm.repeatDaysDescription, "Каждый день")
    }

    func testRepeatDaysWeekdays() {
        let alarm = Alarm(repeatDays: [0, 1, 2, 3, 4])
        XCTAssertEqual(alarm.repeatDaysDescription, "Будни")
    }

    func testRepeatDaysWeekend() {
        let alarm = Alarm(repeatDays: [5, 6])
        XCTAssertEqual(alarm.repeatDaysDescription, "Выходные")
    }
}
