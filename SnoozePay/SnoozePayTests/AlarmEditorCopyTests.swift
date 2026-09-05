import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that #612 moved out of the alarms list and the alarm editor
/// (`ViewControllers/Alarms`, slice 2 of 3) into `Localizable.xcstrings`.
///
/// A wrong key is silent: `Localized.text` hands the key back, `SoundCell`
/// renders `create_alarm.sound.title` where «Звук» used to be, and the
/// build ships. So, mirroring `DesignSystemCopyTests`, the assertions come in
/// three layers and a red run names which one broke:
///
///  1. **Catalogue layer** — every key exists.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration, transcribed here from the pre-migration literals rather
///     than read back out of the file under test.
///  3. **Call-site layer** — the real cells and controllers are built and what
///     they render is compared against the catalogue. Layers 1 and 2 are blind
///     to a typo in the *key* at the call site, because the catalogue is fine
///     in that case.
///
/// Underneath all three sits the question of *how much* they cover, and the
/// table of words is not what answers it: the list of keys the loops walk is
/// read off the editor's own sources by `CatalogueKeyScanner`. It used to be
/// `copy.keys.sorted()`, which made the table its own scope — lifting a pair out
/// of it also lifted that key out of every loop and out of the leak guard, and
/// nothing said so (#767).
///
/// Three things this slice deliberately did **not** migrate, asserted here so
/// a later pass doesn't "finish the job" and break them:
///
///  * the default alarm name «Будильник» (`Alarm.name`), which is compared
///    against records already on disk;
///  * the weekday chips, which are calendar data from `WeekdayNames`;
///  * the sound names, which `SoundCatalogue` already owns.
@MainActor
final class AlarmEditorCopyTests: XCTestCase {

    // MARK: - Layer 1 + 2: the catalogue and its words

    /// The strings as they read on screen today, copied from the literals this
    /// slice replaced. A list derived from the catalogue would agree with any
    /// mistake in it.
    private static let copy: [String: String] = [
        "alarms.backend_guard.create_anyway": "Всё равно создать",
        "alarms.backend_guard.enable_anyway": "Всё равно включить",
        "alarms.balance_corrupted.later": "Позже",
        "alarms.balance_corrupted.message": "В хранилище обнаружено некорректное значение баланса (%@). "
            + "Пополнения и списания приостановлены. Сбросить баланс до 0 ₽?",
        "alarms.balance_corrupted.reset": "Сбросить",
        "alarms.balance_corrupted.title": "Баланс повреждён",
        "alarms.button.delete": "Удалить",
        "alarms.cell.accessibility": "Будильник %@",
        "alarms.cell.toggle_accessibility": "Будильник",
        "alarms.debug.reset_onboarding.message": "Закройте приложение и запустите заново — "
            + "увидите экран приветствия.",
        "alarms.debug.reset_onboarding.title": "Онбординг сброшен",
        "alarms.delete.title": "Удалить будильник?",
        "alarms.error.data_title": "Ошибка данных",
        "alarms.error.load_failed_fallback": "Не удалось загрузить будильники.",
        "alarms.streak.caps": "%1$lld %2$@ БЕЗ ОТКЛАДЫВАНИЙ",
        "alarms.streak.saved": "Сэкономили %@",
        "common.button.cancel": "Отмена",
        "common.button.done": "Готово",
        "create_alarm.accessibility.not_selected": "не выбрано",
        "create_alarm.accessibility.selected": "выбрано",
        "create_alarm.button.delete_alarm": "Удалить будильник",
        "create_alarm.button.save": "Сохранить",
        "create_alarm.close.accessibility": "Закрыть",
        "create_alarm.error.persist_failed": "Не удалось сохранить",
        "create_alarm.error.retry": "Попробуйте ещё раз.",
        "create_alarm.error.schedule_failed": "Не удалось запланировать будильник",
        "create_alarm.name.placeholder": "Название · напр. Будни",
        "create_alarm.penalty.accessibility": "Цена откладывания, рублей",
        "create_alarm.penalty.caps": "Цена откладывания",
        "create_alarm.penalty.hint": "Сколько спишется при «отложить»",
        "create_alarm.penalty.minimum": "Минимум 1 ₽",
        "create_alarm.progressive.subtitle": "Каждое откладывание — в 2 раза дороже.",
        "create_alarm.progressive.title": "Прогрессивный режим",
        "create_alarm.repeat.caps": "ПОВТОР",
        "create_alarm.repeat.never": "Никогда",
        "create_alarm.repeat.weekly": "Еженедельно",
        "create_alarm.snooze.caps": "Длительность откладывания",
        "create_alarm.snooze.hint": "На сколько минут отодвигается звонок",
        "create_alarm.snooze.minutes": "%lld мин",
        "create_alarm.sound.fallback": "По умолчанию",
        "create_alarm.sound.title": "Звук",
        "create_alarm.sound_picker.accessibility": "Выбор звука",
        "create_alarm.sound_picker.custom_slot": "%@ · скоро",
        "create_alarm.sound_picker.custom_slot_subtitle": "Импорт своей мелодии появится позже",
        "create_alarm.sound_picker.preview_accessibility": "Прослушать превью",
        "create_alarm.sound_picker.preview_caps": "Превью",
        "create_alarm.sound_picker.volume_row": "Громкость и нарастание",
        "create_alarm.theme.title": "Тема",
        "create_alarm.theme_picker.error.message": "Попробуйте выбрать другое изображение.",
        "create_alarm.theme_picker.error.title": "Не удалось сохранить фото",
        "create_alarm.theme_picker.preview_caps": "ПРЕВЬЮ ЭКРАНА ЗВОНКА",
        "create_alarm.theme_picker.section_presets": "Готовые темы",
        "create_alarm.theme_picker.title": "Тема будильника",
        "create_alarm.title.edit": "Будильник",
        "create_alarm.title.new": "Новый будильник",
        "create_alarm.vibration.title": "Вибрация",
        "create_alarm.volume.title": "Громкость",
        "create_alarm.volume.value_fade": "%lld%% · плавно",
        "create_alarm.volume_picker.fade_subtitle": "За 30 секунд",
        "create_alarm.volume_picker.fade_title": "Постепенно нарастает"
    ]

