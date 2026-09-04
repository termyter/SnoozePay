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
///     would agree with any mistake in it. Keys, though, are not ids: this
///     layer says the words exist under the right key, not that the right
///     sound reaches them. ``subtitlesBySoundID`` is the second half.
///  3. **Call-site layer** — the production accessors are invoked and what
///     they return is compared against the catalogue. Layers 1 and 2 are blind
///     to a typo in the *key* at the call site, because there the catalogue
///     itself is fine.
///
/// # What layer 3 does and does not reach
///
/// It reaches **22 of the 22 keys** through this type: `entries` plus
/// `customSlot` cover every one, with `CreateAlarmViewModel.availableSounds`
/// exercised on top. It used to name `subtitle(for:)` here as well; #720
/// deleted that accessor as dead, and no key coverage moved with it because
/// `entries` already reads all ten subtitle keys. The ten name keys have a second
/// production reader — `AlarmsListViewModel.alarmSoundName(at:)` — which is
/// covered from its own side in `AlarmsListSoundNameTests`.
///
/// The names live under `common.*` because the words appear on two screens —
/// the picker row and the alarms-list cell's sound pill
/// (`AlarmsListViewController:546` → `AlarmCell:397-401`). Both now read the
/// same key: #599 deleted the ten literals the cell used to carry.
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

    /// The ten descriptive subtitles keyed by **sound id** rather than by
    /// catalogue key. That difference is the whole reason the table exists.
    ///
    /// ``copy`` above pins *key → words*, so any expectation drawn from it has
    /// to be looked up through `subtitleKey(for:)` — the very function layer 3
    /// is checking. A `subtitleKey(for:)` that handed each id another sound's
    /// key would move both sides of that comparison together and stay green
    /// while every picker row read someone else's description. The three
    /// outside checks #746 added survive that mutation too: a permutation
    /// keeps the subtitles distinct from each other and distinct from the
    /// names, and every key it lands on exists.
    ///
    /// This table is the outside view. It states which words belong to which
    /// id, and nothing in `SoundCatalogue` can move it.
    ///
    /// The name column already has one — `namesBeforeTheCollapse` in
    /// `AlarmsListSoundNameTests`, keyed by id and driven through the
    /// alarms-list reader — so a permuted `nameKey(for:)` reddens there. The
    /// subtitle column had none anywhere: #720 deleted the last id → words
    /// pinning along with `subtitle(for:)`. Transcribed from
    /// `Localizable.xcstrings`, where #598 left the pre-migration literals.
    private static let subtitlesBySoundID: [String: String] = [
        "dawn": "Тёплый рассвет с птицами",
        "radar": "Нарастающий сигнал тревоги",
        "drops": "Мягкие капли воды",
        "piano": "Спокойные клавиши",
        "guitar": "Лёгкий струнный перебор",
        "bell": "Чистый звон без музыки",
        "waves": "Прибой и морской бриз",
        "birds": "Только щебет, без музыки",
        "classic": "Старый добрый писк",
        "jazz": "Бодрое утреннее настроение"
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

    /// Two properties of ``subtitlesBySoundID`` itself, because an oracle that
    /// silently stops covering a sound stops failing for it as well.
    ///
    /// The second one is what makes the first useful: if two ids were pinned to
    /// the same words, a `subtitleKey(for:)` that swapped those two would still
    /// satisfy every assertion in this file.
    func testEverySoundIDIsPinnedToItsOwnSubtitle() {
        XCTAssertEqual(
            Set(SoundCatalogue.ids), Set(Self.subtitlesBySoundID.keys),
            "the id → subtitle table no longer covers exactly the catalogue"
        )
        XCTAssertEqual(
            Set(Self.subtitlesBySoundID.values).count, Self.subtitlesBySoundID.count,
            "two sounds are pinned to the same subtitle — a swap between them would pass"
        )
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
            // Looked up BY the key builder it checks, so it is blind to a
            // `nameKey(for:)` that points each id at another sound's key: both
            // sides move together. What reddens on that is the id-keyed
            // `namesBeforeTheCollapse` in `AlarmsListSoundNameTests`, driving
            // the other production reader of these ten keys.
            let name = try XCTUnwrap(Self.copy[SoundCatalogue.nameKey(for: entry.id)])
            XCTAssertEqual(entry.name, name)
            // The subtitle expectation is keyed by id and never touches
            // `subtitleKey(for:)`, so a permuted builder fails here rather than
            // agreeing with itself.
            XCTAssertEqual(
                entry.subtitle, Self.subtitlesBySoundID[entry.id],
                "'\(entry.id)' reads the subtitle of another sound — subtitleKey is wired to the wrong id"
            )
            XCTAssertNotEqual(
                entry.name, entry.subtitle,
                "'\(entry.id)': subtitle resolved to the name — subtitleKey is wired to the name namespace"
            )
        }
        XCTAssertEqual(
            Set(entries.map { $0.name }).count, entries.count,
            "two sounds resolved to the same name — one is wired to the wrong key"
        )
        XCTAssertEqual(
            Set(entries.map { $0.subtitle }).count, entries.count,
            "two sounds resolved to the same subtitle — one is wired to the wrong key"
        )
    }

    func testCustomSlotReadsAsCopyRatherThanAsKeys() {
        let slot = SoundCatalogue.customSlot
        XCTAssertEqual(slot.id, "custom")
        XCTAssertEqual(slot.name, "Своя мелодия")
        XCTAssertEqual(slot.subtitle, "Скоро")
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
            XCTAssertEqual(
                sound.subtitle, Self.subtitlesBySoundID[sound.id],
                "the picker would render another sound's description under '\(sound.id)'"
            )
        }
    }

    // MARK: - The duplicate this slice unblocks

    /// Written while `AlarmsListViewModel` still rendered sound names from ten
    /// private literals of its own, to prove the two sources agreed for every
    /// catalogued id and so make the collapse a pure deletion. #599 has since
    /// performed it, so this now asserts the surviving reader agrees with the
    /// picker's — i.e. that no future change splits the two screens apart
    /// again. The word-for-word check moved to `AlarmsListSoundNameTests`,
    /// which holds the Russian as literals rather than reading it back out of
    /// the catalogue both sides now share.
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
