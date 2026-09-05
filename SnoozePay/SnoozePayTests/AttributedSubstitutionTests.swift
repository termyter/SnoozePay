import UIKit
import XCTest
@testable import SnoozePay

/// Guards the one mechanism that puts a differently-styled run inside a
/// localized sentence: `Localized.attributed(_:attributes:replacing:specifier:)`.
///
/// Until #722 there were two. `SnoozeSliderCell.valueText(_:)` rendered the
/// whole phrase and then *located* the number with `range(of:)` to restyle it;
/// `Localized.attributed` substitutes an already-styled run over the
/// specifier. Neither doc comment mentioned the other and both argued the same
/// motive as though it were theirs alone. The slider now goes through
/// `Localized.attributed`.
///
/// # What these tests hold — and what they do not
///
/// They pin the **rendering**: the phrase, the run boundaries, the fonts and
/// the colours on each side of an insertion. Nothing here inspects which
/// mechanism produced that rendering, so — contrary to what this comment
/// claimed until review — they are not what stops the retired idiom from
/// growing back. For the slider's own inputs the two idioms agree byte for
/// byte: minutes are 1...15, «7» occurs exactly once in «7 мин», and a
/// `range(of:)` written back into `valueText(_:)` would pass every assertion
/// in this file.
///
/// One test does separate the mechanisms —
/// `testRunLandsOnTheSpecifierRatherThanOnTheFirstMatchingText` — and it
/// separates them *inside* `Localized.attributed`, for a caller that still
/// calls it. What keeps the app on one idiom is that there is one method with
/// three call sites, which is a fact about the code and not about this file.
///
/// # Why every expectation here is a literal
///
/// The failure worth catching is «the inserted run arrived flattened to the
/// surrounding font» — paler on screen, identical in `.string`. An oracle
/// built by calling `Localized.attributed` (or `Localized.format`) a second
/// time agrees with whatever the code does, including that. So the phrases,
/// the offsets and the fonts below are spelled out by hand: `«7 мин»`, the
/// digit at `0..<1`, the unit at `1..<5`. If the substitution stops carrying
/// its own attributes, or starts carrying them over the whole phrase, a run
/// boundary moves and these go red.
///
/// # Mutations these assertions were written against
///
/// ⚠️ Derived by **reading** the assertions, not by running them: no mutation
/// below was committed or executed — this agent has no simulator tools and a
/// local test run is barred in `/team`. Read each entry as «this is the
/// assertion that should fire», not as a mutation-testing report. The one
/// executor is the `Unit tests` job.
///
/// A list rather than a table: the reasons do not fit in a cell, and a cell
/// that has to be shortened is where the wrong reason gets written down.
///
///   * **`replacing:` given a plain `NSAttributedString(string:)`** —
///     `testSliderReadingKeepsTheDigitInItsOwnRun`, at the digit's font. It
///     fails against `nil`, not against `h4`: the base attributes go on the
///     *template's* characters, and `replaceCharacters(in:with:)` hands the
///     replaced range the insertion's own attributes, which this mutation
///     leaves empty.
///   * **the slider's `attributes:` re-applied over the whole result** — same
///     test, same first assertion, but the digit's font now reads `h4`. The
///     run-width check below it never gets to speak.
///   * **the placement widened from the specifier to the whole template** —
///     same test, at the phrase equality: `valueText(7)` returns «7», so there
///     is no run left to measure.
///   * **the insertion collapsed to one uniform face** —
///     `testInsertionKeepsItsOwnRunsWhenTheyDiffer`: the font at index 1 is
///     the first face rather than the second.
///   * **`MoneyFormatter`'s narrow space refonted to the digits face** —
///     `testMoneyRunSurvivesPlacementWithAllThreeOfItsFaces`, at index 26.
///   * **`Localized.attributed` reverted to render-then-`range(of:)`** —
///     `testRunLandsOnTheSpecifierRatherThanOnTheFirstMatchingText`: the
///     inserted run starts at 3 instead of 22.
///
/// One mutation is listed apart, because its consequence is not «a red test»
/// and putting it in the list above would read as though it were: dropping
/// `specifier: "%lld"` back to the `%@` default leaves «%lld мин» holding no
/// `%@`, which reaches the `assertionFailure` inside `Localized.attributed`.
/// In the DEBUG build the test target uses, that traps and **aborts the
/// process** — the whole run dies and is reported as a crash, not as one
/// failing assertion.
final class AttributedSubstitutionTests: XCTestCase {