    // MARK: - Layer 0: how much of the screen the layers above cover

    /// The sources this suite stands over: the alarm editor, the cells and
    /// pickers it is built from, and the list it returns to.
    ///
    /// Naming the files is what makes the suite's *scope* independent of the
    /// table above. `allKeys` used to read `copy.keys.sorted()`, so lifting a
    /// pair out of the table lifted that key out of everything standing over it
    /// — `testEveryMigratedKeyResolvesToCopy`,
    /// `testMigratedCopyStillReadsTheWayItDidBefore` and `assertNoKeysLeaked`
    /// all kept passing over a smaller world and said nothing (#767). The
    /// scenario is not hypothetical: #720 deleted `subtitle(for:)` as dead code
    /// and took a live id → words binding with it; #746 and #755 put it back.
    ///
    /// Shortening *this* list shrinks coverage just as effectively, and that is
    /// accepted: it is a visible edit to a list whose only job is to say what is
    /// covered, not a side effect of tidying a dictionary of words. (Shortening
    /// it is loud for 16 of the 20 — the table then pins keys nothing reads and
    /// `stale` fires. The other four hold only keys some other listed source
    /// reads too, or `create_alarm.wake_up`, which lives in ``pinnedElsewhere``;
    /// dropping one of those four is silent. Deletion is the visible half.)
    ///
    /// NEVER ADDING a file is the failure mode this list cannot see by itself: a
    /// source it has not heard of contributes no keys, so its copy can never
    /// come back `unpinned`, and being absent from the table it can never come
    /// back `stale` either. ``coveredByAnotherSuite`` plus
    /// ``testEverySourceUnderTheEditorIsAccountedFor`` is what makes a new file
    /// red instead of silent.
    private static let screenSources = [
        "AlarmCell.swift",
        "AlarmThemePickerViewController.swift",
        "AlarmsListViewController.swift",
        "ConfirmDeleteAlarmViewController.swift",
        "CreateAlarmViewController.swift",
        "CreateAlarmViewController+Pickers.swift",
        "CreateAlarmViewController+Sections.swift",
        "SoundPickerViewController.swift",
        "VolumePickerViewController.swift",
        "Cells/AlarmsStreakBannerView.swift",
        "Cells/DayPickerCell.swift",
        "Cells/NameCell.swift",
        "Cells/PenaltyCell.swift",
        "Cells/ProgressiveScaleCell.swift",
        "Cells/RepeatModeCell.swift",
        "Cells/SnoozeSliderCell.swift",
        "Cells/SoundCell.swift",
        "Cells/ThemeRowCell.swift",
        "Cells/TimePickerCell.swift",
        "Cells/VibrationCell.swift"
    ]

    /// The rest of the editor's directory, each name carrying the suite that
    /// owns it — or, for a file with no catalogue keys yet, listed so that
    /// growing one goes red here first.
    ///
    /// ``screenSources`` cannot police itself; this is the other half of the
    /// partition, and `testEverySourceUnderTheEditorIsAccountedFor` asserts the
    /// two cover the directory exactly. Adding a cell is an ordinary thing to
    /// do, and nobody editing `Cells/SoundPickerRowCell.swift` will think to
    /// open a copy suite — so the suite has to notice on its own.
    private static let coveredByAnotherSuite: Set<String> = [
        // FiringCopyTests
        "AlarmFiringViewController.swift",
        "AlarmFiringViewController+Audio.swift",
        "AlarmFiringViewController+Layout.swift",
        "AlarmFiringViewController+NoBalance.swift",
        "AlarmFiringViewController+NoBalanceColumn.swift",
        "AlarmFiringViewController+Progressive.swift",
        "AlarmFiringViewController+Snoozed.swift",
        "AlarmFiringViewController+SnoozedViews.swift",
        "AlarmFiringViewController+Theme.swift",
        "AlarmFiringViewController+ViewLifecycle.swift",
        "WokeMorningContent.swift",
        "WokeMorningViewController.swift",
        // FiringTopUpCopyTests
        "FiringTopUpBottomSheetViewController.swift",
        "FiringTopUpCopy.swift",
        "FiringTopUpPresetRow.swift",
        // No catalogue keys today; listed so growing one goes red here first.
        "Cells/AlarmThemeTileCell.swift",
        "Cells/SoundPickerRowCell.swift"
    ]

    /// Keys those sources read whose words another suite already pins. Every
    /// entry names that suite: an unexplained exception here is how the table
    /// would start shrinking again, one line at a time.
    private static let pinnedElsewhere: Set<String> = [
        // `AlertButtonLocalizationTests` owns this one end to end — it pins the
        // spelling («Ок», not «ОК» or «OK») and scans every source for alert
        // buttons that bypass the key.
        "common.button.ok",
        // `LocalizableCatalogTests.testTimePickerHeaderResolves` pins «Подъём».
        "create_alarm.wake_up"
    ]

    /// What those sources hand to `Localized`, read off this checkout instead of
    /// off the table. External by construction: a table cannot vouch for its own
    /// completeness.
    private static let reading = CatalogueKeyScanner.read(
        screenSources, under: alarmSourceDirectory()
    )

    /// Everything the loops below stand over: the keys the screens read plus the
    /// keys the table claims.
    ///
    /// The union, not the reading alone. Were the reading to come back empty —
    /// sources moved, the list renamed — swapping one source of truth for the
    /// other would quietly disarm the leak guard, which is the exact failure
    /// mode this change closes.
    /// `testCopyTableHoldsExactlyTheKeysTheScreensRead` is what goes red then,
    /// loudly and in one place.
    private static var allKeys: [String] { Set(copy.keys).union(reading.keys).sorted() }

