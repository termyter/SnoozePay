import XCTest
@testable import SnoozePay

/// Round-trip and malformed-input coverage for the typed notification payload.
///
/// The struct is the single source of truth for what we put into and read out
/// of `UNNotificationContent.userInfo`. Three independent reader sites used to
/// scrape this dict with stringly-typed `as?` casts; a single key typo or type
/// mismatch silently dropped a snooze. These tests guarantee we surface that
/// kind of regression instead of returning a partially-populated struct.
final class AlarmNotificationPayloadTests: XCTestCase {

    // MARK: - Construction from Alarm

    func testInit_fromAlarm_copiesAllFields() {
        let alarm = Alarm(
            id: UUID(),
            name: "Утренний",
            soundID: "morning_bells",
            snoozeMinutes: 7,
            penaltyAmount: 75,
            progressiveScale: true
        )
        let payload = AlarmNotificationPayload(alarm: alarm, snoozeCount: 2)

        XCTAssertEqual(payload.alarmID, alarm.id)
        XCTAssertEqual(payload.penaltyAmount, 75)
        XCTAssertEqual(payload.progressiveScale, true)
        XCTAssertEqual(payload.snoozeCount, 2)
        XCTAssertEqual(payload.snoozeMinutes, 7)
        XCTAssertEqual(payload.soundID, "morning_bells")
    }

    // MARK: - Round-trip

