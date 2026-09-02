import XCTest
@testable import SnoozePay

/// Pins the copy that this slice of #598 moved out of `SoundCatalogue` and
/// into `Localizable.xcstrings`: ten sound names, ten descriptive subtitles
/// and the two strings of the disabled custom-melody slot.
///
/// `Localized.text` hands back the key on a miss, so a mistyped key ships as
/// `common.sound.name.dawn` in a picker row and the build stays green.
/// `SoundThemePickerCatalogueTests` would not notice either: it asserts that
/// names are non-empty, and a key is non-empty.
///
/// Three layers, so a red run names which one broke:
///
///  1. **Catalogue layer** — every key exists and does not resolve to itself.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration, transcribed from the pre-migration literals rather than
///     read back out of the file under test. A list derived from the catalogue
///     would agree with any mistake in it.
///  3. **Call-site layer** — the production accessors are invoked and what
///     they return is compared against the catalogue. Layers 1 and 2 are blind
///     to a typo in the *key* at the call site, because there the catalogue
///     itself is fine.
///
/// # What layer 3 does and does not reach
///
/// It reaches **22 of the 22 keys**: `SoundCatalogue` is the only production
/// reader of all of them, and `entries` plus `customSlot` cover every one.
/// `CreateAlarmViewModel.availableSounds` and `subtitle(for:)` are exercised on
/// top of that.
///
/// The names live under `common.*` because the words appear on two screens
/// **today** — the picker row and the alarms-list cell's sound pill
/// (`AlarmsListViewController:546` → `AlarmCell:397-401`). The rule in
/// `Localized` is about where copy is *seen*, not about which key a call site
/// happens to read, so the second screen still sourcing those words from its
/// own ten literals does not weaken it.
///
/// What no assertion here can prove is *which* of the two sources the cell
/// read, and ``testAlarmsListStillRendersTheSameWordsAsTheCatalogue`` does not
/// try: it drives the un-migrated lookup table through the real view-model and
/// asserts it agrees with the catalogue word for word. Today that pins the
/// duplication as exact; after #599 collapses the table, the same test pins the
/// collapse as changing no copy.
///
/// One thing no layer here covers: `create_alarm.sound.subtitle.custom`
/// («Скоро») reaches no screen at all. The picker substitutes
/// `create_alarm.sound_picker.custom_slot_subtitle` over it, as
/// `AlarmEditorCopyTests` records. It is pinned as copy because the model
/// still carries it, not because a user can see it.
final class SoundCatalogueCopyTests: XCTestCase {

    /// No-op scheduler so `repository.save` never reaches
    /// `UNUserNotificationCenter`.
    private final class NoopScheduler: AlarmScheduling {
        func schedule(
            _ alarm: Alarm,
            completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?
        ) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }

    // MARK: - Layers 1 + 2: the catalogue and its words

    /// Transcribed from the literals as they stood on `origin/main` before this
    /// slice, not read back from the catalogue.
    private static let copy: [String: String] = [
        "common.sound.name.dawn": "Рассвет",
        "common.sound.name.radar": "Радар",
        "common.sound.name.drops": "Капли",
        "common.sound.name.piano": "Пиано",
        "common.sound.name.guitar": "Гитара",
        "common.sound.name.bell": "Колокольчик",
        "common.sound.name.waves": "Волны",
        "common.sound.name.birds": "Птицы",
        "common.sound.name.classic": "Классика",
        "common.sound.name.jazz": "Джаз",
        "create_alarm.sound.subtitle.dawn": "Тёплый рассвет с птицами",
        "create_alarm.sound.subtitle.radar": "Нарастающий сигнал тревоги",
        "create_alarm.sound.subtitle.drops": "Мягкие капли воды",
        "create_alarm.sound.subtitle.piano": "Спокойные клавиши",
        "create_alarm.sound.subtitle.guitar": "Лёгкий струнный перебор",
        "create_alarm.sound.subtitle.bell": "Чистый звон без музыки",
        "create_alarm.sound.subtitle.waves": "Прибой и морской бриз",
        "create_alarm.sound.subtitle.birds": "Только щебет, без музыки",
        "create_alarm.sound.subtitle.classic": "Старый добрый писк",
        "create_alarm.sound.subtitle.jazz": "Бодрое утреннее настроение",
        "create_alarm.sound.name.custom": "Своя мелодия",
        "create_alarm.sound.subtitle.custom": "Скоро"
    ]

    func testEveryMigratedKeyResolvesToCopy() {
        for key in Self.copy.keys.sorted() {
            XCTAssertNotNil(Localized.optionalText(key), "missing catalogue key: \(key)")
            XCTAssertNotEqual(
                Localized.text(key), key,
                "\(key) resolves to itself — the entry is absent or holds the key as its value"
            )
        }
    }