    /// The check the table cannot perform on itself, in both directions:
    ///
    ///  * a key the screens read that the table does not pin — which covers both
    ///    the case that used to be silent, a pair *removed* from the table, and
    ///    a genuinely new key appearing on a screen;
    ///  * a key the table pins that no listed source reads any more, i.e. an
    ///    expectation standing over nothing.
    func testCopyTableHoldsExactlyTheKeysTheScreensRead() {
        XCTAssertEqual(
            Self.reading.unreadable, [],
            "listed sources could not be read — renamed or moved, and whatever "
                + "copy they hold is now outside every assertion here"
        )
        XCTAssertFalse(
            Self.reading.keys.isEmpty,
            "the scan read no keys at all: the comparison below would be vacuous"
        )

        let gaps = Self.coverageGaps(copyKeys: Set(Self.copy.keys), keysOnScreen: Self.reading.keys)
        XCTAssertEqual(
            gaps.unpinned, [],
            "the editor reads keys this table does not pin — add them with the "
                + "words they render, or name the suite that pins them in "
                + "`pinnedElsewhere`: \(gaps.unpinned)"
        )
        XCTAssertEqual(
            gaps.stale, [],
            "this table pins keys no listed source reads any more — the "
                + "expectation stands over nothing: \(gaps.stale)"
        )
        // An exemption that outlived its call site subtracts nothing and would
        // never be reported: `coverageGaps` only ever removes `pinnedElsewhere`
        // from the reading. Without this line the set could keep growing on one
        // side and rotting on the other.
        XCTAssertEqual(
            Self.pinnedElsewhere.subtracting(Self.reading.keys), [],
            "`pinnedElsewhere` names keys no listed source reads any more — "
                + "delete them, or the exemption list becomes its own blind spot"
        )
    }

