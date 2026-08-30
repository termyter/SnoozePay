import XCTest
@testable import SnoozePay

/// Guards the second batch of #598 — the model-level copy that renders a
/// repeat schedule (`Weekday`, `Alarm`, `AlarmDeletionCopy`) and the theme
/// picker's names and subtitles (`AlarmTheme`, `AlarmThemeSubtitles`).
///
/// Why this exists next to `AlarmModelTests`, `WeekdayTests`,
/// `AlarmThemeTests`, `SoundThemePickerCatalogueTests` and
/// `AlarmDeletionCopyTests`, all of which already pin the exact Russian
/// strings: those files would go red on a *missing* key (`Localized.text`
/// echoes the key, and "Пн" ≠ "common.weekday.short.mon"), but they cannot
/// distinguish the two failures this migration actually introduces —
///
/// 1. a key that resolves but is wired to the wrong entry, when two entries
///    happen to hold interchangeable-looking copy;
/// 2. a format string whose specifier survived into the rendered text,
///    because `String(format:)` fails silently rather than throwing.
///
/// Both are asserted structurally here (distinctness, absence of `%`), which
/// is the part a byte-comparison against the old literals cannot cover.
final class LocalizedScheduleCopyTests: XCTestCase {

    /// Every key this batch introduced. Listed once so that adding an entry to
    /// the catalogue without adding it here is the only way past the miss
    /// detector below.
    private static let migratedKeys = [
        "common.weekday.short.mon",
        "common.weekday.short.tue",
        "common.weekday.short.wed",
        "common.weekday.short.thu",
        "common.weekday.short.fri",
        "common.weekday.short.sat",
        "common.weekday.short.sun",
        "alarms.default_name",
        "alarms.days.weekdays_plain",
        "alarms.days.weekend_range",
        "alarms.delete.once_at",
        "alarms.delete.once_on_at",
        "alarms.delete.schedule_at",
        "alarms.delete.range_all",
        "alarms.delete.range_weekdays",
        "alarms.delete.range_weekend",
        "alarms.delete.reassurance",
        "alarms.delete.body",
        "create_alarm.theme.name.dawn",
        "create_alarm.theme.name.mountains",
        "create_alarm.theme.name.ocean",
        "create_alarm.theme.name.forest",
        "create_alarm.theme.name.neon",
        "create_alarm.theme.name.abstract",
        "create_alarm.theme.name.custom",
        "create_alarm.theme.subtitle.dawn",
        "create_alarm.theme.subtitle.ocean",
        "create_alarm.theme.subtitle.mountains",
        "create_alarm.theme.subtitle.forest",
        "create_alarm.theme.subtitle.neon",
        "create_alarm.theme.subtitle.abstract",
        "create_alarm.theme.subtitle.custom"
    ]

    /// Keys this batch deliberately *reuses* rather than duplicating: the alarm
    /// card and the delete sheet say the same four things, and a second entry
    /// holding the same Russian is a second entry to keep in sync forever.
    private static let reusedKeys = [
        "alarms.days.once",
        "alarms.days.every_day",
        "alarms.days.weekend",
        "alarms.days.weekdays"
    ]

    // MARK: - The keys exist

    func testEveryMigratedKeyResolvesToCopyRatherThanToItself() {
        for key in Self.migratedKeys + Self.reusedKeys {
            let copy = Localized.text(key)
            XCTAssertNotEqual(copy, key, "missing catalogue key: \(key)")
            XCTAssertFalse(copy.isEmpty, "empty catalogue value for: \(key)")
        }
    }

    // MARK: - Weekday

    /// Seven cases, seven keys, and the failure a `switch` invites is pointing
    /// two of them at one entry. `WeekdayTests` pins the values; this pins that
    /// no two are the same, which is what a copy-pasted key line produces.
    func testWeekdayShortNamesAreSevenDistinctPiecesOfCopy() {
        let names = Weekday.allCases.map(\.localizedShortName)
        XCTAssertEqual(Set(names).count, 7, "two weekdays share a catalogue key: \(names)")
        for name in names {
            XCTAssertTrue(
                name.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil,
                "reads as a key rather than as copy: \(name)"
            )
        }
    }

    // MARK: - Alarm

    /// The default name moved from a literal default argument to
    /// `Alarm.defaultName`. Both initializers have to have moved: the
    /// validating one is the boundary, the historical one is what the app
    /// actually calls.
    func testBothInitializersDefaultToTheCatalogueName() {
        XCTAssertEqual(Alarm().name, Alarm.defaultName)
        XCTAssertEqual(Alarm(validating: UUID())?.name, Alarm.defaultName)
        XCTAssertNotEqual(Alarm.defaultName, "alarms.default_name")
    }