    // MARK: - The call site: the snooze slider's reading

    /// The reading the slider shows: «7 мин» with the digit in the mono
    /// headline face and the unit dimmed.
    ///
    /// Read off `valueText(_:)` directly rather than off the label. Through
    /// `valueLabel.attributedText` the two expectations that matter most —
    /// `moneyMd` and `fg1` on the digit — are also the label's own defaults
    /// (`SnoozeSliderCell.valueLabel`), so were `UILabel` to fill unattributed
    /// stretches in from its own font and colour, the mutation «the insertion
    /// carries no attributes» would read back as correct. Taking the method's
    /// return value removes the label from the oracle. That the cell then
    /// renders this into the label is pinned separately, by
    /// `AlarmEditorCopyTests.testSnoozeSliderReadingKeepsItsNumberInTheHeadlineFace`.
    ///
    /// The method is `internal` for exactly this; `7` is chosen so the reading
    /// cannot be confused with the range-bound labels under the track, which
    /// read «1 мин» and «15 мин» through the same catalogue key.
    func testSliderReadingKeepsTheDigitInItsOwnRun() {
        let reading = SnoozeSliderCell.valueText(7)

        // The whole phrase, spelled out: one catalogue entry, not a digit
        // concatenated with a unit here.
        XCTAssertEqual(reading.string, "7 мин")
        XCTAssertEqual(reading.length, 5)

        var digitRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(
            reading.attribute(.font, at: 0, effectiveRange: &digitRun) as? UIFont,
            AppTypography.moneyMd,
            "the digit lost the mono headline face — the substituted run arrived flattened"
        )
        assertRun(
            digitRun,
            location: 0,
            length: 1,
            "the digit's face bled past the digit: only «7» is in mono, «мин» is not"
        )
        XCTAssertEqual(
            reading.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
            AppColors.fg1
        )

        var unitRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(
            reading.attribute(.font, at: 1, effectiveRange: &unitRun) as? UIFont,
            AppTypography.h4,
            "the unit lost its dimmed face"
        )
        assertRun(
            unitRun,
            location: 1,
            length: 4,
            "«мин» is one run from the space to the end"
        )
        XCTAssertEqual(
            reading.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? UIColor,
            AppColors.fg3
        )
    }

    /// A two-digit value keeps **both** digits in the mono face, and the run
    /// stops there.
    ///
    /// This does not distinguish the two idioms — `range(of: "12")` would find
    /// the same two characters. What it catches is an insertion styled in part
    /// (a run that covers the first digit only) and a run that spills into the
    /// space, neither of which the single-digit case can see, since at length
    /// 1 «too narrow» and «too wide» are the same assertion.
    func testSliderReadingStylesBothDigitsOfATwoDigitValue() {
        let reading = SnoozeSliderCell.valueText(12)

        XCTAssertEqual(reading.string, "12 мин")
        var digitRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(reading.attribute(.font, at: 0, effectiveRange: &digitRun) as? UIFont, AppTypography.moneyMd)
        assertRun(
            digitRun,
            location: 0,
            length: 2,
            "the second digit fell out of the mono run"
        )
    }

    // MARK: - The mechanism: placement by specifier, not by search

