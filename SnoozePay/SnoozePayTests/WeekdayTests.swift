import XCTest
@testable import SnoozePay

/// Unit tests for the `Weekday` enum — Calendar convention, legacy bridge,
/// and display labels.
final class WeekdayTests: XCTestCase {

    // MARK: - Calendar.weekday convention (1 = Sunday … 7 = Saturday)

    func testRawValuesMatchCalendarConvention() {
        // iOS `DateComponents.weekday` and `UNCalendarNotificationTrigger`
        // both use 1 = Sunday … 7 = Saturday. Lock that in.
        XCTAssertEqual(Weekday.sunday.rawValue, 1)
        XCTAssertEqual(Weekday.monday.rawValue, 2)
        XCTAssertEqual(Weekday.tuesday.rawValue, 3)
        XCTAssertEqual(Weekday.wednesday.rawValue, 4)
        XCTAssertEqual(Weekday.thursday.rawValue, 5)
        XCTAssertEqual(Weekday.friday.rawValue, 6)
        XCTAssertEqual(Weekday.saturday.rawValue, 7)
    }

    func testRawValueMatchesGregorianWeekday() {
        // Cross-check against an actual Date — 2026-04-12 is a Sunday.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let sundayComponents = DateComponents(
            calendar: calendar,
            year: 2026, month: 4, day: 12
        )
        let sundayDate = sundayComponents.date!
        let weekdayInt = calendar.component(.weekday, from: sundayDate)
        XCTAssertEqual(weekdayInt, Weekday.sunday.rawValue)
    }

    // MARK: - Legacy bridge (Mon=0 … Sun=6)

    func testLegacyIndexRoundTripAllDays() {
        for weekday in Weekday.allCases {
            let index = weekday.legacyMondayFirstIndex
            XCTAssertEqual(Weekday(legacyMondayFirstIndex: index), weekday)
        }
    }

    func testLegacyIndexBoundaries() {
        XCTAssertEqual(Weekday(legacyMondayFirstIndex: 0), .monday)
        XCTAssertEqual(Weekday(legacyMondayFirstIndex: 6), .sunday)
    }

    func testLegacyIndexOutOfRangeRejected() {
        XCTAssertNil(Weekday(legacyMondayFirstIndex: -1))
        XCTAssertNil(Weekday(legacyMondayFirstIndex: 7))
        XCTAssertNil(Weekday(legacyMondayFirstIndex: 99))
    }

    // MARK: - Set<Weekday> bridge

    func testSetFromLegacyIndices() {
        let set = Set<Weekday>(legacyMondayFirstIndices: [0, 2, 6])
        XCTAssertEqual(set, [.monday, .wednesday, .sunday])
    }

    func testSetFromLegacyDropsOutOfRange() {
        // The legacy storage allowed any Int; the typed view skips invalid ones
        // rather than crashing existing user data.
        let set = Set<Weekday>(legacyMondayFirstIndices: [0, 99, 5, -1])
        XCTAssertEqual(set, [.monday, .saturday])
    }

    func testSetRoundTripToLegacyIndicesIsSorted() {
        let set: Set<Weekday> = [.sunday, .monday, .friday]
        // Round-tripped indices come back sorted Mon→Sun
        XCTAssertEqual(set.legacyMondayFirstIndices, [0, 4, 6])
    }

    // MARK: - Display

    func testLocalizedShortNamesMatchExistingUI() {
        // Must match the labels currently used by `Alarm.repeatDaysDescription`.
        XCTAssertEqual(Weekday.monday.localizedShortName, "Пн")
        XCTAssertEqual(Weekday.tuesday.localizedShortName, "Вт")
        XCTAssertEqual(Weekday.wednesday.localizedShortName, "Ср")
        XCTAssertEqual(Weekday.thursday.localizedShortName, "Чт")
        XCTAssertEqual(Weekday.friday.localizedShortName, "Пт")
        XCTAssertEqual(Weekday.saturday.localizedShortName, "Сб")
        XCTAssertEqual(Weekday.sunday.localizedShortName, "Вс")
    }
}
