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
/// `Localized.attributed`, so these tests are what stops the retired idiom
/// from growing back somewhere else and what stops the surviving one from
/// quietly flattening its insertion.
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
/// Mutation checks the assertions were written against (each names the first
/// assertion that fires):
///
/// | mutation | red |
/// |---|---|
/// | `replacing:` given a plain `NSAttributedString(string:)` | digit font is `h4`, not `moneyMd` |
/// | slider's `attributes:` applied over the whole result | the digit's font run spans `0..<5`, not `0..<1` |
/// | the placement widened to the whole template | the unit's run starts at 5, so `«7 мин»` is never found |
/// | `specifier: "%lld"` dropped back to the `%@` default | «%lld мин» holds no `%@`, so the debug trap fires |
final class AttributedSubstitutionTests: XCTestCase {

    // MARK: - The call site: the snooze slider's reading

    /// The reading the slider actually shows: «7 мин» with the digit in the
    /// mono headline face and the unit dimmed.
    ///
    /// Read off the rendered cell rather than off `valueText(_:)` — the method
    /// is private, and the label is what a person sees. `7` is chosen so the
    /// reading cannot be confused with the range-bound labels under the track,
    /// which read «1 мин» and «15 мин» through the same catalogue key.
    func testSliderReadingKeepsTheDigitInItsOwnRun() throws {
        let cell = SnoozeSliderCell(style: .default, reuseIdentifier: nil)
        cell.configure(minutes: 7)

        let reading = try XCTUnwrap(
            Self.attributedStrings(in: cell.contentView).first { $0.string == "7 мин" },
            "the slider never rendered «7 мин»: \(Self.attributedStrings(in: cell.contentView).map(\.string))"
        )

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

    /// Two digits, to pin that the specifier is *replaced* rather than the
    /// digits being searched for afterwards: «15 мин» has its number at the
    /// same offset the template's `%lld` occupied, and both digits carry the
    /// mono face.
    func testSliderReadingStylesBothDigitsOfATwoDigitValue() throws {
        let cell = SnoozeSliderCell(style: .default, reuseIdentifier: nil)
        cell.configure(minutes: 12)

        let reading = try XCTUnwrap(
            Self.attributedStrings(in: cell.contentView).first { $0.string == "12 мин" }
        )
        var digitRun = NSRange(location: NSNotFound, length: 0)
        XCTAssertEqual(reading.attribute(.font, at: 0, effectiveRange: &digitRun) as? UIFont, AppTypography.moneyMd)
        assertRun(
            digitRun,
            location: 0,
            length: 2,
            "the second digit fell out of the mono run"
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
    /// `attributed(_:attributes:replacing:)` traps by design, which would
    /// abort the suite instead of measuring anything.
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

    /// Every `attributedText` in the tree, in traversal order.
    private static func attributedStrings(in view: UIView) -> [NSAttributedString] {
        var found: [NSAttributedString] = []
        if let label = view as? UILabel, let text = label.attributedText {
            found.append(text)
        }
        for subview in view.subviews {
            found.append(contentsOf: attributedStrings(in: subview))
        }
        return found
    }
}
