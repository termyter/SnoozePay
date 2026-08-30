import XCTest
@testable import SnoozePay

/// Model-level coverage for "this alarm is still on its auto-assigned name"
/// (#623).
///
/// The state used to be re-derived on every render by comparing the persisted
/// `Alarm.name` against the literal `"будильник"`. That can only be correct
/// while exactly one language ships: the string on disk is written in the
/// locale the alarm was CREATED in, while the default it was compared against
/// is spelled in the locale the reader is RUNNING in. The two diverge the day
/// a translation lands, and the alarms list starts printing
/// `ALARM · БУДНИ · ПН–ПТ` — the duplication the suppression exists to avoid.
///
/// So the fact is stored instead: `customName == nil` means "the user never
/// typed a name". These tests pin the three things that have to survive —
/// construction, the `with(...)` mutator, and a decoder that must keep reading
/// records written before the flag existed.
///
/// Expected strings are literals rather than `Localized.text` reads: checking
/// the catalogue against the catalogue is green no matter what it holds.
final class AlarmDefaultNameTests: XCTestCase {

    // MARK: - Construction

    func testNewAlarm_hasNoUserName() {
        let alarm = Alarm()
        XCTAssertTrue(alarm.nameIsDefault, "An alarm nobody named is on the default")
        XCTAssertNil(alarm.customName)
        XCTAssertEqual(alarm.name, "Будильник", "Display falls back to the catalogue default")
        XCTAssertEqual(alarm.name, Alarm.defaultName)
    }

    func testValidatingInit_withoutName_hasNoUserName() {
        let alarm = Alarm(validating: UUID())
        XCTAssertEqual(alarm?.nameIsDefault, true)
        XCTAssertEqual(alarm?.name, Alarm.defaultName)
    }

    func testTypedName_isUserOwned() {
        let alarm = Alarm(name: "Спорт")
        XCTAssertFalse(alarm.nameIsDefault)
        XCTAssertEqual(alarm.customName, "Спорт")
        XCTAssertEqual(alarm.name, "Спорт")
    }

    /// Deliberate decision, not an accident of the implementation: the flag
    /// records PROVENANCE (did the user type a name?), not spelling. A user
    /// who types the word "Будильник" gets it rendered, because the alternative
    /// — hiding a typed name whenever it collides with today's default — is
    /// exactly the language-dependent behaviour this issue removed. It would
    /// hide the name in Russian and show it in English.
    func testTypedNameEqualToTheDefaultWord_staysUserOwned() {
        let alarm = Alarm(name: "Будильник")
        XCTAssertFalse(alarm.nameIsDefault, "The user typed it, so it is theirs")
        XCTAssertEqual(alarm.name, "Будильник")
    }

    /// A whitespace-only name is NOT promoted to "no name": `AlarmFiringViewModel`
    /// degrades a blank name to a bare time, and inventing "Будильник" for it
    /// would put a name back on the firing hero that the user never typed.
    /// The alarms-list caps row suppresses it on its own `trimmed.isEmpty` arm.
    func testWhitespaceName_staysAWhitespaceName() {
        let alarm = Alarm(name: "   ")
        XCTAssertFalse(alarm.nameIsDefault)
        XCTAssertEqual(alarm.name, "   ")
    }

    // MARK: - with(...)

    func testWith_otherField_preservesTheDefaultNameState() {
        let alarm = Alarm(repeatDays: [0], enabled: true)
        XCTAssertTrue(alarm.with(enabled: false).nameIsDefault,
                      "Toggling an alarm must not turn its default name into a typed one")
    }

    func testWith_name_marksTheNameAsUserOwned() {
        let renamed = Alarm().with(name: "Зал")
        XCTAssertFalse(renamed.nameIsDefault)
        XCTAssertEqual(renamed.name, "Зал")
    }

    func testWith_otherField_preservesAUserName() {
        let alarm = Alarm(name: "Спорт")
        let toggled = alarm.with(enabled: false)
        XCTAssertFalse(toggled.nameIsDefault)
        XCTAssertEqual(toggled.name, "Спорт")
    }

    // MARK: - Encoding

    func testEncode_writesResolvedNamePlusFlag() throws {
        let json = try encodedJSON(Alarm())
        XCTAssertEqual(json["nameIsDefault"] as? Bool, true)
        XCTAssertEqual(
            json["name"] as? String, "Будильник",
            "The resolved name still goes under the historical key so a build without the flag reads the record"
        )
    }

    func testEncode_userNameWritesFlagFalse() throws {
        let json = try encodedJSON(Alarm(name: "Спорт"))
        XCTAssertEqual(json["nameIsDefault"] as? Bool, false)
        XCTAssertEqual(json["name"] as? String, "Спорт")
    }

