import XCTest
@testable import SnoozePay

/// Guards the keys `AlarmsListViewModel` and `StatisticsViewModel` moved into
/// `Localizable.xcstrings` (#599, part of #569).
///
/// A missed key is the quiet failure mode of this whole migration: `Localized`
/// echoes the key back, so the alarm card renders `alarms.days.weekend`
/// instead of «Выходные» and nothing throws, logs, or fails to compile.
///
/// The behavioural assertions on the migrated call sites are NOT here — they
/// already exist in `AlarmsListViewModelTests`, `AlarmsListCapsRowTests`,
/// `AlarmsListZeroBalanceAndWrapTests` and `StatisticsViewModelTests`, still
/// comparing against the Russian words verbatim. #599 deliberately left those
/// untouched: unchanged, they now assert the whole chain (call site → key →
/// catalogue → copy) rather than just the tail of it, and a test edited in the
/// same commit as the code it covers catches one regression fewer. What is
/// added here is only what those tests cannot see — that a key exists at all,
/// and that its substitution specifier survived the trip into JSON.
final class ViewModelLocalizationTests: XCTestCase {

    /// Every key #599 introduced. Listed literally rather than derived from
    /// the catalogue, so deleting an entry fails instead of shrinking the loop.
    private static let migratedKeys = [
        "alarms.days.every_day",
        "alarms.days.once",
        "alarms.days.once_on",
        "alarms.days.weekdays",
        "alarms.days.weekend",
        "alarms.error.rollback_persist_failed",
        "alarms.hint.zero_balance",
        "alarms.penalty",
        "statistics.last_slip",
        "statistics.last_slip.none",
        "statistics.tooltip.no_alarm",
        "statistics.tooltip.woke",
        "statistics.trend.better",
        "statistics.trend.delta",
        "statistics.trend.no_change",
        "statistics.trend.same",
        "statistics.trend.worse"
    ]

    // MARK: - The keys resolve

    func testEveryMigratedKeyResolvesToCopyRatherThanToItself() {
        for key in Self.migratedKeys {
            let value = Localized.text(key)
            XCTAssertNotEqual(
                value, key,
                "missing catalogue entry: \(key) — the UI would render the key itself"
            )
            XCTAssertFalse(value.isEmpty, "empty catalogue value for \(key)")
        }
    }

    /// A key present but mistyped in Swift resolves to nothing; a key present
    /// in both places but *empty* in the catalogue would pass the check above
    /// only by accident. Asserting the copy is Russian pins the entry to the
    /// language the source catalogue is written in.
    func testMigratedCopyIsTheRussianSourceText() {
        for key in Self.migratedKeys {
            let isCyrillic = Localized.text(key).unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
            XCTAssertTrue(isCyrillic, "catalogue value for \(key) carries no Russian text")
        }
    }

    // MARK: - Substitutions survived the move into JSON

    /// The specifier is the part of a migrated string most easily lost: drop
    /// `%@` while retyping the copy and `Localized.format` still returns a
    /// perfectly readable sentence — just one with the number missing from it.
    func testFormatKeysKeepTheirSubstitutionSpecifier() {
        for key in ["alarms.days.once_on", "alarms.penalty", "statistics.last_slip", "statistics.trend.delta"] {
            XCTAssertTrue(
                Localized.text(key).contains("%@"),
                "\(key) lost its %@ specifier — the substituted value would vanish silently"
            )
        }
    }

    func testFormattedKeysSubstituteTheirArgument() {
        XCTAssertTrue(AlarmsListViewModel.weekdayPhrase(for: [1, 3], repeatMode: .never).contains("Вт, Чт"))
        XCTAssertEqual(StatisticsViewModel.subtitle(forDiff: -3), "−3 к прошлой неделе")
    }

    // MARK: - Weekday names come from the calendar, not from the catalogue

    /// `WeekdayNames` replaced two hand-written arrays with locale data, and
    /// the swap is only safe because Foundation's Russian standalone symbols
    /// match the design copy character for character. That is an assumption
    /// about CLDR, not about this code, so it is asserted rather than trusted:
    /// if a future OS reshapes the symbols, this names the cause instead of
    /// reddening a dozen unrelated caps-row and heatmap tests.
    func testShortWeekdayNamesAreTheDesignCopyMondayFirst() {
        XCTAssertEqual(WeekdayNames.short, ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
    }

    func testFullWeekdayNamesAreLowercaseMondayFirst() {
        XCTAssertEqual(
            WeekdayNames.full,
            ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
        )
    }

    func testViewModelsExposeTheCalendarBackedWeekdayNames() {
        XCTAssertEqual(StatisticsViewModel.weekdayShortLabels, WeekdayNames.short)
        XCTAssertEqual(StatisticsViewModel.weekdayFullNames, WeekdayNames.full)
    }

    // MARK: - Date format stayed behaviour rather than becoming copy

    /// `dayMonthText` moved from the literal pattern `"d MMMM"` to a localized
    /// template. Under `ru_RU` the template resolves to the same pattern, so
    /// the rendered date must not have moved — and the month must stay in the
    /// genitive the pattern produces («8 января», not «8 январь»), which is
    /// exactly what a catalogue string would have got wrong.
    func testDayMonthTextIsUnchangedByTheTemplateSwitch() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 8
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        XCTAssertEqual(StatisticsViewModel.dayMonthText(date), "8 января")
    }
}