    /// The property #722 names as the second reason this idiom survived, and
    /// the only assertion in the file that a locate-and-restyle implementation
    /// fails: the run lands where the **specifier stood**, not where a search
    /// of the rendered sentence first hits.
    ///
    /// `alarm_off.body` reads «За эту неделю списано %@. …», so substituting
    /// the fragment «эту» makes the rendered sentence hold it twice — at 3, in
    /// the copy, and at 22, where the `%@` was. Render-then-`range(of:)`
    /// restyles the first occurrence it finds, which is the wrong one and says
    /// nothing about it; substitution over the specifier cannot.
    ///
    /// The slider's own inputs cannot express this — «7» occurs once in
    /// «7 мин» — which is why the case had to be built from a call site whose
    /// copy repeats a word, rather than found in one.
    func testRunLandsOnTheSpecifierRatherThanOnTheFirstMatchingText() {
        let inserted = UIFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let surrounding = UIFont.systemFont(ofSize: 17)

        let result = Localized.attributed(
            "alarm_off.body",
            attributes: [.font: surrounding],
            replacing: NSAttributedString(string: "эту", attributes: [.font: inserted])
        )

        XCTAssertEqual(
            result.string,
            "За эту неделю списано эту. Возможно, что-то пошло не так. Что хотите сделать?"
        )

        // «За эту неделю списано » is 22 UTF-16 units; the earlier «эту» sits
        // at 3.
        var insertedRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(
            result.attribute(.font, at: 22, effectiveRange: &insertedRun) as? UIFont,
            inserted,
            "the run did not land where the specifier was"
        )
        assertRun(insertedRun, location: 22, length: 3, "the inserted run is «эту» and nothing else")
        XCTAssertEqual(
            result.attribute(.font, at: 3, effectiveRange: nil) as? UIFont,
            surrounding,
            "the earlier «эту» was restyled — the run was located by text rather than placed by specifier"
        )
    }

    // MARK: - The mechanism: a non-uniform insertion survives

    /// The property locate-and-restyle could not have: an insertion that is
    /// **not** uniform inside itself keeps every one of its own runs.
    ///
    /// Fonts here are built in the test rather than taken from
    /// `AppTypography`, so a design-token rename cannot make this pass or fail
    /// for a reason that has nothing to do with substitution.
    func testInsertionKeepsItsOwnRunsWhenTheyDiffer() {
        let first = UIFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let second = UIFont.italicSystemFont(ofSize: 13)
        let surrounding = UIFont.systemFont(ofSize: 17)

        let replacement = NSMutableAttributedString(
            string: "1", attributes: [.font: first, .foregroundColor: UIColor.red]
        )
        replacement.append(
            NSAttributedString(string: "2", attributes: [.font: second, .foregroundColor: UIColor.green])
        )

        let result = Localized.attributed(
            "create_alarm.snooze.minutes",
            attributes: [.font: surrounding, .foregroundColor: UIColor.blue],
            replacing: replacement,
            specifier: "%lld"
        )

        XCTAssertEqual(result.string, "12 мин")

        var firstRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(result.attribute(.font, at: 0, effectiveRange: &firstRun) as? UIFont, first)
        assertRun(firstRun, location: 0, length: 1, "the first inserted run is one character wide")
        XCTAssertEqual(result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .red)

        var secondRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(
            result.attribute(.font, at: 1, effectiveRange: &secondRun) as? UIFont,
            second,
            "the insertion was collapsed to one uniform face — the very thing the retired idiom could not avoid"
        )
        assertRun(secondRun, location: 1, length: 1, "the second inserted run is one character wide")
        XCTAssertEqual(result.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor, .green)

        var tailRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(result.attribute(.font, at: 2, effectiveRange: &tailRun) as? UIFont, surrounding)
        assertRun(tailRun, location: 2, length: 4, "the surrounding copy is one run after the insertion")
    }

