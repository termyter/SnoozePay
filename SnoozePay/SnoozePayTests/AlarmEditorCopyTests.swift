import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that #612 moved out of the alarms list and the alarm editor
/// (`ViewControllers/Alarms`, slice 2 of 3) into `Localizable.xcstrings`.
///
/// A wrong key is silent: `Localized.text` hands the key back, `VolumeCell`
/// renders `create_alarm.volume.title` where «Громкость» used to be, and the
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

    private static var allKeys: [String] { copy.keys.sorted() }

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
        let volume = VolumeCell(style: .default, reuseIdentifier: nil)

        let rendered = [sound, theme, vibration, volume].flatMap { Self.strings(in: $0.contentView) }
        Self.assertNoKeysLeaked(in: rendered)
        for key in [
            "create_alarm.sound.title", "create_alarm.theme.title",
            "create_alarm.vibration.title", "create_alarm.volume.title"
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

        // The caption is upper-cased at the call site, which is where that
        // decision belongs — the catalogue holds sentence case.
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
    /// catalogue-level assertion can see.
    func testVolumeRowKeepsBothItsNumberAndItsPercentSign() {
        let cell = VolumeCell(style: .default, reuseIdentifier: nil)

        cell.configure(volume: 0.8, fadeIn: true)
        XCTAssertTrue(
            Self.strings(in: cell.contentView).contains("80% · плавно"),
            "faded volume row reads \(Self.strings(in: cell.contentView))"
        )

        cell.configure(volume: 0.8, fadeIn: false)
        XCTAssertTrue(Self.strings(in: cell.contentView).contains("80%"))
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
    /// — no branch reads back a value the app assigned. So the *red* run was
    /// the honest one: it happened to be the run in which that layer was
    /// installed, which is the state every VoiceOver user is in. The green run
    /// only meant the layer had not been installed in the process yet, so the
    /// plain stored property answered instead. The old expectation was therefore
    /// unreachable in production, and `AlarmCell` no longer assigns it.
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
    /// The platform is the oracle, so the baseline has to be the platform. Both `nil` (layer not
    /// installed) or both `"1"`/`"0"` (installed) — either way the card is
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
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.sound_picker.preview_caps").uppercased()))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.sound_picker.volume_row")))
        XCTAssertTrue(
            rendered.contains("80% · плавно"),
            "the volume row lost its reading: \(rendered)"
        )
        XCTAssertEqual(
            Localized.format("create_alarm.sound_picker.custom_slot", SoundCatalogue.customSlot.name),
            "Своя мелодия · скоро"
        )
    }

    func testThemePickerRendersItsTitleAndSectionHeader() {
        // No `layoutIfNeeded`: the grid's section header is a supplementary
        // view, and forcing a collection-view pass here would buy one more
        // assertion at the price of rendering every theme tile.
        let picker = AlarmThemePickerViewController(currentTheme: .dawn, onSelect: { _ in })
        picker.loadViewIfNeeded()

        let rendered = Self.strings(in: picker.view) + Self.titleViewStrings(of: picker)
        Self.assertNoKeysLeaked(in: rendered)
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.theme_picker.title").uppercased()))
        XCTAssertTrue(rendered.contains(Localized.text("create_alarm.theme_picker.preview_caps")))
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

    /// A key that reached the screen looks like `create_alarm.volume.title`.
    private static func assertNoKeysLeaked(
        in rendered: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for key in allKeys where rendered.contains(key) {
            XCTFail("«\(key)» rendered as its own key — the catalogue lookup missed", file: file, line: line)
        }
    }
}