    /// `repeatDaysDescription` stopped carrying its own weekday table and now
    /// reads `Weekday.localizedShortName` — the same entries the delete sheet
    /// and the day picker read. Asserting the identity rather than the literal
    /// is what pins them together: a future PR that gives the alarm card its
    /// own `alarms.weekday.*` keys goes red here, which is the point.
    func testSubsetDescriptionIsBuiltFromTheSharedWeekdayNames() {
        let alarm = Alarm(validating: UUID(), repeatDays: [3, 1])
        XCTAssertEqual(
            alarm?.repeatDaysDescription,
            [Weekday.tuesday, .thursday].map(\.localizedShortName).joined(separator: ", ")
        )
        XCTAssertEqual(alarm?.repeatDaysDescription, "Вт, Чт", "sorted Mon-first, comma separated")
    }

    /// «Будни» (the card's narrow form) and «Будни · Пн–Пт» (the delete
    /// sheet's) are two entries on purpose. Wiring the alarm card to the wrong
    /// one is invisible in a diff and obvious on screen.
    func testWeekdayBucketKeepsTheNarrowFormOnTheAlarmItself() {
        let weekdays = Alarm(validating: UUID(), repeatDays: [0, 1, 2, 3, 4])
        XCTAssertEqual(weekdays?.repeatDaysDescription, "Будни")
        XCTAssertNotEqual(
            Localized.text("alarms.days.weekdays_plain"),
            Localized.text("alarms.days.weekdays"),
            "the two weekday buckets collapsed into one entry"
        )
    }

    // MARK: - Theme picker

    func testThemeNamesAndSubtitlesAreDistinctPerBuiltInTheme() {
        let themes = AlarmTheme.builtInOrder
        let names = themes.map(\.displayName)
        let subtitles = themes.map(AlarmThemeSubtitles.subtitle(for:))

        XCTAssertEqual(Set(names).count, themes.count, "two themes share a name key: \(names)")
        XCTAssertEqual(
            Set(subtitles).count, themes.count,
            "two themes share a subtitle key: \(subtitles)"
        )
        for copy in names + subtitles {
            XCTAssertFalse(copy.contains("create_alarm."), "unresolved key: \(copy)")
        }
    }

    /// The custom slot is the one case that is not in the id→key map: it is
    /// matched by pattern before the lookup. A regression there returns "" and
    /// the tile loses its second line without anything else noticing.
    func testCustomThemeSlotStillCarriesNameAndSubtitle() {
        let custom = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/tmp/x.jpg"))
        XCTAssertEqual(custom.displayName, Localized.text("create_alarm.theme.name.custom"))
        XCTAssertEqual(
            AlarmThemeSubtitles.subtitle(for: custom),
            Localized.text("create_alarm.theme.subtitle.custom")
        )
        XCTAssertFalse(AlarmThemeSubtitles.customSlotSubtitle.isEmpty)
    }

    // MARK: - Delete sheet substitutions

    /// Four of the delete sheet's strings are now format strings. A wrong
    /// argument count or a mistyped specifier leaves `%@` in the sentence the
    /// user reads — `String(format:)` neither throws nor logs.
    func testDeleteSheetLeavesNoUnsubstitutedSpecifiers() {
        let sevenAM = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let lines = [
            AlarmDeletionCopy.contextLine(repeatDays: [], repeatMode: .weekly, time: sevenAM),
            AlarmDeletionCopy.contextLine(repeatDays: [0, 1], repeatMode: .never, time: sevenAM),
            AlarmDeletionCopy.contextLine(repeatDays: [5, 6], repeatMode: .weekly, time: sevenAM),
            AlarmDeletionCopy.body(balance: 840),
            AlarmDeletionCopy.body(contextLine: "Будни · Пн–Пт · 07:00", balance: 840)
        ]
        for line in lines {
            XCTAssertFalse(line.contains("%"), "a specifier was left unsubstituted: \(line)")
            XCTAssertTrue(
                line.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil,
                "reads as a key rather than as copy: \(line)"
            )
        }
    }

    /// The reassurance sentence and the two-sentence body are separate keys, so
    /// the sheet's own text must contain the reassurance verbatim rather than a
    /// re-worded copy of it — that is what makes «context. reassurance» a
    /// translatable join instead of a Swift concatenation frozen into Russian.
    func testBodyWithContextContainsTheStandaloneReassuranceVerbatim() {
        let standalone = AlarmDeletionCopy.body(balance: 840)
        let joined = AlarmDeletionCopy.body(contextLine: "Каждый день · 07:00", balance: 840)
        XCTAssertTrue(joined.hasSuffix(standalone), "\(joined) does not end with \(standalone)")
        XCTAssertTrue(joined.hasPrefix("Каждый день · 07:00"), joined)
    }
}