    /// The two lists have to cover the editor's directory exactly.
    ///
    /// This is the assertion ``screenSources`` cannot make about itself. A new
    /// file under `ViewControllers/Alarms` is in neither set, contributes no
    /// keys to the scan and holds none in the table, so both `unpinned` and
    /// `stale` stay empty and the suite says nothing — the silence #767 was
    /// filed about, moved one level out.
    func testEverySourceUnderTheEditorIsAccountedFor() {
        let root = Self.alarmSourceDirectory()
        let onDisk = Set(
            (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
                .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") } ?? [])
        )

        XCTAssertFalse(
            onDisk.isEmpty,
            "enumerated nothing under \(root.path) — this check would be vacuous"
        )
        XCTAssertEqual(
            onDisk.subtracting(Self.screenSources).subtracting(Self.coveredByAnotherSuite), [],
            "a source under the editor is in neither list — add it to "
                + "`screenSources`, or name the suite that pins its copy in "
                + "`coveredByAnotherSuite`"
        )
    }

    /// Both halves of the acceptance, asserted on the comparison instead of on
    /// the checkout: mutating the real table or a real source to demonstrate the
    /// redness demonstrates it once, in a PR nobody re-runs.
    func testCoverageComparisonReportsAShrunkTableAndANewKeyOnScreenAlike() {
        let onScreen: Set<String> = ["create_alarm.sound.title", "create_alarm.theme.title"]

        // (a) a pair lifted out of the table.
        let shrunk = Self.coverageGaps(copyKeys: ["create_alarm.sound.title"], keysOnScreen: onScreen)
        XCTAssertEqual(shrunk.unpinned, ["create_alarm.theme.title"])
        XCTAssertEqual(shrunk.stale, [])

        // (b) a key a screen started reading that nobody transcribed.
        let added = Self.coverageGaps(
            copyKeys: onScreen, keysOnScreen: onScreen.union(["create_alarm.brand_new"])
        )
        XCTAssertEqual(added.unpinned, ["create_alarm.brand_new"])

        // An expectation whose call site is gone: the other direction, and the
        // reason the comparison is an equality rather than a containment.
        let orphan = Self.coverageGaps(copyKeys: ["create_alarm.retired"], keysOnScreen: onScreen)
        XCTAssertEqual(orphan.stale, ["create_alarm.retired"])

        // The excused keys are subtracted, not ignored: a key another suite pins
        // is neither unpinned nor stale here.
        let excused = Self.coverageGaps(copyKeys: [], keysOnScreen: Self.pinnedElsewhere)
        XCTAssertEqual(excused.unpinned, [])
        XCTAssertEqual(excused.stale, [])
    }

    func testEveryMigratedKeyResolvesToCopy() {
        for key in Self.allKeys {
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

    // MARK: - Layer 3: the alarm-editor rows

    func testSettingsRowsRenderCopyRatherThanKeys() {
        let sound = SoundCell(style: .default, reuseIdentifier: nil)
        let theme = ThemeRowCell(style: .default, reuseIdentifier: nil)
        let vibration = VibrationCell(style: .default, reuseIdentifier: nil)

        let rendered = [sound, theme, vibration].flatMap { Self.strings(in: $0.contentView) }
        Self.assertNoKeysLeaked(in: rendered)
        // «Громкость» is not a row of this card: #263 moved it under the sound
        // screen, so `create_alarm.volume.title` is pinned by
        // `testVolumeScreenRendersItsTitleAndFadeRow` instead.
        for key in [
            "create_alarm.sound.title", "create_alarm.theme.title",
            "create_alarm.vibration.title"
        ] {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "no settings row renders «\(Localized.text(key))»"
            )
        }
    }

    func testPenaltyCardRendersItsCaptionHintAndHelper() {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        let rendered = Self.strings(in: cell.contentView)
        Self.assertNoKeysLeaked(in: rendered)

        // Recipe form. Safe only because `create_alarm.penalty.caps` is stored
        // sentence-case and `PenaltyCell` upper-cases it: drop that call and the
        // sides disagree, red. Both preview captions are literals instead, for
        // two different reasons — `theme_picker.preview_caps` is stored already
        // capped, so this form reads one string on both sides and cannot catch a
        // caps change; `sound_picker.preview_caps` is stored sentence-case like
        // this key, so the form is NOT blind there, and its literal buys
        // independence from the WORD. Reasoned from the stored values, not
        // measured. See `testThemePickerRendersItsTitleAndPreviewCaption` and
        // `testSoundPickerFramesTheCatalogueSlotWithoutRenamingIt` (#665; #793).
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.penalty.caps").uppercased()))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.penalty.hint")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.penalty.minimum")))
        XCTAssertTrue(
            rendered.contains(Localized.text("create_alarm.penalty.accessibility")),
            "the amount field lost its VoiceOver label: \(rendered)"
        )
    }

    func testProgressiveCardRendersItsTitleAndRationale() {
        let cell = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        let rendered = Self.strings(in: cell.contentView)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.progressive.title")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.progressive.subtitle")))
    }

    func testNamePlaceholderComesFromTheCatalogue() {
        let cell = NameCell(style: .default, reuseIdentifier: nil)
        let field = Self.textFields(in: cell.contentView).first
        XCTAssertEqual(
            field?.attributedPlaceholder?.string,
            Localized.text("create_alarm.name.placeholder")
        )
    }

    func testRepeatSegmentsRenderBothModesAndTheirSelectionState() {
        let cell = RepeatModeCell(style: .default, reuseIdentifier: nil)
        cell.configure(mode: .weekly, hint: "")

        let rendered = Self.strings(in: cell.contentView)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.repeat.caps")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.repeat.never")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.repeat.weekly")))

        let values = Self.controls(in: cell.contentView).compactMap { $0.accessibilityValue }
        XCTAssertTrue(values.contains(Localized.text("create_alarm.accessibility.selected")))
        XCTAssertTrue(values.contains(Localized.text("create_alarm.accessibility.not_selected")))
    }

    /// The chips are the one place in this slice where the right answer was
    /// *not* a catalogue key: weekday names ship with the locale, so the cell
    /// reads `WeekdayNames`. Nothing on screen may move because of that.
    func testWeekdayChipsComeFromTheCalendarAndStillReadTheSame() {
        let cell = DayPickerCell(style: .default, reuseIdentifier: nil)
        let titles = Self.controls(in: cell.contentView)
            .compactMap { ($0 as? UIButton)?.title(for: .normal) }

        XCTAssertEqual(titles, ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
        XCTAssertEqual(titles, WeekdayNames.short, "the chips stopped following the locale")

        cell.configure(selectedDays: [0])
        let values = Self.controls(in: cell.contentView).compactMap { $0.accessibilityValue }
        XCTAssertEqual(values.first, Localized.text("create_alarm.accessibility.selected"))
        XCTAssertTrue(values.dropFirst().allSatisfy {
            $0 == Localized.text("create_alarm.accessibility.not_selected")
        })
    }

    // MARK: - Layer 3: the two substitutions that can silently lose a number

    /// «%lld%% · плавно» carries an escaped percent sign. Get the escape wrong
    /// and `String(format:)` eats the number instead of printing it, which no
    /// catalogue-level assertion can see. The reading is built by
    /// `SoundPickerViewController.refreshVolumeLabel()` — the volume row moved
    /// under the sound screen in #263 — and both of its branches are pinned
    /// here, because only the faded one is exercised by
    /// `testSoundPickerFramesTheCatalogueSlotWithoutRenamingIt`.
    func testVolumeRowKeepsBothItsNumberAndItsPercentSign() {
        let faded = Self.volumeRowReadings(fadeIn: true)
        XCTAssertTrue(faded.contains("80% · плавно"), "faded volume row reads \(faded)")

        let plain = Self.volumeRowReadings(fadeIn: false)
        XCTAssertTrue(plain.contains("80%"), "plain volume row reads \(plain)")
    }

    /// 0.8 was the only volume the suite ever exercised, and it cannot tell the
    /// rounding in `refreshVolumeLabel()` apart from any of its corruptions: as
    /// a `Float`, `0.8 * 100` is exactly 80 whether the result is rounded,
    /// truncated, floored or ceiled.
    ///
    /// Three seeds are needed to part all five realistic forms, and none of the
    /// three is redundant — the obvious tidy-up here is to collapse them into
    /// one value, which silently reopens the hole. In binary32:
    ///
    /// | seed  | `Float(v) * 100` | `.rounded()` | `.up` | `.down` / `Int(_:)` | `.toNearestOrEven` |
    /// |-------|------------------|--------------|-------|---------------------|--------------------|
    /// | 0.755 | 75.5 exactly     | 76           | 76    | 75                  | 76                 |
    /// | 0.125 | 12.5 exactly     | 13           | 13    | 12                  | 12                 |
    /// | 0.752 | 75.19999694…     | 75           | 76    | 75                  | 75                 |
    ///
    /// So: either tie kills truncation and `.rounded(.down)`; only the 12.5 tie
    /// parts `.rounded()` from `.rounded(.toNearestOrEven)`; and only 0.752 —
    /// whose product is deliberately *not* a tie — kills `.rounded(.up)`, because
    /// on an exact `.5` the ceiling agrees with the shipped rounding and both
    /// ties let that mutation through (#704).
    ///
    /// Such a value never comes off the slider — that quantises to 5% steps —
    /// but it can come off disk: `Alarm.volume` is a stored `Float`.
    func testVolumeRowRoundsAFractionalPercentInsteadOfTruncatingIt() {
        for (volume, expected) in [
            (Float(0.755), "76%"), (Float(0.125), "13%"), (Float(0.752), "75%")
        ] {
            let readings = Self.volumeRowReadings(fadeIn: false, volume: volume)
            XCTAssertTrue(
                readings.contains(expected),
                "volume \(volume) should read «\(expected)», row reads \(readings)"
            )
        }
    }

    /// `refreshVolumeLabel()` formats `volume` without a clamp of its own, and
    /// that is deliberate rather than an oversight left by the removal of
    /// `VolumeCell` (#686): every writer of the property is already bounded —
    /// the initialiser below and the persisted side both go through
    /// `Alarm.clampedVolume` (one implementation since #714), and
    /// `VolumePickerViewController.sliderChanged()` quantises inside `0...1`
    /// before calling back. A clamp at render time would be unreachable, i.e.
    /// exactly the kind of code #686 deleted. What is worth pinning is the last
    /// live boundary in front of the label: the seed. A corrupt persisted value
    /// has to arrive as a percentage inside 0…100, and a non-finite one must not
    /// reach `Int(_:)` at all — that conversion traps on NaN (#704).
    func testSoundPickerClampsACorruptVolumeSeedInsteadOfRenderingIt() {
        let tooLoud = Self.volumeRowReadings(fadeIn: false, volume: 1.4)
        XCTAssertTrue(tooLoud.contains("100%"), "an over-range seed leaked out: \(tooLoud)")

        let negative = Self.volumeRowReadings(fadeIn: false, volume: -0.2)
        XCTAssertTrue(negative.contains("0%"), "a negative seed leaked out: \(negative)")

        let garbage = Self.volumeRowReadings(fadeIn: false, volume: .nan)
        XCTAssertTrue(garbage.contains("100%"), "a NaN seed did not fall back to full: \(garbage)")
    }

    /// Everything the sound screen renders at the given volume. `volume` and
    /// `fadeIn` are private and only settable through the initialiser, so each
    /// state needs its own instance.
    private static func volumeRowReadings(fadeIn: Bool, volume: Float = 0.8) -> [String] {
        let picker = SoundPickerViewController(
            sounds: SoundCatalogue.entries,
            selectedID: SoundCatalogue.entries[0].id,
            onSelect: { _ in },
            previewSound: { _ in },
            volume: volume,
            fadeIn: fadeIn,
            // The volume block only mounts for a host that wired the handler.
            onVolumeChange: { _, _ in }
        )
        picker.loadViewIfNeeded()
        return strings(in: picker.view)
    }

    /// The slider reading is one catalogue string whose number is then styled
    /// apart, rather than two concatenated fragments — so the number has to
    /// still be found inside the phrase, and still be the only part in the
    /// mono face.
    func testSnoozeSliderReadingKeepsItsNumberInTheHeadlineFace() throws {
        let cell = SnoozeSliderCell(style: .default, reuseIdentifier: nil)
        cell.configure(minutes: 7)

        let reading = try XCTUnwrap(
            Self.attributedStrings(in: cell.contentView).first { $0.string == "7 мин" },
            "the slider never rendered «7 мин»: \(Self.strings(in: cell.contentView))"
        )
        XCTAssertEqual(
            reading.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
            AppTypography.moneyMd,
            "the digit lost the mono headline face"
        )
        XCTAssertEqual(
            reading.attribute(.font, at: reading.length - 1, effectiveRange: nil) as? UIFont,
            AppTypography.h4,
            "the unit lost its dimmed face"
        )

        // Range bounds under the track read through the same key.
        XCTAssertTrue(Self.strings(in: cell.contentView).contains("1 мин"))
        XCTAssertTrue(Self.strings(in: cell.contentView).contains("15 мин"))

        // The cell's caps label renders `create_alarm.snooze.caps`, which is in
        // `allKeys` — but this was the one caps call site never handed to the
        // guard, so a leak here stayed outside it however many spellings the
        // guard learned.
        Self.assertNoKeysLeaked(in: Self.strings(in: cell.contentView))
    }

    // MARK: - Layer 3: the alarms list

    /// The composed VoiceOver summary starts with a substituted key now; a
    /// swapped or missing argument would drop the time from the announcement.
    func testAlarmCardSummaryStillOpensWithTheAlarmAndItsTime() {
        XCTAssertEqual(
            AlarmCell.accessibilityLabel(
                time: "07:00",
                daysCaps: "БУДНИ · ПН–ПТ",
                priceText: "50 ₽",
                multiplier: "×2",
                soundName: "Soft Dawn"
            ),
            "Будильник 07:00, Будни · пн–пт, 50 ₽, ×2, Soft Dawn"
        )
    }

    /// The card's toggle: its *label* comes from the catalogue, its *value*
    /// comes from the platform — and this test claims only the first.
    ///
    /// #645. The assertion here used to read
    /// `XCTAssertEqual(toggle?.accessibilityValue, Localized.text("alarms.cell.toggle_on"))`
    /// and was green in the full suite but red under `-only-testing:`, reporting
    /// `("1") is not equal to ("включён")`. That is not test order: `"1"` can
    /// only be produced by UIKit's accessibility layer, whose
    /// `-[UISwitchAccessibility accessibilityValue]` (disassembled from
    /// `System/Library/AccessibilityBundles/UIKit.axbundle`) is exactly
    ///
    ///     return [self safeBoolForKey:@"isOn"] ? @"1" : @"0";
    ///
    /// — no branch reads back a value the app assigned. (Read off the iOS 26.5
    /// simulator runtime, 23F77; private implementation, so re-read it before
    /// leaning on the exact body.)
    ///
    /// What is established is the disassembly and the two observed runs. Which
    /// run had the accessibility layer installed is the explanation that fits
    /// them, not something this suite measured — but it does not need to be: in
    /// production the layer IS installed whenever VoiceOver runs, so the red
    /// result is the one that describes a user. The old expectation was
    /// unreachable there, and `AlarmCell` no longer assigns it.
    ///
    /// The replacement oracle is a **baseline** rather than a constant: a bare
    /// `UISwitch` in the same state, created next to the cell and read in the
    /// same breath, so both sides see the same process.
    ///
    /// `UISwitch` and not `SPSwitch` on purpose. The value under test is
    /// UIKit's derived one, and the card's control is an `SPSwitch`; baselining
    /// against another `SPSwitch` would move both sides together the day
    /// `SPSwitch` grows an `accessibilityValue` override of its own, and the
    /// test would stay green while VoiceOver started saying something else.
    /// The platform is the oracle, so the baseline has to be the platform.
    /// Both `nil` (layer not installed) or both `"1"`/`"0"` (installed) —
    /// either way the card is
    /// compared against the platform, and re-introducing a hand-set value turns
    /// this red in exactly the run that used to be green.
    ///
    /// `accessibilityLabel` is asserted as before: the same UIKit class resolves
    /// it through `accessibilityUserDefinedLabel`, so it *is* ours to set.
    func testAlarmCardToggleAnnouncesItsStateTheWayThePlatformDoes() throws {
        for enabled in [true, false] {
            let cell = AlarmCell(style: .default, reuseIdentifier: nil)
            cell.configure(time: "07:00", daysCaps: "ВЫХОДНЫЕ", priceText: "50 ₽",
                           multiplier: nil, soundName: nil, enabled: enabled)
            let baseline = UISwitch()
            baseline.isOn = enabled

            let toggle = try XCTUnwrap(
                Self.controls(in: cell.contentView).compactMap { $0 as? UISwitch }.first {
                    $0.accessibilityLabel == Localized.text("alarms.cell.toggle_accessibility")
                },
                "the card's switch lost its VoiceOver label (enabled: \(enabled))"
            )
            XCTAssertEqual(toggle.isOn, enabled, "the card's switch stopped tracking `enabled`")
            XCTAssertEqual(
                toggle.accessibilityValue, baseline.accessibilityValue,
                """
                the card announces its state differently from a bare UISwitch in the same \
                state (enabled: \(enabled)) — card: \
                \(toggle.accessibilityValue.map { "\"\($0)\"" } ?? "nil"), \
                platform: \(baseline.accessibilityValue.map { "\"\($0)\"" } ?? "nil"). \
                Something assigned accessibilityValue again, and VoiceOver will ignore it
                """
            )
        }
    }

    /// Two arguments in a row, one of them a declined noun: a swapped pair
    /// reads «ДНЯ 3 БЕЗ ОТКЛАДЫВАНИЙ» and still compiles.
    func testStreakBannerKeepsTheCountBeforeItsNoun() throws {
        let banner = AlarmsStreakBannerView(frame: CGRect(x: 0, y: 0, width: 360, height: 96))
        banner.configure(streakDays: 3, savedAmount: 250)
        banner.layoutIfNeeded()

        let rendered = Self.strings(in: banner)
        Self.assertNoKeysLeaked(in: rendered)

        let caps = try XCTUnwrap(
            rendered.first { $0.contains("БЕЗ ОТКЛАДЫВАНИЙ") },
            "the streak banner never rendered its caps line: \(rendered)"
        )
        XCTAssertEqual(caps, "3 ДНЯ БЕЗ ОТКЛАДЫВАНИЙ")
        XCTAssertTrue(
            rendered.contains { $0.hasPrefix("Сэкономили ") },
            "the streak banner lost its savings line: \(rendered)"
        )
    }

    // MARK: - Layer 3: the sheets and screens

    func testConfirmDeleteSheetRendersHeadlineAndBothButtons() {
        let sheet = ConfirmDeleteAlarmViewController(body: "…")
        sheet.loadViewIfNeeded()

        let rendered = Self.strings(in: sheet.view)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("alarms.delete.title")))
        XCTAssertTrue(rendered.contains(Localized.text("alarms.button.delete")))
        XCTAssertTrue(rendered.contains(Localized.text("common.button.cancel")))
    }

    /// Both modes of the editor, because the title and the primary action are
    /// chosen by the same `isEditing` branch — a key pasted into the wrong arm
    /// only shows up in one of them.
    func testAlarmEditorTitlesAndActionsFollowItsMode() {
        let creating = CreateAlarmViewController(alarm: nil)
        creating.loadViewIfNeeded()
        XCTAssertEqual(creating.title, Localized.text("create_alarm.title.new"))
        var rendered = Self.strings(in: creating.view) + Self.titleViewStrings(of: creating)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.title.new").uppercased()))
        XCTAssertTrue(rendered.contains(Localized.text("common.button.done")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.close.accessibility")))

        let editing = CreateAlarmViewController(alarm: Alarm())
        editing.loadViewIfNeeded()
        XCTAssertEqual(editing.title, Localized.text("create_alarm.title.edit"))
        rendered = Self.strings(in: editing.view) + Self.titleViewStrings(of: editing)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.title.edit").uppercased()))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.button.save")))
        XCTAssertTrue(rendered.contains(Localized.text("common.button.cancel")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.button.delete_alarm")))
    }

    func testVolumeScreenRendersItsTitleAndFadeRow() {
        let picker = VolumePickerViewController(volume: 0.5, fadeIn: true)
        picker.loadViewIfNeeded()

        let rendered = Self.strings(in: picker.view) + Self.titleViewStrings(of: picker)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.volume.title").uppercased()))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.volume_picker.fade_title")))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.volume_picker.fade_subtitle")))
    }

    /// The sound picker is where the «don't invent a second set of sound
    /// names» rule lives: the catalogue supplies the frame («%@ · скоро»),
    /// `SoundCatalogue` supplies the name inside it.
    func testSoundPickerFramesTheCatalogueSlotWithoutRenamingIt() {
        let picker = SoundPickerViewController(
            sounds: SoundCatalogue.entries,
            selectedID: SoundCatalogue.entries[0].id,
            onSelect: { _ in },
            previewSound: { _ in },
            volume: 0.8,
            fadeIn: true,
            // The volume block only mounts for a host that wired the handler.
            onVolumeChange: { _, _ in }
        )
        picker.loadViewIfNeeded()

        let rendered = Self.strings(in: picker.view) + Self.titleViewStrings(of: picker)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.sound.title").uppercased()))
        // Pinned as a literal, on purpose — but not because the old form was
        // blind to lost caps: this key holds «Превью», `SoundPickerViewController`
        // upper-cases it at line 86, and removing that call would have failed
        // `Localized.text(key).uppercased()` too. What the literal buys is
        // independence from the *word*: re-type the entry as «Прослушать» and the
        // old form still agrees with the screen, so only the word table above
        // (layer 2) goes red, naming the catalogue row and not this screen. The
        // theme caption below is the other case, where the recipe form really was
        // blind (#665; unification in #793).
        XCTAssertTrue(
            rendered.contains("ПРЕВЬЮ"),
            "the sound preview card lost its caps caption: \(rendered)"
        )
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.sound_picker.volume_row")))
        // The key's other live call site. `VolumePickerViewController:118` is
        // pinned by `testVolumeScreenRendersItsTitleAndFadeRow`; this caps
        // caption above the volume card (`SoundPickerViewController:588`) was
        // read by nothing, so swapping its key there stayed green (#704).
        XCTAssertTrue(
            rendered.contains(Localized.text("create_alarm.volume.title").uppercased()),
            "the volume block lost its caps caption: \(rendered)"
        )
        XCTAssertTrue(
            rendered.contains("80% · плавно"),
            "the volume row lost its reading: \(rendered)"
        )
        XCTAssertEqual(
            Localized.format("create_alarm.sound_picker.custom_slot", SoundCatalogue.customSlot.name),
            "Своя мелодия · скоро"
        )
    }

    func testThemePickerRendersItsTitleAndPreviewCaption() {
        // Not the section header, whatever the old name promised: it is a
        // supplementary view only a full collection-view pass would render (hence
        // no `layoutIfNeeded`), so `theme_picker.section_presets` is pinned by
        // the word table above and by nothing on screen.
        let picker = AlarmThemePickerViewController(currentTheme: .dawn, onSelect: { _ in })
        picker.loadViewIfNeeded()

        let rendered = Self.strings(in: picker.view) + Self.titleViewStrings(of: picker)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.theme_picker.title").uppercased()))
        // The literal, for the reason in
        // `testSoundPickerFramesTheCatalogueSlotWithoutRenamingIt` — and this is
        // the assertion that *was* blind: the key is stored already capped and
        // `AlarmThemePickerViewController:84` upper-cases nothing, so the old
        // right-hand side re-read the entry the label did and matched a screen
        // that had dropped its caps. The *suite* was not blind: the word table
        // above pins the exact value (the mutation had to change it too) and
        // catches a re-typed caption — keep that row (#665; unification #793).
        XCTAssertTrue(
            rendered.contains("ПРЕВЬЮ ЭКРАНА ЗВОНКА"),
            "the theme preview lost its caps caption: \(rendered)"
        )
    }

    // MARK: - The guard itself

    /// The guard is only as strong as the spellings it recognises, and nothing
    /// else asserts on it: every other test here would stay green if it stopped
    /// matching. A caps section label renders `Localized.text(key).uppercased()`,
    /// so a missed lookup reaches the screen as `CREATE_ALARM.VOLUME.TITLE` —
    /// both spellings have to be a failure.
    func testKeyLeakGuardCatchesLowerAndUpperCasedKeys() {
        let key = "create_alarm.volume.title"
        for leaked in [key, key.uppercased()] {
            // `strict` is already the default, but it is the whole contract
            // here: with it off, a guard that stopped matching would record
            // nothing and this test would pass. Written out so nobody turns it
            // off by habit. The matcher is the other half: without it the
            // expectation swallows ANY recorded failure, so the test would
            // prove only that the guard went red, not that it named the
            // spelling that reached the screen. The two arrive as `strict:` +
            // trailing `issueMatcher:` because no overload takes `options:` and
            // a trailing `issueMatcher:` together — a matcher can still ride
            // inside the options, which is what the next test does.
            XCTExpectFailure("the guard has to name «\(leaked)»", strict: true) {
                Self.assertNoKeysLeaked(in: ["Громкость", leaked])
            } issueMatcher: { issue in
                issue.compactDescription.contains("«\(leaked)»")
            }
        }
    }

    /// The guard reports EVERY spelling that reached the screen, not just the
    /// first one it matches: a key that leaks into a plain label *and* a caps
    /// one is two call sites, and naming half of them sends the fixer to half
    /// the job. Nothing noticed when that was the case — going back to
    /// `spellings.first(where:)` still leaves the guard red, only with half the
    /// picture, so the test above and every other test here stay green (#757).
    /// Counting the reports is what tells the two loops apart.
    func testKeyLeakGuardReportsEverySpellingThatReachedTheScreen() {
        let key = "create_alarm.volume.title"

        let both = Self.issuesRecordedByGuard(over: ["Громкость", key, key.uppercased()])
        XCTAssertEqual(
            both.count, 2,
            "one key leaked in two spellings and the guard filed \(both.count) "
                + "report(s): \(Self.descriptions(of: both))"
        )
        for leaked in [key, key.uppercased()] {
            XCTAssertTrue(
                both.contains { $0.compactDescription.contains("«\(leaked)»") },
                "no report names «\(leaked)»: \(Self.descriptions(of: both))"
            )
        }

        // The other half of the contract, and the reason the count above is an
        // equality and not a `>= 2`: one spelling on screen stays one report.
        // A guard that reported both spellings of anything it matched would
        // satisfy the assertions above and be wrong about every real leak.
        for leaked in [key, key.uppercased()] {
            let single = Self.issuesRecordedByGuard(over: ["Громкость", leaked])
            XCTAssertEqual(
                single.count, 1,
                "«\(leaked)» leaked once and the guard filed \(single.count) "
                    + "report(s): \(Self.descriptions(of: single))"
            )
        }
    }

    /// Runs the guard over `rendered` and hands back the issues it recorded,
    /// absorbing them so the self-test itself stays green.
    ///
    /// Counting needs a matcher that accumulates instead of one that answers a
    /// single yes/no, so this is the second of the two shapes XCTest offers:
    /// the matcher goes inside `XCTExpectedFailure.Options`. The other shape —
    /// `strict:` plus a trailing `issueMatcher:`, used by the test above —
    /// cannot be combined with `options:`; that overload does not exist
    /// (`XCTest.swiftmodule/arm64-apple-ios-simulator.swiftinterface:100-118`),
    /// and reaching for it is what broke the whole test target's build once.
    private static func issuesRecordedByGuard(over rendered: [String]) -> [XCTIssue] {
        var recorded: [XCTIssue] = []
        let options = XCTExpectedFailure.Options()
        // Strict, as above: a guard that recorded nothing has to be a failure
        // rather than a quiet zero-count pass.
        options.isStrict = true
        options.issueMatcher = { issue in
            recorded.append(issue)
            return true
        }
        XCTExpectFailure("the guard has to report the leaked key", options: options) {
            assertNoKeysLeaked(in: rendered)
        }
        return recorded
    }

    private static func descriptions(of issues: [XCTIssue]) -> String {
        issues.isEmpty ? "nothing" : issues.map(\.compactDescription).joined(separator: " | ")
    }

    // MARK: - Helpers

    /// Every piece of text the subtree renders — plain labels, attributed
    /// labels (the caps captions are attributed) and the accessibility labels
    /// the brand controls expose instead of a reachable title label.
    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let field = view as? UITextField {
            found.append(contentsOf: [field.text, field.attributedPlaceholder?.string].compactMap { $0 })
        }
        if let control = view as? UIControl {
            found.append(contentsOf: [control.accessibilityLabel, control.accessibilityValue].compactMap { $0 })
        }
        if let button = view as? UIButton {
            found.append(contentsOf: [button.title(for: .normal)].compactMap { $0 })
            if let attributed = button.configuration?.attributedTitle {
                found.append(String(attributed.characters))
            }
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }

    /// The caps screen titles live in `navigationItem.titleView`, which is not
    /// part of the controller's own view tree.
    private static func titleViewStrings(of controller: UIViewController) -> [String] {
        let items: [UIView?] = [
            controller.navigationItem.titleView,
            (controller.navigationItem.leftBarButtonItem?.customView),
            (controller.navigationItem.rightBarButtonItem?.customView)
        ]
        return items.compactMap { $0 }.flatMap { strings(in: $0) }
    }

    private static func attributedStrings(in view: UIView) -> [NSAttributedString] {
        var found: [NSAttributedString] = []
        if let label = view as? UILabel, let attributed = label.attributedText {
            found.append(attributed)
        }
        return found + view.subviews.flatMap { attributedStrings(in: $0) }
    }

    private static func controls(in view: UIView) -> [UIControl] {
        let own = (view as? UIControl).map { [$0] } ?? []
        return own + view.subviews.flatMap { controls(in: $0) }
    }

    private static func textFields(in view: UIView) -> [UITextField] {
        let own = (view as? UITextField).map { [$0] } ?? []
        return own + view.subviews.flatMap { textFields(in: $0) }
    }

    /// A key that reached the screen looks like `create_alarm.volume.title` —
    /// or `CREATE_ALARM.VOLUME.TITLE`, because the caps section labels
    /// upper-case whatever `Localized.text` hands back, the key included when
    /// the lookup missed. Matching the lower-case spelling alone let every caps
    /// call site walk a leaked key past the guard (#713). Deliberately not
    /// counting the call sites: #713 said four, and any number written here
    /// goes stale on the next caps label.
    private static func assertNoKeysLeaked(
        in rendered: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for key in allKeys {
            // Both spellings are reported, not just the first match: a key that
            // leaks into a plain label AND a caps one is two call sites to fix,
            // and naming only the lower-case half sends the fixer to one of them.
            let spellings = key == key.uppercased() ? [key] : [key, key.uppercased()]
            for leaked in spellings where rendered.contains(leaked) {
                XCTFail(
                    "«\(leaked)» rendered as its own key — the catalogue lookup missed",
                    file: file, line: line
                )
            }
        }
    }

    // MARK: - Helpers: the table against the sources

    /// The two ways the table and the screens can disagree, as data.
    ///
    /// A function of both sides rather than a test body, so the tests can feed
    /// it a shrunk table and a screen that grew a key — the two failures this
    /// file has to be able to produce — without touching the checkout.
    private static func coverageGaps(
        copyKeys: Set<String>, keysOnScreen: Set<String>
    ) -> (unpinned: [String], stale: [String]) {
        let expected = keysOnScreen.subtracting(pinnedElsewhere)
        return (expected.subtracting(copyKeys).sorted(), copyKeys.subtracting(expected).sorted())
    }

    /// Where `screenSources` live in *this* checkout, derived from the
    /// compiled-in path of this file rather than from an absolute one.
    ///
    /// Parallel agents each build from their own worktree, so a hardcoded
    /// `/Users/…` would have every one of them reading the same foreign clone —
    /// the check would pass while the code under review went unread. `#filePath`
    /// is the worktree this file was compiled from, by construction. Asking the
    /// VCS for the root is not an option: this runs on the simulator, where
    /// spawning a subprocess is unavailable. Same technique, same reasons, as
    /// `AlertButtonLocalizationTests.appSourceRoot()`.
    private static func alarmSourceDirectory(filePath: StaticString = #filePath) -> URL {
        // <root>/SnoozePay/SnoozePayTests/AlarmEditorCopyTests.swift
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()  // SnoozePayTests
            .deletingLastPathComponent()  // SnoozePay (project dir)
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("SnoozePay/SnoozePay/ViewControllers/Alarms")
    }
}