    /// `encode(to:)` is hand-rolled since #623, so a forgotten key would drop a
    /// field silently on the next save. Round-trip every one of them.
    func testEncodeDecode_roundTripsEveryField() throws {
        let alarm = Alarm(
            time: Date(timeIntervalSince1970: 1_700_000_000),
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

        let encoded = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: encoded)

        XCTAssertEqual(decoded, alarm, "A key missing from the hand-rolled encode shows up here")
        XCTAssertEqual(decoded.id, alarm.id)
        XCTAssertEqual(decoded.time, alarm.time)
        XCTAssertEqual(decoded.repeatDays, [1, 3, 5])
        XCTAssertEqual(decoded.customName, "Спорт")
        XCTAssertEqual(decoded.soundID, "morning_bells")
        XCTAssertFalse(decoded.vibrationEnabled)
        XCTAssertEqual(decoded.snoozeMinutes, 7)
        XCTAssertEqual(decoded.penaltyAmount, 175)
        XCTAssertTrue(decoded.progressiveScale)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.volume, 0.4, accuracy: 0.0001)
        XCTAssertTrue(decoded.volumeFadeIn)
        XCTAssertEqual(decoded.theme, .ocean)
        XCTAssertEqual(decoded.repeatMode, .never)
    }

    func testEncodeDecode_roundTripsTheDefaultNameState() throws {
        let encoded = try JSONEncoder().encode(Alarm())
        let decoded = try JSONDecoder().decode(Alarm.self, from: encoded)
        XCTAssertTrue(decoded.nameIsDefault)
        XCTAssertNil(decoded.customName)
    }

    // MARK: - Legacy decode (pre-#623 payloads)
    //
    // Records already on disk carry `name` and no `nameIsDefault`. They must
    // keep behaving exactly as they did, or this fix would buy a future bug at
    // the price of a present one.

    func testDecodeLegacy_defaultName_readsAsDefault() throws {
        let alarm = try decodeLegacy(name: "Будильник")
        XCTAssertTrue(alarm.nameIsDefault, "An existing default-named alarm must stay suppressed")
        XCTAssertEqual(alarm.name, "Будильник")
    }

    /// Parity with the comparison this replaces, which was
    /// `trimmed.lowercased() == "будильник"`.
    func testDecodeLegacy_defaultNameWithCaseAndPadding_readsAsDefault() throws {
        XCTAssertTrue(try decodeLegacy(name: "  БУДИЛЬНИК ").nameIsDefault)
    }

    func testDecodeLegacy_userName_staysUserOwned() throws {
        let alarm = try decodeLegacy(name: "Спорт")
        XCTAssertFalse(alarm.nameIsDefault)
        XCTAssertEqual(alarm.name, "Спорт")
    }

    func testDecodeLegacy_whitespaceName_isNotPromotedToDefault() throws {
        let alarm = try decodeLegacy(name: "   ")
        XCTAssertFalse(alarm.nameIsDefault)
        XCTAssertEqual(alarm.name, "   ", "A blank name must stay blank so the firing hero keeps degrading")
    }

    func testDecodeLegacy_preservesEveryOtherField() throws {
        let original = Alarm(repeatDays: [2], name: "Зал", penaltyAmount: 75, theme: .neon)
        var json = try encodedJSON(original)
        json.removeValue(forKey: "nameIsDefault")
        let decoded = try decode(json)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.repeatDays, original.repeatDays)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.penaltyAmount, original.penaltyAmount)
        XCTAssertEqual(decoded.theme, original.theme)
    }

    // MARK: - Cross-locale records

    /// The case the whole issue is about: a record written by a build running
    /// another language. The name on disk is that language's default, which no
    /// comparison against the Russian literal could ever match — the flag does.
    /// The display name re-resolves to the language in use, so the alarm reads
    /// as a default-named alarm everywhere rather than as one called "Alarm".
    func testDecode_defaultNameWrittenInAnotherLocale_readsAsDefault() throws {
        var json = try encodedJSON(Alarm())
        json["name"] = "Alarm"
        json["nameIsDefault"] = true

        let decoded = try decode(json)

        XCTAssertTrue(decoded.nameIsDefault)
        XCTAssertEqual(decoded.name, "Будильник", "The default follows the reader's language, not the writer's")
    }

    /// The mirror image: a user who typed a name that happens to be another
    /// language's default keeps it. The flag is written by whoever created the
    /// alarm and is never re-inferred from the string.
    func testDecode_flagFalse_keepsANameThatLooksLikeADefault() throws {
        var json = try encodedJSON(Alarm())
        json["name"] = "Alarm"
        json["nameIsDefault"] = false

        let decoded = try decode(json)

        XCTAssertFalse(decoded.nameIsDefault)
        XCTAssertEqual(decoded.name, "Alarm")
    }

    // MARK: - Helpers

    private func encodedJSON(_ alarm: Alarm) throws -> [String: Any] {
        let data = try JSONEncoder().encode(alarm)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> Alarm {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Alarm.self, from: data)
    }

    /// Encode an alarm, then strip the `nameIsDefault` key and overwrite the
    /// name — i.e. produce exactly the shape a pre-#623 build persisted.
    private func decodeLegacy(name: String) throws -> Alarm {
        var json = try encodedJSON(Alarm(repeatDays: [0, 1, 2, 3, 4], penaltyAmount: 50))
        json["name"] = name
        json.removeValue(forKey: "nameIsDefault")
        return try decode(json)
    }
}
