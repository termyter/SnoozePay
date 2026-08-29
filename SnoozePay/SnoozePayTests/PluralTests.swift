import XCTest
@testable import SnoozePay

/// Tests for the single plural rule that replaced the seven hand-written
/// copies found by #569.
///
/// The headline test is `testEveryFacadeAgreesWithTheSharedRule`: each copy was
/// defensible on its own, the problem was that they disagreed. Five of the
/// seven ignored the sign of `count` (`-1 % 10 == -1` in Swift, which falls
/// through every branch to the many form), while `AlarmsStreakBannerView` and
/// `SnoozeAffordability` normalised with `abs` first — so a negative count read
/// as "-1 откладываний" in the wallet-adjacent copy and "-1 откладывание" in
/// the affordability hint. Per-façade tests stayed green through that; the
/// cross-façade assertion is the guard.
///
/// The normalising behaviour (#546) wins: every call site passes a magnitude.
final class PluralTests: XCTestCase {

    /// The full boundary set — 11-14 and 111-114 are the traps in the Russian
    /// rule, and 101 / 1001 check that only the last two digits matter.
    private let boundaries = [0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 1001]

    // MARK: - Category

    func testRussianCategoriesAtTheBoundaries() {
        let expected: [Int: PluralCategory] = [
            0: .many, 1: .one, 2: .few, 4: .few, 5: .many,
            11: .many, 12: .many, 14: .many,
            21: .one, 22: .few, 25: .many,
            101: .one, 111: .many, 1001: .one
        ]
        XCTAssertEqual(Set(expected.keys), Set(boundaries))
        for (count, category) in expected {
            XCTAssertEqual(Plural.category(for: count), category, "count = \(count)")
        }
    }

    /// Negative counts are magnitudes with a sign bug upstream, not a separate
    /// declension: `-2` gets the same form as `2`.
    func testNegativeCountsUseTheMagnitude() {
        for count in boundaries {
            XCTAssertEqual(
                Plural.category(for: -count),
                Plural.category(for: count),
                "count = \(count)"
            )
        }
    }

    /// A two-form language must not inherit the Slavic split — this is the
    /// property that lets English land without touching a single call site.
    func testTwoFormLanguageSplitsOnlyOnOne() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(Plural.category(for: 1, locale: english), .one)
        for count in boundaries where count != 1 {
            XCTAssertEqual(Plural.category(for: count, locale: english), .many, "count = \(count)")
        }
    }

    // MARK: - Forms as data

    /// `few` defaults to `many` so a language without the form can omit it.
    func testFewFallsBackToMany() {
        let forms = PluralForms(one: "snooze", many: "snoozes")
        XCTAssertEqual(forms.form(.few), "snoozes")
        XCTAssertEqual(Plural.word(2, forms), "snoozes")
    }

    func testNounCatalogue() {
        XCTAssertEqual(Plural.word(1, .days), "день")
        XCTAssertEqual(Plural.word(3, .days), "дня")
        XCTAssertEqual(Plural.word(14, .days), "дней")

        XCTAssertEqual(Plural.word(1, .snoozes), "откладывание")
        XCTAssertEqual(Plural.word(22, .snoozes), "откладывания")
        XCTAssertEqual(Plural.word(0, .snoozes), "откладываний")

        // Genitive after «после» — 2-4 collapses onto the many form on purpose.
        XCTAssertEqual(Plural.word(1, .snoozesAfter), "откладывания")
        XCTAssertEqual(Plural.word(2, .snoozesAfter), "откладываний")
        XCTAssertEqual(Plural.word(11, .snoozesAfter), "откладываний")

        XCTAssertEqual(Plural.word(1, .mornings), "утро")
        XCTAssertEqual(Plural.word(2, .mornings), "утра")
        XCTAssertEqual(Plural.word(5, .mornings), "утр")
    }

    // MARK: - The seven former copies

    /// Every surviving name is now a one-line façade over the same rule, so
    /// each must track `Plural` across the whole boundary set, negatives
    /// included. This is what the seven copies could not do.
    func testEveryFacadeAgreesWithTheSharedRule() {
        for count in boundaries + boundaries.map({ -$0 }) {
            XCTAssertEqual(
                StatisticsViewModel.snoozeWord(count),
                Plural.word(count, .snoozes),
                "StatisticsViewModel, count = \(count)"
            )
            XCTAssertEqual(
                StatisticsViewModel.morningWord(count),
                Plural.word(count, .mornings),
                "StatisticsViewModel+Money, count = \(count)"
            )
            XCTAssertEqual(
                StreakModalViewController.dayWord(for: count),
                Plural.word(count, .days),
                "StreakModalViewController, count = \(count)"
            )
            XCTAssertEqual(
                WokeMorningContent.snoozeWord(for: count),
                Plural.word(count, .snoozesAfter),
                "WokeMorningContent, count = \(count)"
            )
            XCTAssertEqual(
                DepositPresets.snoozeNoun(for: count),
                Plural.word(count, .snoozes),
                "DepositPresets, count = \(count)"
            )
            XCTAssertEqual(
                SnoozeAffordability.snoozeWord(for: count),
                Plural.word(count, .snoozes),
                "SnoozeAffordability, count = \(count)"
            )
        }
    }

    /// The three façades that spell the same noun must also agree with each
    /// other — they were three separate word lists before.
    func testNominativeSnoozeCopyIsSpelledOnceEverywhere() {
        for count in boundaries {
            let statistics = StatisticsViewModel.snoozeWord(count)
            XCTAssertEqual(DepositPresets.snoozeNoun(for: count), statistics, "count = \(count)")
            XCTAssertEqual(SnoozeAffordability.snoozeWord(for: count), statistics, "count = \(count)")
        }
    }

    // MARK: - Display locale

    /// The seam #569 needs: one constant, not twelve `Locale(identifier:)`
    /// literals. Flipping it to the device locale must stay a one-line change.
    func testDisplayLocaleIsRussianForNow() {
        XCTAssertEqual(AppLocale.display.identifier, "ru_RU")
        XCTAssertEqual(AppLocale.display.language.languageCode?.identifier, "ru")
    }
}
