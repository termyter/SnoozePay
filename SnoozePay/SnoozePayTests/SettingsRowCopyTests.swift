import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that this slice of #600 moved out of
/// `SettingsViewController+Sections.swift` into `Localizable.xcstrings`.
///
/// A wrong key is silent: `Localized.text` hands the key back, the row renders
/// `settings.row.volume` where «Громкость» used to be, and the build ships. So,
/// mirroring `AlarmEditorCopyTests`, the assertions come in three layers and a
/// red run names which one broke:
///
///  1. **Catalogue layer** — every key exists.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration, transcribed here from the pre-migration literals rather
///     than read back out of the file under test.
///  3. **Call-site layer** — the real rows are built through the data source
///     and what they render is compared against the catalogue. Layers 1 and 2
///     are blind to a typo in the *key* at the call site, because in that case
///     the catalogue itself is fine.
///
/// # What layer 3 does NOT reach
///
/// Five of the sixteen keys are only ever read while a `UIAlertController` is
/// being assembled, and this slice left that assembly inline in
/// `presentRecoveryConfirmation()` / the two pickers. They are covered by
/// layers 1 and 2 only:
///
///  * `settings.picker.applies_to_new_alarms`
///  * `settings.recovery.alert_title`
///  * `settings.recovery.alert_message`
///  * `settings.recovery.confirm`
///  * `common.button.cancel` — its words are asserted here, but no call site
///    of it is; the key predates this slice and three other screens read it.
///
/// "Not covered in this slice", not "not reachable": the same move that made
/// the recovery row testable would work here — extracting
/// `makeRecoveryAlert() -> UIAlertController` would put `alert.title`,
/// `alert.message` and `alert.actions.map(\.title)` in reach with no window
/// and no presentation at all. That is a change to production structure, and
/// this slice moves strings only.
@MainActor
final class SettingsRowCopyTests: XCTestCase {

    // MARK: - Layer 1 + 2: the catalogue and its words

    /// The strings as they read on screen today, copied from the literals this
    /// slice replaced. A list derived from the catalogue would agree with any
    /// mistake in it.
    private static let copy: [String: String] = [
        "common.button.cancel": "Отмена",
        "settings.picker.applies_to_new_alarms": "Применяется к новым будильникам",
        "settings.picker.minutes_option": "%lld мин",
        "settings.recovery.alert_message": "Будильники и история операций будут удалены безвозвратно, "
            + "а хранилище разблокировано. Это действие нельзя отменить.",
        "settings.recovery.alert_title": "Стереть повреждённые данные?",
        "settings.recovery.confirm": "Подтвердить",
        "settings.recovery.row_subtitle": "Хранилище повреждено и заблокировано",
        "settings.recovery.row_title": "Стереть повреждённые данные",
        "settings.row.contact": "Связаться с нами",
        "settings.row.default_price": "Цена откладывания по умолчанию",
        "settings.row.privacy_policy": "Политика конфиденциальности",
        "settings.row.progressive_price": "Прогрессивная цена",
        "settings.row.snooze_duration": "Длительность откладывания",
        "settings.row.terms": "Пользовательское соглашение",
        "settings.row.vibration": "Вибрация",
        "settings.row.volume": "Громкость"
    ]

    func testEveryKeyResolvesToCopyRatherThanToItself() {
        for key in Self.copy.keys {
            XCTAssertNotEqual(Localized.text(key), key, "missing catalogue key: \(key)")
        }
    }

