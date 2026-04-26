import XCTest
@testable import SnoozePay

/// Unit tests for the `TimeOfDay` value type — range validation and date projection.
final class TimeOfDayTests: XCTestCase {

    // MARK: - Construction

    func testValidBoundaries() {
        XCTAssertNotNil(TimeOfDay(hour: 0, minute: 0))
        XCTAssertNotNil(TimeOfDay(hour: 23, minute: 59))
        XCTAssertNotNil(TimeOfDay(hour: 12, minute: 30))
    }

    func testHourOutOfRangeRejected() {
        XCTAssertNil(TimeOfDay(hour: -1, minute: 0))
        XCTAssertNil(TimeOfDay(hour: 24, minute: 0))
        XCTAssertNil(TimeOfDay(hour: 99, minute: 0))
    }

    func testMinuteOutOfRangeRejected() {
        XCTAssertNil(TimeOfDay(hour: 8, minute: -1))
        XCTAssertNil(TimeOfDay(hour: 8, minute: 60))
        XCTAssertNil(TimeOfDay(hour: 8, minute: 99))
    }

    // MARK: - From Date

    func testFromDateExtractsComponents() {
        // Build 2026-04-15 09:45 in UTC, extract via UTC calendar — exact components.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(
            calendar: calendar,
            year: 2026, month: 4, day: 15, hour: 9, minute: 45
        )
        guard let date = components.date else {
            XCTFail("Failed to construct fixture date")
            return
        }
        let tod = TimeOfDay(from: date, calendar: calendar)
        XCTAssertEqual(tod, TimeOfDay(hour: 9, minute: 45))
    }

    // MARK: - To Date

    func testToDatePreservesHourMinuteOnReferenceDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let referenceComponents = DateComponents(
            calendar: calendar,
            year: 2026, month: 4, day: 15, hour: 17, minute: 22
        )
        let reference = referenceComponents.date!

        let tod = TimeOfDay(hour: 7, minute: 30)!
        let projected = tod.toDate(on: reference, calendar: calendar)
        XCTAssertNotNil(projected)

        let projectedComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: projected!
        )
        XCTAssertEqual(projectedComponents.year, 2026)
        XCTAssertEqual(projectedComponents.month, 4)
        XCTAssertEqual(projectedComponents.day, 15)
        XCTAssertEqual(projectedComponents.hour, 7)
        XCTAssertEqual(projectedComponents.minute, 30)
        XCTAssertEqual(projectedComponents.second, 0)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = TimeOfDay(hour: 6, minute: 15)!
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimeOfDay.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