    func testRoundTrip_preservesAllFields() {
        let original = AlarmNotificationPayload(
            alarmID: UUID(),
            penaltyAmount: 125,
            progressiveScale: true,
            snoozeCount: 4,
            snoozeMinutes: 9,
            soundID: "radar"
        )

        let dict = original.asUserInfo()
        let decoded = AlarmNotificationPayload(userInfo: dict)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTrip_throughAnyHashableDict_preservesFields() {
        // UNNotificationContent.userInfo is exposed as `[AnyHashable: Any]` to
        // callers — round-trip through that shape too, in case Foundation
        // ever bridges the keys differently from a plain `[String: Any]`.
        let original = AlarmNotificationPayload(
            alarmID: UUID(),
            penaltyAmount: 50,
            progressiveScale: false,
            snoozeCount: 0,
            snoozeMinutes: 9,
            soundID: "default_alarm"
        )

        let raw = original.asUserInfo()
        let bridged: [AnyHashable: Any] = raw.reduce(into: [:]) { acc, pair in
            acc[pair.key] = pair.value
        }
        let decoded = AlarmNotificationPayload(userInfo: bridged)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - asUserInfo emits Plist-compatible types

    func testAsUserInfo_emitsExpectedKeys() {
        let payload = AlarmNotificationPayload(
            alarmID: UUID(),
            penaltyAmount: 100,
            progressiveScale: true,
            snoozeCount: 1,
            snoozeMinutes: 5,
            soundID: "radar"
        )
        let dict = payload.asUserInfo()

        XCTAssertEqual(Set(dict.keys), [
            "alarmID",
            "penaltyAmount",
            "progressiveScale",
            "snoozeCount",
            "snoozeMinutes",
            "soundID"
        ])
        XCTAssertTrue(dict["alarmID"] is String)
        XCTAssertTrue(dict["penaltyAmount"] is Double)
        XCTAssertTrue(dict["progressiveScale"] is Bool)
        XCTAssertTrue(dict["snoozeCount"] is Int)
        XCTAssertTrue(dict["snoozeMinutes"] is Int)
        XCTAssertTrue(dict["soundID"] is String)
    }

    // MARK: - Malformed input → nil

    func testInit_emptyUserInfo_returnsNil() {
        XCTAssertNil(AlarmNotificationPayload(userInfo: [:]))
    }

    func testInit_missingAlarmID_returnsNil() {
        let dict: [AnyHashable: Any] = [
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_invalidUUIDString_returnsNil() {
        let dict: [AnyHashable: Any] = [
            "alarmID": "not-a-real-uuid",
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_alarmIDAsUUIDInsteadOfString_returnsNil() {
        // Defensive: someone could try to put a UUID() directly. We require the
        // string representation because that's what survives Plist encoding
        // through the notification daemon.
        let dict: [AnyHashable: Any] = [
            "alarmID": UUID(),
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_penaltyAsString_returnsNil() {
        let dict: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": "50",
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_snoozeCountAsDouble_returnsNil() {
        // We require Int specifically — a Double would silently discard the
        // user's intent if someone in a callsite ever wrote `5.5`.
        let dict: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0.5,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_progressiveScaleMissing_returnsNil() {
        let dict: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_soundIDMissing_returnsNil() {
        let dict: [AnyHashable: Any] = [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_typoedKeyAlarmId_returnsNil() {
        // Regression: the original silent-failure path caught by /audit was
        // exactly this — someone read `"alarmId"` (lowercase d) instead of
        // `"alarmID"`. Now the entire payload bails so the typo is loud.
        let dict: [AnyHashable: Any] = [
            "alarmId": UUID().uuidString,
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    // MARK: - Out-of-range values rejected (issue #208)

    private func validDict() -> [AnyHashable: Any] {
        [
            "alarmID": UUID().uuidString,
            "penaltyAmount": 50.0,
            "progressiveScale": false,
            "snoozeCount": 0,
            "snoozeMinutes": 9,
            "soundID": "radar"
        ]
    }

    func testInit_negativeSnoozeCount_returnsNil() {
        var dict = validDict()
        dict["snoozeCount"] = -1
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict),
                     "negative snoozeCount would yield pow(2.0, negative) → silently shrunk penalty")
    }

    func testInit_zeroSnoozeMinutes_returnsNil() {
        var dict = validDict()
        dict["snoozeMinutes"] = 0
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict),
                     "0 minutes would schedule a trigger at the current instant")
    }

    func testInit_excessiveSnoozeMinutes_returnsNil() {
        var dict = validDict()
        dict["snoozeMinutes"] = 61
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict),
                     "spec caps snoozeMinutes at 30; >60 is clearly out-of-range")
    }

    func testInit_negativePenaltyAmount_returnsNil() {
        var dict = validDict()
        dict["penaltyAmount"] = -10.0
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_nanPenaltyAmount_returnsNil() {
        var dict = validDict()
        dict["penaltyAmount"] = Double.nan
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict),
                     "NaN penalty would silently disable charge (current >= NaN is false)")
    }

    func testInit_infinitePenaltyAmount_returnsNil() {
        var dict = validDict()
        dict["penaltyAmount"] = Double.infinity
        XCTAssertNil(AlarmNotificationPayload(userInfo: dict))
    }

    func testInit_validBoundaryValues_succeeds() {
        // snoozeMinutes == 1 and snoozeMinutes == 60 must be accepted —
        // boundary regressions are the typical fallout when ranges tighten.
        var dict = validDict()
        dict["snoozeMinutes"] = 1
        XCTAssertNotNil(AlarmNotificationPayload(userInfo: dict))
        dict["snoozeMinutes"] = 60
        XCTAssertNotNil(AlarmNotificationPayload(userInfo: dict))
        dict["snoozeMinutes"] = 9
        dict["snoozeCount"] = 0
        dict["penaltyAmount"] = 0.0
        XCTAssertNotNil(AlarmNotificationPayload(userInfo: dict),
                        "Zero penalty / zero count must round-trip (legit fresh-fire state)")
    }

    // MARK: - Compatibility with existing keys
    //
    // The keys here are the exact strings AlarmScheduler / AlarmFiringCoordinator
    // / AppDelegate used before this refactor. Pinning them in a test guarantees
    // a future rename can't silently invalidate a notification that was
    // scheduled by an older build still pending in the system queue.

    func testKeys_areStableContract() {
        XCTAssertEqual(AlarmNotificationPayload.Key.alarmID, "alarmID")
        XCTAssertEqual(AlarmNotificationPayload.Key.penaltyAmount, "penaltyAmount")
        XCTAssertEqual(AlarmNotificationPayload.Key.progressiveScale, "progressiveScale")
        XCTAssertEqual(AlarmNotificationPayload.Key.snoozeCount, "snoozeCount")
        XCTAssertEqual(AlarmNotificationPayload.Key.snoozeMinutes, "snoozeMinutes")
        XCTAssertEqual(AlarmNotificationPayload.Key.soundID, "soundID")
    }
}
