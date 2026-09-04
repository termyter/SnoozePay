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
        // 16 is the first value above the canonical 1...15 range (#286).
        XCTAssertNil(Alarm(validating: UUID(), snoozeMinutes: 16))
        XCTAssertNil(Alarm(validating: UUID(), snoozeMinutes: 30))
    }

    func testValidatingInit_snoozeBoundariesSucceed() {
        // Both ends of the canonical 1...15 range construct successfully.
        XCTAssertEqual(Alarm(validating: UUID(), snoozeMinutes: 1)?.snoozeMinutes, 1)
        XCTAssertEqual(Alarm(validating: UUID(), snoozeMinutes: 15)?.snoozeMinutes, 15)
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
            snoozeMinutes: 15,
            penaltyAmount: 0
        )
        XCTAssertNotNil(alarm)
        XCTAssertEqual(alarm?.repeatDays, [0, 6])
        XCTAssertEqual(alarm?.snoozeMinutes, 15)
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

    // MARK: - The single volume clamp (#714)

    // The expression behind these assertions used to exist in four independent
    // copies (the model, both pickers, `AudioService`). They agreed byte for
    // byte, so nothing here changes behaviour — the point is that there is now
    // one implementation to hold to it, and these tests sit on that one.

    func testClampedVolume_nonFiniteFallsBackToFullVolume() {
        // The branch the whole invariant exists for. A corrupt alarm must ring
        // loudly enough to wake someone; silently degrading to 0 would turn bad
        // data into a missed alarm, which is the one failure this app cannot
        // have. `Int(_:)` on the percentage also traps on NaN (#704).
        XCTAssertEqual(Alarm.clampedVolume(Float.nan), 1.0)
        XCTAssertEqual(Alarm.clampedVolume(Float.infinity), 1.0)
        // Negative infinity is non-finite first and negative second, so it also
        // rings full — not 0. Pinned because the order is easy to flip.
        XCTAssertEqual(Alarm.clampedVolume(-Float.infinity), 1.0)
    }

    func testClampedVolume_clampsOutOfRangeToTheNearestBound() {
        XCTAssertEqual(Alarm.clampedVolume(-0.2), 0.0)
        XCTAssertEqual(Alarm.clampedVolume(-99), 0.0)
        XCTAssertEqual(Alarm.clampedVolume(1.4), 1.0)
        XCTAssertEqual(Alarm.clampedVolume(99), 1.0)
    }

    func testClampedVolume_leavesTheBoundsAndInRangeValuesAlone() {
        // Exactly 0 and exactly 1 are legal inputs, not edges to be nudged.
        XCTAssertEqual(Alarm.clampedVolume(0.0), 0.0)
        XCTAssertEqual(Alarm.clampedVolume(1.0), 1.0)
        XCTAssertEqual(Alarm.clampedVolume(0.5), 0.5)
        XCTAssertEqual(Alarm.clampedVolume(0.755), 0.755)
    }

    func testClampedVolume_isWhatTheDecodePathApplies() throws {
        // Ties the shared helper to the persisted path: same input, same value.
        for raw in [Float.nan, -0.2, 0, 0.5, 1, 1.4] {
            let stored = try XCTUnwrap(Alarm(validating: UUID(), volume: raw)?.volume)
            XCTAssertEqual(
                stored,
                Alarm.clampedVolume(raw),
                "construction diverged from the shared clamp for \(raw)"
            )
        }
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

    /// Legacy alarms persisted under the old 1...30 spec carry snoozeMinutes
    /// 16–30. They must SURVIVE the tighter 1...15 range — clamped to 15, not
    /// dropped or trapped (#286).
    func testDecode_clampsLegacySixteenToFifteen() throws {
        let alarm = try decodeLegacyAlarm(snoozeMinutesJSON: "16")
        XCTAssertEqual(alarm.snoozeMinutes, 15)
    }

    func testDecode_clampsLegacyThirtyToFifteen() throws {
        let alarm = try decodeLegacyAlarm(snoozeMinutesJSON: "30")
        XCTAssertEqual(alarm.snoozeMinutes, 15)
    }

    /// Boundary value 15 round-trips unchanged through decode.
    func testDecode_preservesInRangeSnoozeMinutes() throws {
        let alarm = try decodeLegacyAlarm(snoozeMinutesJSON: "15")
        XCTAssertEqual(alarm.snoozeMinutes, 15)
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
