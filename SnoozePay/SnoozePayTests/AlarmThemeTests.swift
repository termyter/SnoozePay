import XCTest
@testable import SnoozePay

/// Coverage for `AlarmTheme` Codable + the `Alarm` migration path that lets
/// pre-#151 alarms decode cleanly without a `theme` field. The migration is
/// the contract that ships #151 safely on top of #143 — without it,
/// `AlarmRepository.readAll()` would throw `decodeFailure` on every existing
/// install and lock the entire alarm store via `_lastLoadFailed`.
final class AlarmThemeTests: XCTestCase {

    // MARK: - AlarmTheme round-trip

    func testBuiltInThemesRoundTripThroughJSON() throws {
        for theme in AlarmTheme.builtInOrder {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AlarmTheme.self, from: data)
            XCTAssertEqual(decoded, theme, "Round-trip failed for \(theme.id)")
        }
    }

    func testCustomThemeRoundTripPreservesPath() throws {
        let url = URL(fileURLWithPath: "/var/mobile/Caches/AlarmThemes/IMG.jpg")
        let theme = AlarmTheme.custom(imagePath: url)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(AlarmTheme.self, from: data)
        if case .custom(let decodedURL) = decoded {
            XCTAssertEqual(decodedURL.absoluteString, url.absoluteString)
        } else {
            XCTFail("Expected .custom, got \(decoded)")
        }
    }

    func testUnknownThemeIDDecodesAsDawn() throws {
        let json = #"{"id":"made-up-future-theme"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AlarmTheme.self, from: json)
        XCTAssertEqual(decoded, .dawn)
    }

    func testCustomWithoutPathDecodesAsDawn() throws {
        // `.custom` requires `imagePath`. A corrupt entry without the path
        // should degrade to `.dawn` rather than throw — a missing theme
        // must not block the entire alarm decode.
        let json = #"{"id":"custom"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AlarmTheme.self, from: json)
        XCTAssertEqual(decoded, .dawn)
    }

    // MARK: - Alarm migration

    func testLegacyAlarmJSONWithoutThemeDecodesWithDawnDefault() throws {
        // Hand-rolled JSON identical to a pre-#151 stored alarm — the
        // `theme` key is intentionally absent. Must decode to `.dawn` so
        // `AlarmRepository.readAll()` doesn't throw `decodeFailure` on
        // every existing install (issues #72 / #117).
        let json = """
        {
            "id":"\(UUID().uuidString)",
            "time":\(Date().timeIntervalSinceReferenceDate),
            "repeatDays":[0,1,2],
            "name":"Утренний",
            "soundID":"radar",
            "vibrationEnabled":true,
            "snoozeMinutes":9,
            "penaltyAmount":50.0,
            "progressiveScale":false,
            "enabled":true
        }
        """.data(using: .utf8)!
        let alarm = try JSONDecoder().decode(Alarm.self, from: json)
        XCTAssertEqual(alarm.theme, .dawn)
        XCTAssertEqual(alarm.name, "Утренний")
    }

    func testNewAlarmEncodesAndDecodesWithExplicitTheme() throws {
        let alarm = Alarm(
            penaltyAmount: 100,
            theme: .ocean
        )
        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(decoded.theme, .ocean)
    }

    func testAlarmListDecodesMixedLegacyAndNewEntries() throws {
        // Real-world AlarmRepository state right after the user upgrades:
        // some alarms were saved before #151 (no `theme`), some after.
        let legacyID = UUID()
        let modernID = UUID()
        let json = """
        [
            {
                "id":"\(legacyID.uuidString)",
                "time":770000000,
                "repeatDays":[],
                "name":"Старый",
                "soundID":"dawn",
                "vibrationEnabled":false,
                "snoozeMinutes":5,
                "penaltyAmount":25.0,
                "progressiveScale":false,
                "enabled":true
            },
            {
                "id":"\(modernID.uuidString)",
                "time":770003600,
                "repeatDays":[1,2,3],
                "name":"Новый",
                "soundID":"radar",
                "vibrationEnabled":true,
                "snoozeMinutes":9,
                "penaltyAmount":50.0,
                "progressiveScale":true,
                "enabled":true,
                "theme":{"id":"abstract"}
            }
        ]
        """.data(using: .utf8)!
        let alarms = try JSONDecoder().decode([Alarm].self, from: json)
        XCTAssertEqual(alarms.count, 2)
        let legacy = alarms.first { $0.id == legacyID }
        let modern = alarms.first { $0.id == modernID }
        XCTAssertEqual(legacy?.theme, .dawn)
        XCTAssertEqual(modern?.theme, .abstract)
    }

    // MARK: - Display

    func testDisplayNamesAreLocalised() {
        XCTAssertEqual(AlarmTheme.dawn.displayName, "Рассвет")
        XCTAssertEqual(AlarmTheme.mountains.displayName, "Горы")
        XCTAssertEqual(AlarmTheme.ocean.displayName, "Океан")
        XCTAssertEqual(AlarmTheme.abstract.displayName, "Абстракция")
        let custom = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/x.jpg"))
        XCTAssertEqual(custom.displayName, "Своё фото")
    }
}
