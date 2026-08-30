import XCTest
@testable import SnoozePay

/// The persisted contract of `Alarm` (#629).
///
/// `Alarm.encode(to:)` is hand-rolled, so the set of fields that reach disk is
/// a decision someone makes by hand every time the model grows. Since #629 the
/// encoder is driven by an exhaustive `switch` over `CodingKeys.allCases`,
/// which means a NEW KEY cannot be declared without the file failing to
/// compile until it is written. That covers the mechanical half.
///
/// This file covers the half a compiler cannot see:
///
/// 1. a new STORED PROPERTY that never got a key at all — caught by reflecting
///    over the value and comparing against the table below;
/// 2. a `switch` arm that visits a key and writes nothing — caught by
///    comparing the encoded key set against the same table;
/// 3. the wire format itself, which is live user data in `UserDefaults` under
///    `"stored_alarms"` and must survive a refactor of the encoder unchanged.
///
/// The legacy payloads here are hand-written JSON literals, deliberately. The
/// sibling checks in `AlarmDefaultNameTests` build their "old record" by
/// running TODAY's encoder and deleting a key, so they can only ever agree
/// with the current implementation — they would stay green through a change
/// that silently rewrote the stored shape. A literal cannot.
final class AlarmCodingContractTests: XCTestCase {

    // MARK: - The pinned contract

    /// Every stored property of `Alarm`, mapped to the key(s) it is persisted
    /// under. Adding a field to the model breaks
    /// `testStoredProperties_areAllAccountedFor` until it is listed here, and
    /// listing it is the moment to decide how it is stored and how records
    /// written before it existed should decode.
    ///
    /// Exactly one entry is not a 1:1 mapping: `customName` is optional and is
    /// written as the RESOLVED display name under the historical `name` key
    /// plus a separate `nameIsDefault` flag (#623), so a build that predates
    /// the flag still reads the record it always read.
    private static let storedPropertyToPersistedKeys: [String: [String]] = [
        "id": ["id"],
        "time": ["time"],
        "repeatDays": ["repeatDays"],
        "customName": ["name", "nameIsDefault"],
        "soundID": ["soundID"],
        "vibrationEnabled": ["vibrationEnabled"],
        "snoozeMinutes": ["snoozeMinutes"],
        "penaltyAmount": ["penaltyAmount"],
        "progressiveScale": ["progressiveScale"],
        "enabled": ["enabled"],
        "volume": ["volume"],
        "volumeFadeIn": ["volumeFadeIn"],
        "theme": ["theme"],
        "repeatMode": ["repeatMode"]
    ]

    private static var persistedKeys: Set<String> {
        Set(storedPropertyToPersistedKeys.values.flatMap { $0 })
    }

    private static let fixtureID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    /// 2023-11-14T22:13:20Z. Encoded as `timeIntervalSinceReferenceDate`
    /// (`JSONEncoder`'s default date strategy), i.e. `721692800`.
    private static let fixtureTime = Date(timeIntervalSince1970: 1_700_000_000)

    /// Every field set to something other than its default, so a value that
    /// stops being written shows up as a changed field rather than as a
    /// default that happens to match.
    private static var fullySpecifiedAlarm: Alarm {
        Alarm(
            id: fixtureID,
            time: fixtureTime,
            repeatDays: [1, 3, 5],
            name: "Спорт",
            soundID: "morning_bells",
            vibrationEnabled: false,
            snoozeMinutes: 7,
            penaltyAmount: 175,
            progressiveScale: true,
            enabled: false,
            volume: 0.4,
            volumeFadeIn: true,
            theme: .ocean,
            repeatMode: .never
        )
    }

    // MARK: - A field cannot go unaccounted for

    /// Reflection, not `CodingKeys`: the point is to catch a property that was
    /// added to the struct and NEVER given a key, which no read of the coding
    /// keys can see. `Mirror` over a value lists the stored properties, so the
    /// two sides of the comparison come from genuinely different places.
    func testStoredProperties_areAllAccountedFor() {
        let reflected = Set(Mirror(reflecting: Alarm()).children.compactMap { $0.label })

        XCTAssertEqual(
            reflected, Set(Self.storedPropertyToPersistedKeys.keys),
            """
            Alarm gained or lost a stored property. Decide how it is persisted \
            (encode(to:)), how records written before it existed decode \
            (init(from:) — decodeIfPresent + a documented default), then list \
            it in storedPropertyToPersistedKeys.
            """
        )
    }

    /// The exhaustive `switch` guarantees every key is VISITED; it cannot
    /// guarantee the arm writes anything (`case .foo: break` compiles). This
    /// is the check that closes that gap.
    func testEncode_writesExactlyThePinnedKeys() throws {
        let written = Set(try encodedJSON(Self.fullySpecifiedAlarm).keys)

        XCTAssertEqual(
            written, Self.persistedKeys,
            "The encoded record no longer matches the pinned key set — a field is being dropped or added silently"
        )
    }

