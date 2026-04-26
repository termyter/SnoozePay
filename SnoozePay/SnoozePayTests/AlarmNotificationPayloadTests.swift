import XCTest
@testable import SnoozePay

/// Unit tests for `AlarmNotificationPayload` — the typed wrapper that replaced
/// the previously stringly-typed notification `userInfo` dictionary.
///
/// Locks two contracts:
/// - `payload → asUserInfo() → init?(userInfo:)` is a faithful round-trip.
/// - any malformed/missing/wrong-typed value yields `nil` (no silent defaults).
final class AlarmNotificationPayloadTests: XCTestCase {

    // MARK: - Round-trip

    func testRoundTrip_preservesAllFields() {
        let original = AlarmNotificationPayload(
            alarmID: UUID(),
            penalty: 75,
            snoozeCount: 2,
            soundID: "morning_bells"
        )

        let decoded = AlarmNotificationPayload(userInfo: original.asUserInfo())
        XCTAssertEqual(decoded, original)
    }

    func testRoundTrip_zeroSnoozeCountAndZeroPenalty() {
        // Boundary: a fresh fire (snoozeCount=0) + free alarm (penalty=0) should
        // still round-trip cleanly — guards against truthy-only checks creeping in.
        let original = AlarmNotificationPayload(
            alarmID: UUID(),
            penalty: 0,
            snoozeCount: 0,
            soundID: "radar"
        )

        XCTAssertEqual(AlarmNotificationPayload(userInfo: original.asUserInfo()), original)
    }

    func testAsUserInfo_usesExpectedKeys() {
        // Lock the wire format — these strings are what the system serialises into
        // the notification payload, so renaming them is a breaking change for any
        // notification that's already pending in the system queue.
        let payload = AlarmNotificationPayload(
            alarmID: UUID(),
            penalty: 50,
            snoozeCount: 0,
            soundID: "radar"
        )

        let userInfo = payload.asUserInfo()
        XCTAssertNotNil(userInfo["alarmID"])
        XCTAssertNotNil(userInfo["penaltyAmount"])
        XCTAssertNotNil(userInfo["snoozeCount"])
        XCTAssertNotNil(userInfo["soundID"])
    }

    // MARK: - Malformed userInfo

    func testInit_emptyUserInfo_isNil() {
        XCTAssertNil(AlarmNotificationPayload(userInfo: [:]))
    }

    func testInit_missingAlarmID_isNil() {
        let userInfo: [AnyHashable: Any] = [
            "penaltyAmount": 50.0,
            "snoozeCount": 0,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_invalidUUIDString_isNil() {
        let userInfo: [AnyHashable: Any] = [
            "alarmID": "not-a-uuid",
            "penaltyAmount": 50.0,
            "snoozeCount": 0,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_missingPenalty_isNil() {
        let userInfo: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "snoozeCount": 0,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_penaltyWrongType_isNil() {
        // A String where Double was expected — the previous stringly-typed
        // reader silently defaulted; the typed init rejects.
        let userInfo: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": "50",
            "snoozeCount": 0,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_missingSnoozeCount_isNil() {
        let userInfo: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_snoozeCountWrongType_isNil() {
        let userInfo: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "snoozeCount": "0",
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_missingSoundID_isNil() {
        let userInfo: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "snoozeCount": 0
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }

    func testInit_typoKey_isNil() {
        // The original motivation for #74 — a single typo (`"alarmId"` vs
        // `"alarmID"`) silently dropped snoozes. The typed init must reject it.
        let userInfo: [AnyHashable: Any] = [
            "alarmId": UUID().uuidString,
            "penaltyAmount": 50.0,
            "snoozeCount": 0,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: userInfo))
    }
}
