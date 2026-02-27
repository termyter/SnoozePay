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
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 1), 50)   // x1
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 2), 100)  // x2
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 3), 200)  // x4
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 4), 400)  // x8
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 5), 800)  // x16
    }

    func testProgressivePenaltyFifthSnooze() {
        // Spec: 5th snooze = base * 16. Verify with base=1000.
        let alarm = Alarm(penaltyAmount: 1000, progressiveScale: true)
        XCTAssertEqual(alarm.penalty(forSnoozeCount: 5), 16000)
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
