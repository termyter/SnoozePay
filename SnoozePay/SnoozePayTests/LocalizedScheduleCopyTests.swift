import XCTest
@testable import SnoozePay

/// Guards the second batch of #598 — the model-level copy that renders a
/// repeat schedule (`Weekday`, `Alarm`, `AlarmDeletionCopy`) and the theme
/// picker's names and subtitles (`AlarmTheme`, `AlarmThemeSubtitles`).
///
/// Why this exists next to `AlarmModelTests`, `WeekdayTests`,
/// `AlarmThemeTests`, `SoundThemePickerCatalogueTests` and
/// `AlarmDeletionCopyTests`, all of which already pin the exact Russian
/// strings: those files go red on a *missing* key, because `Localized.text`
/// echoes the key and «Рассвет» ≠ `create_alarm.theme.name.dawn`. What they
/// cannot see are the three failures this migration actually introduces —
///
/// 1. a key that resolves but is wired to the wrong entry, when two entries
///    hold interchangeable-looking copy;
/// 2. a format string whose specifier survived into the rendered text,
///    because `String(format:)` fails silently rather than throwing;
/// 3. copy quietly moving *into* the catalogue that does not belong there —
///    weekday names are calendar data and must keep coming from CLDR (#569).
///
/// All three are asserted structurally (distinctness, absence of `%`, identity
/// with `WeekdayNames`), which is the part a byte-comparison against the old
/// literals cannot cover.
final class LocalizedScheduleCopyTests: XCTestCase {

    /// The keys this batch introduced.
    ///
    /// Maintained by hand, and nothing forces a future key into it — the list
    /// is a checklist, not a gate. What it does buy is that all 25 are checked
    /// for presence in one place, so a typo in a key that only one rarely-hit
    /// branch reads still fails the suite.
    private static let migratedKeys = [
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

    /// Weekday names are calendar data, not catalogue copy (#569). This pins
    /// the seam rather than the seven strings — `WeekdayTests` and
    /// `ViewModelLocalizationTests` already pin those — because the regression
    /// worth catching is someone giving `Weekday` its own `common.weekday.*`
    /// entries again. On the day `en` ships, that split is what makes one alarm
    /// card render its caps row from CLDR and its detail line from a
    /// translator's table.
    func testWeekdayShortNamesComeFromTheCalendarNotTheCatalogue() {
        XCTAssertEqual(
            Weekday.allCases.sorted { $0.legacyMondayFirstIndex < $1.legacyMondayFirstIndex }
                .map(\.localizedShortName),
            WeekdayNames.short,
            "Weekday stopped reading WeekdayNames — the alarm card can now disagree with itself"
        )
    }

    /// The index guard, which exists because `WeekdayNames.mondayFirst(_:)`
    /// returns `[]` rather than throwing when Foundation hands back anything
    /// but seven symbols. Every case must land inside the array it indexes.
    func testEveryWeekdayResolvesToANonEmptyName() {
        for day in Weekday.allCases {
            XCTAssertFalse(
                day.localizedShortName.isEmpty,
                "\(day) fell through the index guard in localizedShortName"
            )
        }
    }

    // MARK: - Alarm

    /// The default name moved from a literal default argument to
    /// `Alarm.defaultName`. Both initializers have to have moved: the
    /// validating one is the boundary, the historical one is what the app
    /// actually calls.
    func testBothInitializersDefaultToTheCatalogueName() {
        // Pinned to the literal, not just to itself: a self-comparison is
        // green whatever the catalogue holds. Since #623 the value is no
        // longer a sentinel — an unnamed alarm stores no name and resolves
        // this at display time — so changing it changes copy only, which is
        // exactly what this assertion is here to make visible.
        XCTAssertEqual(Alarm.defaultName, "Будильник")
        XCTAssertEqual(Alarm().name, Alarm.defaultName)
        XCTAssertEqual(Alarm(validating: UUID())?.name, Alarm.defaultName)
    }

    /// `repeatDaysDescription` stopped carrying its own weekday table and now
    /// reads `Weekday.localizedShortName` — the same CLDR names the caps row,
    /// the delete sheet and the day picker read. Asserting that identity as
    /// well as the literal is what pins them together: a future PR that gives
    /// the alarm card its own weekday source goes red here, which is the point.
    func testSubsetDescriptionIsBuiltFromTheSharedWeekdayNames() {
        let alarm = Alarm(validating: UUID(), repeatDays: [3, 1])
        XCTAssertEqual(
            alarm?.repeatDaysDescription,
            [Weekday.tuesday, .thursday].map(\.localizedShortName).joined(separator: ", ")
        )
        XCTAssertEqual(alarm?.repeatDaysDescription, "Вт, Чт", "sorted Mon-first, comma separated")
    }

    /// Corrupt storage carries weekday indices outside `0...6` (#72). The old
    /// table dropped them through a `[safe:]` subscript that this batch
    /// deleted, so the question is whether the replacement still holds.
    ///
    /// It is asserted through the decoder rather than through an initializer
    /// because that is the only path such a value can travel: `repeatDays` is
    /// `let`, `init(validating:)` returns `nil`, and the historical `init`
    /// calls `preconditionFailure`. The `compactMap` inside
    /// `repeatDaysDescription` is therefore defence in depth and cannot be
    /// reached directly — what a test *can* pin is that the pair
    /// (decoder sanitizes, description renders the survivors) still produces
    /// «Вт, Чт», which is the behaviour the user sees.
    func testCorruptWeekdayIndicesSurviveAsTheDaysThatAreStillValid() {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "time": 0,
            "repeatDays": [-1, 1, 3, 99],
            "name": "Test",
            "soundID": "radar",
            "vibrationEnabled": true,
            "snoozeMinutes": 9,
            "penaltyAmount": 50,
            "progressiveScale": false,
            "enabled": true
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let alarm = try? JSONDecoder().decode(Alarm.self, from: data)
        else {
            return XCTFail("a legacy alarm payload must stay decodable")
        }
        XCTAssertEqual(alarm.repeatDays, [1, 3], "the decoder is what drops the bad indices")
        XCTAssertEqual(alarm.repeatDaysDescription, "Вт, Чт")
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

    /// `SoundThemePickerCatalogueTests` pins «Тёплый янтарь» and «Холодный
    /// мятный»; the other four subtitles were only checked for being distinct
    /// and non-empty, which a «ё»→«е» slip or a swapped pair passes green.
    func testRemainingThemeSubtitlesKeepTheirExactCopy() {
        let expected: [(AlarmTheme, String)] = [
            (.mountains, "Молочный свет"),
            (.forest, "Хвойный сумрак"),
            (.neon, "Городская ночь"),
            (.abstract, "Чистый цвет")
        ]
        for (theme, text) in expected {
            XCTAssertEqual(AlarmThemeSubtitles.subtitle(for: theme), text, theme.id)
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

    /// Two `compactDayPhrase` branches migrated to the catalogue without any
    /// test entering them: `AlarmDeletionCopyTests` covers the weekdays range
    /// but not the all-week and weekend ones. A wrong key in either renders the
    /// key itself on the delete sheet.
    func testOneShotCompactRangesCoverAllWeekAndWeekend() {
        let sevenAM = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        XCTAssertEqual(
            AlarmDeletionCopy.contextLine(
                repeatDays: Array(0...6), repeatMode: .never, time: sevenAM
            ),
            "Единожды · Пн–Вс · 07:00"
        )
        XCTAssertEqual(
            AlarmDeletionCopy.contextLine(repeatDays: [5, 6], repeatMode: .never, time: sevenAM),
            "Единожды · Сб–Вс · 07:00"
        )
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