    func testCatalogueStillHoldsTheWordsTheScreenShipped() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for: \(key)")
        }
    }

    /// The alert body was two Swift literals concatenated to fit the line, and
    /// the seam carried the space. One key now, so the space has to live inside
    /// the catalogue value — nothing in the compiler notices if it is dropped.
    func testRecoveryAlertMessageKeepsTheSpaceAtTheOldConcatenationSeam() {
        XCTAssertTrue(
            Localized.text("settings.recovery.alert_message").contains("безвозвратно, а хранилище"),
            "the seam between the two former literals lost its space"
        )
    }

    /// `%lld` and not `%@`: the call sites pass an `Int`, and a mismatched
    /// specifier prints garbage rather than failing to build.
    func testMinutesOptionSubstitutesTheNumber() {
        XCTAssertEqual(Localized.format("settings.picker.minutes_option", 7), "7 мин")
    }

    // MARK: - Layer 3: the rows are wired to those keys

    func testFinanceRowsRenderCatalogueCopy() {
        let sut = makeSUT(snoozeMinutes: 7)
        let section = sut.sectionIndex(of: .finance)

        assertRenders(["settings.row.default_price"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(["settings.row.snooze_duration"], in: sut, at: IndexPath(row: 1, section: section))
        XCTAssertTrue(
            Self.strings(in: sut.cell(at: IndexPath(row: 1, section: section))).contains("7 мин"),
            "the snooze-duration row lost its «N мин» trailing value"
        )
    }

    func testSoundRowsRenderCatalogueCopy() {
        let sut = makeSUT()
        let section = sut.sectionIndex(of: .soundNotifications)

        assertRenders(["settings.row.volume"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(["settings.row.vibration"], in: sut, at: IndexPath(row: 1, section: section))
    }

    func testRulesRowRendersCatalogueCopy() {
        let sut = makeSUT()
        assertRenders(
            ["settings.row.progressive_price"],
            in: sut,
            at: IndexPath(row: 0, section: sut.sectionIndex(of: .rules))
        )
    }

    func testOtherRowsRenderCatalogueCopy() {
        let sut = makeSUT()
        let section = sut.sectionIndex(of: .other)

        assertRenders(["settings.row.privacy_policy"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(["settings.row.terms"], in: sut, at: IndexPath(row: 1, section: section))
        assertRenders(["settings.row.contact"], in: sut, at: IndexPath(row: 2, section: section))
    }

    /// The recovery row is built directly rather than through the data source:
    /// it only exists while a repository reports `lastLoadFailed`, which is
    /// global state this test has no honest way to fake. The index path is a
    /// live one so the dequeue is real; the builder ignores everything about it
    /// beyond that.
    func testRecoveryRowRendersCatalogueCopy() {
        let sut = makeSUT()
        let cell = sut.makeRecoveryCell(at: IndexPath(row: 0, section: sut.sectionIndex(of: .finance)))
        let rendered = Self.strings(in: cell)

        for key in ["settings.recovery.row_title", "settings.recovery.row_subtitle"] {
            XCTAssertTrue(rendered.contains(Localized.text(key)), "recovery row is not wired to \(key)")
        }
    }

    // MARK: - Helpers

    private func makeSUT(snoozeMinutes: Int? = nil) -> SettingsViewController {
        let suite = "test.settings.rowcopy.\(UUID().uuidString)"
        let defaults = AlarmDefaults(defaults: UserDefaults(suiteName: suite)!)
        if let snoozeMinutes { defaults.snoozeMinutes = snoozeMinutes }
        let sut = SettingsViewController(alarmDefaults: defaults)
        sut.loadViewIfNeeded()
        return sut
    }

    private func assertRenders(
        _ keys: [String],
        in sut: SettingsViewController,
        at indexPath: IndexPath,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rendered = Self.strings(in: sut.cell(at: indexPath))
        for key in keys {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "row \(indexPath) renders \(rendered) — not the copy of \(key)",
                file: file,
                line: line
            )
        }
    }

    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let control = view as? UIControl {
            found.append(contentsOf: [control.accessibilityLabel].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }
}

private extension SettingsViewController {

    /// Section indices are POSITIONS in the live table, not raw values:
    /// `.referral` is hidden behind a flag (#676), so everything after it
    /// shifts up and a raw-value probe reads the wrong section in silence.
    func sectionIndex(of section: Section, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let index = visibleSections.firstIndex(of: section) else {
            XCTFail("section \(section) is not visible; nothing to probe", file: file, line: line)
            return 0
        }
        return index
    }

    func cell(at indexPath: IndexPath) -> UITableViewCell {
        self.tableView(self.tableView, cellForRowAt: indexPath)
    }
}