    /// A default-named alarm writes the same key set as a user-named one:
    /// `name`/`nameIsDefault` are unconditional, never `encodeIfPresent`. A
    /// record that omitted `name` would throw `keyNotFound` on any build,
    /// which `AlarmRepository` reports as a fatal decode failure that locks
    /// the whole store (#72 / #117).
    func testEncode_defaultNamedAlarm_writesTheSameKeys() throws {
        XCTAssertEqual(Set(try encodedJSON(Alarm()).keys), Self.persistedKeys)
    }

    // MARK: - The wire format itself

    /// Value-by-value pin of what lands in `UserDefaults`. These literals
    /// describe the format as it shipped BEFORE the encoder was rewritten;
    /// the rewrite writes the same value under the same key, so the shape is
    /// unchanged. Order is deliberately NOT asserted — key order in the
    /// emitted JSON belongs to Foundation, not to us, and asserting it would
    /// pin a guarantee that never existed.
    ///
    /// Every field here holds a DISTINCT non-default value on purpose: that is
    /// what makes the test catch an arm that encodes the right key from the
    /// wrong property. Simplifying the fixture to defaults would quietly
    /// disarm it.
    func testEncodedPayload_hasTheShippedWireShape() throws {
        let json = try encodedJSON(Self.fullySpecifiedAlarm)

        XCTAssertEqual(json["id"] as? String, "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        XCTAssertEqual(json["time"] as? Double, 721_692_800)
        XCTAssertEqual(json["repeatDays"] as? [Int], [1, 3, 5])
        XCTAssertEqual(json["name"] as? String, "Спорт")
        XCTAssertEqual(json["nameIsDefault"] as? Bool, false)
        XCTAssertEqual(json["soundID"] as? String, "morning_bells")
        XCTAssertEqual(json["vibrationEnabled"] as? Bool, false)
        XCTAssertEqual(json["snoozeMinutes"] as? Int, 7)
        XCTAssertEqual(json["penaltyAmount"] as? Double, 175)
        XCTAssertEqual(json["progressiveScale"] as? Bool, true)
        XCTAssertEqual(json["enabled"] as? Bool, false)
        XCTAssertEqual(try XCTUnwrap(json["volume"] as? Double), 0.4, accuracy: 0.0001)
        XCTAssertEqual(json["volumeFadeIn"] as? Bool, true)
        XCTAssertEqual(json["repeatMode"] as? String, "never")
        // AlarmTheme keeps its own flat object form (`{"id": "ocean"}`).
        XCTAssertEqual((json["theme"] as? [String: Any])?["id"] as? String, "ocean")
    }

    /// The default-name pair, which is the reason the encoder is hand-rolled
    /// at all: the resolved string still goes under the historical key.
    func testEncodedPayload_defaultName_writesResolvedNamePlusFlag() throws {
        let json = try encodedJSON(Alarm())

        XCTAssertEqual(json["name"] as? String, "Будильник")
        XCTAssertEqual(json["nameIsDefault"] as? Bool, true)
    }

    // MARK: - Round trip

    func testRoundTrip_preservesEveryField() throws {
        let alarm = Self.fullySpecifiedAlarm

        let decoded = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(alarm))

        XCTAssertEqual(decoded, alarm)
        XCTAssertEqual(decoded.customName, "Спорт")
        XCTAssertEqual(decoded.volume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(decoded.theme, .ocean)
        XCTAssertEqual(decoded.repeatMode, .never)
    }

    /// Saving a record that was just loaded must not change it. This is the
    /// property that makes the app safe to open and close repeatedly: every
    /// launch re-encodes what it read, and a drifting shape would rewrite the
    /// user's store a little further from the format each time.
    func testEncodeDecodeEncode_isStable() throws {
        let firstData = try JSONEncoder().encode(Self.fullySpecifiedAlarm)
        let reloaded = try JSONDecoder().decode(Alarm.self, from: firstData)
        let first = try XCTUnwrap(try JSONSerialization.jsonObject(with: firstData) as? [String: Any])
        let second = try encodedJSON(reloaded)

        // Compared as parsed objects rather than raw bytes: the claim is that
        // no field drifts, not that Foundation spells a Float the same way twice.
        XCTAssertEqual(
            NSDictionary(dictionary: second), NSDictionary(dictionary: first),
            "Re-saving a loaded alarm changed the stored record"
        )
    }

    // MARK: - Records already on disk

    /// The shape a pre-#623 build wrote: `name`, no `nameIsDefault`.
    private static let preNameFlagPayload = """
    {
      "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
      "time": 721692800,
      "repeatDays": [0, 1, 2, 3, 4],
      "name": "Будильник",
      "soundID": "radar",
      "vibrationEnabled": true,
      "snoozeMinutes": 9,
      "penaltyAmount": 50,
      "progressiveScale": false,
      "enabled": true,
      "volume": 0.5,
      "volumeFadeIn": true,
      "theme": {"id": "forest"},
      "repeatMode": "never"
    }
    """

    /// The shape a pre-#150 build wrote: no `volume`, `volumeFadeIn`, `theme`,
    /// `repeatMode` or `nameIsDefault`. The oldest record that can still be
    /// sitting in a user's `UserDefaults`.
    private static let preVolumePayload = """
    {
      "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
      "time": 721692800,
      "repeatDays": [2],
      "name": "Зал",
      "soundID": "radar",
      "vibrationEnabled": true,
      "snoozeMinutes": 9,
      "penaltyAmount": 50,
      "progressiveScale": false,
      "enabled": true
    }
    """

    func testDecode_preNameFlagPayload_readsEveryFieldAndInfersTheFlag() throws {
        let alarm = try decode(Self.preNameFlagPayload)

        XCTAssertEqual(alarm.id, Self.fixtureID)
        XCTAssertEqual(alarm.time, Self.fixtureTime)
        XCTAssertEqual(alarm.repeatDays, [0, 1, 2, 3, 4])
        XCTAssertTrue(alarm.nameIsDefault, "The only default a pre-flag record can carry is the Russian one")
        XCTAssertNil(alarm.customName)
        XCTAssertEqual(alarm.soundID, "radar")
        XCTAssertTrue(alarm.vibrationEnabled)
        XCTAssertEqual(alarm.snoozeMinutes, 9)
        XCTAssertEqual(alarm.penaltyAmount, 50)
        XCTAssertFalse(alarm.progressiveScale)
        XCTAssertTrue(alarm.enabled)
        XCTAssertEqual(alarm.volume, 0.5, accuracy: 0.0001)
        XCTAssertTrue(alarm.volumeFadeIn)
        XCTAssertEqual(alarm.theme, .forest)
        XCTAssertEqual(alarm.repeatMode, .never)
    }

    func testDecode_preNameFlagPayload_withAUserName_keepsIt() throws {
        let payload = Self.preNameFlagPayload.replacingOccurrences(of: "\"Будильник\"", with: "\"Спорт\"")

        let alarm = try decode(payload)

        XCTAssertFalse(alarm.nameIsDefault)
        XCTAssertEqual(alarm.customName, "Спорт")
    }

    func testDecode_preVolumePayload_fillsTheDocumentedMigrationDefaults() throws {
        let alarm = try decode(Self.preVolumePayload)

        XCTAssertEqual(alarm.customName, "Зал")
        XCTAssertEqual(alarm.repeatDays, [2])
        XCTAssertEqual(alarm.volume, 1.0, accuracy: 0.0001, "pre-#150 alarms ring at full volume")
        XCTAssertFalse(alarm.volumeFadeIn)
        XCTAssertEqual(alarm.theme, .dawn, "pre-#151 alarms take the default theme")
        XCTAssertEqual(alarm.repeatMode, .weekly, "pre-#229 alarms repeat weekly")
    }

    /// The migration completing: an old record read by this build and saved
    /// back gains the flag, keeps the name, and keeps everything else.
    func testDecodeLegacyThenEncode_upgradesTheRecordWithoutLosingAnything() throws {
        let upgraded = try encodedJSON(try decode(Self.preVolumePayload))

        XCTAssertEqual(Set(upgraded.keys), Self.persistedKeys)
        XCTAssertEqual(upgraded["name"] as? String, "Зал")
        XCTAssertEqual(upgraded["nameIsDefault"] as? Bool, false)
        XCTAssertEqual(upgraded["id"] as? String, "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        XCTAssertEqual(upgraded["time"] as? Double, 721_692_800)
        XCTAssertEqual(upgraded["penaltyAmount"] as? Double, 50)
    }

    /// Forward compatibility: a record written by a NEWER build carries a key
    /// this one has never heard of. It must be ignored, not thrown on — a
    /// throw here locks the entire store for a user who rolled back.
    func testDecode_payloadFromANewerBuild_ignoresTheUnknownKey() throws {
        let payload = Self.preNameFlagPayload.replacingOccurrences(
            of: "\"repeatMode\": \"never\"",
            with: "\"repeatMode\": \"never\",\n  \"snoozeLimit\": 3"
        )

        let alarm = try decode(payload)

        XCTAssertEqual(alarm.repeatMode, .never)
        XCTAssertEqual(alarm.id, Self.fixtureID)
    }

    // MARK: - Helpers

    private func encodedJSON(_ alarm: Alarm) throws -> [String: Any] {
        let data = try JSONEncoder().encode(alarm)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ json: String) throws -> Alarm {
        try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))
    }
}
