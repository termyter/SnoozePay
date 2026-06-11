import XCTest
@testable import SnoozePay

/// Unit tests for the validating construction boundary added in #207 —
/// `Alarm(validating:...)` must reject out-of-range field values, the
/// `with(...)` mutators must preserve identity and untouched fields, and the
/// Codable decode path must sanitize (not reject) corrupt legacy storage.
final class AlarmValidationTests: XCTestCase {

    // MARK: - Failable init rejects garbage

    func testValidatingInit_negativePenaltyReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), penaltyAmount: -50))
    }

    func testValidatingInit_nanPenaltyReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), penaltyAmount: .nan))
    }

    func testValidatingInit_infinitePenaltyReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), penaltyAmount: .infinity))
    }

    func testValidatingInit_zeroSnoozeMinutesReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), snoozeMinutes: 0))
    }

    func testValidatingInit_oversizedSnoozeMinutesReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), snoozeMinutes: 31))
    }

    func testValidatingInit_negativeWeekdayIndexReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), repeatDays: [-1, 0]))
    }

    func testValidatingInit_outOfRangeWeekdayIndexReturnsNil() {
        XCTAssertNil(Alarm(validating: UUID(), repeatDays: [0, 7]))
    }

    // MARK: - Failable init accepts valid values

    func testValidatingInit_boundaryValuesSucceed() {
        let alarm = Alarm(
            validating: UUID(),
            repeatDays: [0, 6],
            snoozeMinutes: 30,
            penaltyAmount: 0
        )
        XCTAssertNotNil(alarm)
        XCTAssertEqual(alarm?.repeatDays, [0, 6])
        XCTAssertEqual(alarm?.snoozeMinutes, 30)
        XCTAssertEqual(alarm?.penaltyAmount, 0)
    }

    func testValidatingInit_defaultsAreValid() {
        XCTAssertNotNil(Alarm(validating: UUID()))
    }

    func testValidatingInit_clampsVolumeInsteadOfRejecting() {
        // Volume keeps the historical clamp-don't-reject semantics.
        let alarm = Alarm(validating: UUID(), volume: 1.5)
        XCTAssertEqual(alarm?.volume, 1.0)
    }

    // MARK: - with(...) mutators

    func testWith_preservesIdentityAndUntouchedFields() {
        let original = Alarm(
            repeatDays: [0, 4],
            name: "Утро",
            snoozeMinutes: 5,
            penaltyAmount: 100,
            enabled: true,
            volume: 0.5,
            volumeFadeIn: true,
            theme: .ocean
        )

        let toggled = original.with(enabled: false)

        XCTAssertEqual(toggled.id, original.id, "with(...) must keep identity")
        XCTAssertFalse(toggled.enabled)
        XCTAssertEqual(toggled.repeatDays, original.repeatDays)
        XCTAssertEqual(toggled.name, original.name)
        XCTAssertEqual(toggled.snoozeMinutes, original.snoozeMinutes)
        XCTAssertEqual(toggled.penaltyAmount, original.penaltyAmount)
        XCTAssertEqual(toggled.volume, original.volume)
        XCTAssertEqual(toggled.volumeFadeIn, original.volumeFadeIn)
        XCTAssertEqual(toggled.theme, original.theme)
    }

    func testWith_replacesMultipleFields() {
        let original = Alarm(name: "Старое", penaltyAmount: 50)
        let edited = original.with(name: "Новое", penaltyAmount: 200)

        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.name, "Новое")
        XCTAssertEqual(edited.penaltyAmount, 200)
    }

    // MARK: - Decode sanitizes legacy garbage instead of throwing

    func testDecode_clampsOutOfRangeSnoozeMinutes() throws {
        let low = try decodeLegacyAlarm(snoozeMinutesJSON: "0")
        XCTAssertEqual(low.snoozeMinutes, Alarm.snoozeMinutesRange.lowerBound)

        let high = try decodeLegacyAlarm(snoozeMinutesJSON: "999")
        XCTAssertEqual(high.snoozeMinutes, Alarm.snoozeMinutesRange.upperBound)
    }

    func testDecode_negativePenaltyDegradesToZero() throws {
        let alarm = try decodeLegacyAlarm(penaltyAmountJSON: "-50.0")
        XCTAssertEqual(alarm.penaltyAmount, 0)
    }

    func testDecode_dropsIllegalWeekdayIndices() throws {
        let alarm = try decodeLegacyAlarm(repeatDaysJSON: "[-1, 2, 8, 99]")
        XCTAssertEqual(alarm.repeatDays, [2])
    }

    func testDecode_validValuesRoundTripUnchanged() throws {
        let original = Alarm(
            repeatDays: [0, 1, 2, 3, 4],
            name: "Будни",
            snoozeMinutes: 9,
            penaltyAmount: 150,
            theme: .mountains
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Helper

    /// Hand-rolled pre-validation alarm JSON mimicking corrupt legacy storage
    /// that `Alarm(validating:...)` would reject today.
    private func decodeLegacyAlarm(
        repeatDaysJSON: String = "[]",
        snoozeMinutesJSON: String = "9",
        penaltyAmountJSON: String = "50.0"
    ) throws -> Alarm {
        let json = """
        {
            "id":"\(UUID().uuidString)",
            "time":770000000,
            "repeatDays":\(repeatDaysJSON),
            "name":"Legacy",
            "soundID":"radar",
            "vibrationEnabled":true,
            "snoozeMinutes":\(snoozeMinutesJSON),
            "penaltyAmount":\(penaltyAmountJSON),
            "progressiveScale":false,
            "enabled":true
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(Alarm.self, from: json)
    }
}