    /// `specifier` defaults to `%@`, so the call sites that predate the
    /// parameter are untouched: `alarm_off.body` still places its amount where
    /// the Russian sentence puts it, with the surrounding copy in its own face.
    func testDefaultSpecifierStillPlacesTheRunWhereTheCopyPutsIt() {
        let inserted = UIFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let surrounding = UIFont.systemFont(ofSize: 17)

        let result = Localized.attributed(
            "alarm_off.body",
            attributes: [.font: surrounding],
            replacing: NSAttributedString(string: "−750 ₽", attributes: [.font: inserted])
        )

        XCTAssertEqual(
            result.string,
            "За эту неделю списано −750 ₽. Возможно, что-то пошло не так. Что хотите сделать?"
        )
        // «За эту неделю списано » is 22 UTF-16 units; the amount is 6.
        var amountRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(result.attribute(.font, at: 22, effectiveRange: &amountRun) as? UIFont, inserted)
        assertRun(amountRun, location: 22, length: 6, "the amount is exactly the inserted run, no more")
        XCTAssertEqual(result.attribute(.font, at: 21, effectiveRange: nil) as? UIFont, surrounding)
        XCTAssertEqual(result.attribute(.font, at: 28, effectiveRange: nil) as? UIFont, surrounding)
    }

    /// The real `alarm_off.body` insertion — `MoneyFormatter.attributed(_:)` —
    /// is internally non-uniform: digits in mono, the narrow space refonted,
    /// the ₽ sign back in mono. All three runs have to survive the placement.
    func testMoneyRunSurvivesPlacementWithAllThreeOfItsFaces() {
        let digits = AppFonts.mono(.bold, 17)
        let space = AppFonts.sans(.regular, 17)

        let result = Localized.attributed(
            "alarm_off.body",
            attributes: [.font: AppTypography.bodyLg, .foregroundColor: AppColors.fg2],
            replacing: MoneyFormatter.attributed(
                Decimal(750), digitsFont: digits, prefix: "−", color: AppColors.pain400
            )
        )

        XCTAssertEqual(
            result.string,
            "За эту неделю списано −750\u{202F}₽. Возможно, что-то пошло не так. Что хотите сделать?"
        )
        // 22 prefix + «−750» (4) + narrow space (1) + «₽» (1).
        XCTAssertEqual(result.attribute(.font, at: 22, effectiveRange: nil) as? UIFont, digits)
        XCTAssertEqual(
            result.attribute(.font, at: 26, effectiveRange: nil) as? UIFont,
            space,
            "the narrow space lost its sans face — the insertion was flattened to one font"
        )
        XCTAssertEqual(result.attribute(.font, at: 27, effectiveRange: nil) as? UIFont, digits)
        XCTAssertEqual(result.attribute(.foregroundColor, at: 27, effectiveRange: nil) as? UIColor, AppColors.pain400)
        XCTAssertEqual(result.attribute(.font, at: 28, effectiveRange: nil) as? UIFont, AppTypography.bodyLg)
    }

    /// A template with no specifier at all keeps the run rather than losing
    /// it. Reached through `appendingUnplaceable` directly: the path through
    /// `attributed(_:attributes:replacing:specifier:)` traps by design, which
    /// would abort the suite instead of measuring anything.
    func testUnplaceableRunIsAppendedRatherThanDropped() {
        let inserted = UIFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let result = Localized.appendingUnplaceable(
            template: "Списано.",
            attributes: [.font: UIFont.systemFont(ofSize: 17)],
            replacement: NSAttributedString(string: "−750", attributes: [.font: inserted])
        )

        XCTAssertEqual(result.string, "Списано.−750")
        XCTAssertEqual(result.attribute(.font, at: 8, effectiveRange: nil) as? UIFont, inserted)
    }

    // MARK: - Helpers

    /// `NSRange` compared field by field: a red run should name whether the
    /// run started in the wrong place or ran the wrong distance.
    private func assertRun(
        _ range: NSRange,
        location: Int,
        length: Int,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(range.location, location, "\(message) — run starts at \(range.location)", file: file, line: line)
        XCTAssertEqual(range.length, length, "\(message) — run is \(range.length) long", file: file, line: line)
    }
}