    func testMigratedCopyStillReadsTheWayItDidBefore() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for \(key)")
        }
    }

    /// The slice adds exactly one key per column per sound. A later tidy-up
    /// that drops one and lets a call site fall through to another existing key
    /// would leave layers 1 and 2 green, because the key it landed on is fine.
    func testCatalogueCoversEverySoundIDInBothColumns() {
        for soundID in SoundCatalogue.ids {
            XCTAssertNotNil(
                Localized.optionalText(SoundCatalogue.nameKey(for: soundID)),
                "no name key for sound '\(soundID)'"
            )
            XCTAssertNotNil(
                Localized.optionalText(SoundCatalogue.subtitleKey(for: soundID)),
                "no subtitle key for sound '\(soundID)'"
            )
        }
        XCTAssertEqual(Self.copy.count, SoundCatalogue.ids.count * 2 + 2)
    }

    /// «Рассвет» is a sound *and* an alarm theme, and the two entries were one
    /// tidy-up away from being merged when this slice added the second one.
    /// They are the same word only in Russian: one names a chime, the other a
    /// background image. Asserted apart so the merge costs a red run.
    func testTheDawnSoundIsNotTheDawnTheme() {
        XCTAssertEqual(Localized.text("common.sound.name.dawn"), "Рассвет")
        XCTAssertEqual(Localized.text("create_alarm.theme.name.dawn"), "Рассвет")
        XCTAssertNotEqual(
            SoundCatalogue.nameKey(for: "dawn"), "create_alarm.theme.name.dawn",
            "the sound name must keep its own key — the two words diverge outside Russian"
        )
    }

    /// The model's «Скоро» and the picker's «Импорт своей мелодии появится
    /// позже» are both subtitles of the same row and are *not* the same string.
    /// Collapsing them would rewrite what the picker shows.
    func testTheCustomSlotKeepsItsTwoDistinctSubtitles() {
        XCTAssertNotEqual(
            Localized.text("create_alarm.sound.subtitle.custom"),
            Localized.text("create_alarm.sound_picker.custom_slot_subtitle")
        )
    }

    // MARK: - Layer 3: what SoundCatalogue hands back

    func testEntriesReadAsCopyRatherThanAsKeys() throws {
        let entries = SoundCatalogue.entries
        XCTAssertEqual(entries.map { $0.id }, SoundCatalogue.ids)
        for entry in entries {
            let name = try XCTUnwrap(Self.copy[SoundCatalogue.nameKey(for: entry.id)])
            let subtitle = try XCTUnwrap(Self.copy[SoundCatalogue.subtitleKey(for: entry.id)])
            XCTAssertEqual(entry.name, name)
            XCTAssertEqual(entry.subtitle, subtitle)
        }
        XCTAssertEqual(
            Set(entries.map { $0.name }).count, entries.count,
            "two sounds resolved to the same name — one is wired to the wrong key"
        )
    }

    func testCustomSlotReadsAsCopyRatherThanAsKeys() {
        let slot = SoundCatalogue.customSlot
        XCTAssertEqual(slot.id, "custom")
        XCTAssertEqual(slot.name, "Своя мелодия")
        XCTAssertEqual(slot.subtitle, "Скоро")
    }

    func testSubtitleLookupResolvesKnownIDsAndRejectsEverythingElse() {
        XCTAssertEqual(SoundCatalogue.subtitle(for: "dawn"), "Тёплый рассвет с птицами")
        XCTAssertEqual(SoundCatalogue.subtitle(for: "birds"), "Только щебет, без музыки")

        // The custom slot is not selectable, so no stored alarm names it and
        // the lookup treats it as uncatalogued — as it did before the move.
        XCTAssertNil(SoundCatalogue.subtitle(for: "custom"))
        XCTAssertNil(SoundCatalogue.subtitle(for: "nonexistent"))
        XCTAssertNil(SoundCatalogue.subtitle(for: ""))
    }

    /// The editor's picker is fed from `availableSounds`, so a broken key would
    /// surface there as a row reading `common.sound.name.piano`.
    func testEditorPickerDataIsCatalogueCopy() {
        let suite = "test.soundCopy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let viewModel = CreateAlarmViewModel(repository: AlarmRepository(defaults: defaults))
        XCTAssertEqual(viewModel.availableSounds.map { $0.name }, SoundCatalogue.entries.map { $0.name })
        for sound in viewModel.availableSounds {
            XCTAssertNotEqual(sound.name, SoundCatalogue.nameKey(for: sound.id))
            XCTAssertNotEqual(sound.subtitle, SoundCatalogue.subtitleKey(for: sound.id))
        }
    }

    // MARK: - The duplicate this slice unblocks

    /// `AlarmsListViewModel` still renders sound names from ten private
    /// literals of its own (#599's lane — untouched here). This asserts the two
    /// sources say the same thing for every catalogued id, which is what makes
    /// the collapse onto `Localized.text(SoundCatalogue.nameKey(for:))` a pure
    /// deletion. If the collapse ever changes a word, this goes red on the word
    /// rather than on the refactor.
    func testAlarmsListStillRendersTheSameWordsAsTheCatalogue() {
        let suite = "test.soundCopy.list.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())

        for soundID in SoundCatalogue.ids {
            repository.save(Alarm(name: "sound-\(soundID)", soundID: soundID))
        }

        let viewModel = AlarmsListViewModel(alarmRepository: repository)
        viewModel.loadData()
        XCTAssertEqual(viewModel.alarms.count, SoundCatalogue.ids.count)

        for (index, alarm) in viewModel.alarms.enumerated() {
            XCTAssertEqual(
                viewModel.alarmSoundName(at: index),
                SoundCatalogue.entries.first(where: { $0.id == alarm.soundID })?.name,
                "alarms-list name for '\(alarm.soundID)' diverged from the catalogue"
            )
        }
    }
}
