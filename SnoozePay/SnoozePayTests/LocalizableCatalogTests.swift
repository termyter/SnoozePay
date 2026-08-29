import XCTest
@testable import SnoozePay

/// Guards `Resources/Localizable.xcstrings` — the scaffold #598-#601 build on.
///
/// A missing key in a string catalogue is the quietest failure in the project:
/// nothing throws, nothing logs, the label simply renders `create_alarm.wake_up`
/// instead of «Подъём» and ships. Neither the compiler nor SwiftLint can see it,
/// because a key is a perfectly ordinary `String`. These tests are the only
/// thing standing between a typo'd key and the App Store.
///
/// The assertions are deliberately layered from "is the catalogue in the target
/// at all" through "does a plain key resolve" to "do the plural forms resolve",
/// so a red run names the broken layer instead of just the symptom. That
/// matters more than usual here: this project's unit tests run in CI only
/// (CLAUDE.md), so every diagnostic round-trip costs ~4 minutes.
final class LocalizableCatalogTests: XCTestCase {

    // MARK: - Layer 1: the catalogue reaches the built product

    /// The catalogue joins the target through the
    /// `PBXFileSystemSynchronizedRootGroup` for `SnoozePay/`, whose only
    /// membership exception is `Info.plist` — nothing declares
    /// `Localizable.xcstrings` anywhere. This asserts the compiled output of
    /// that arrangement rather than the arrangement itself: Xcode's build turns
    /// the catalogue into `ru.lproj/Localizable.strings`, so if the file ever
    /// stops being a target member, this is what notices.
    func testCompiledCatalogueShipsInsideTheAppBundle() {
        XCTAssertTrue(
            Bundle.main.localizations.contains("ru"),
            "The app bundle declares no ru localization — Localizable.xcstrings "
                + "is not being compiled into the target. Bundle.main.localizations = "
                + "\(Bundle.main.localizations)"
        )
        XCTAssertNotNil(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "ru.lproj"),
            "ru.lproj exists but holds no compiled Localizable.strings."
        )
    }

    /// `Localized` must reach the Russian bundle rather than fall back to
    /// `.main`. While `knownRegions` is `(en, Base)` (#596), `.main` negotiates
    /// to `Base.lproj`, which contains no copy at all — so this failing means
    /// every string in the app has silently become its own key.
    func testLocalizedResolvesToTheRussianBundle() {
        XCTAssertNotEqual(
            Localized.bundle.bundlePath,
            Bundle.main.bundlePath,
            "Localized fell back to Bundle.main; ru.lproj was not found."
        )
    }

    // MARK: - Layer 2: plain keys

    func testTimePickerHeaderResolves() {
        XCTAssertEqual(Localized.text("create_alarm.wake_up"), "Подъём")
    }

    /// The miss detector itself, without which every other assertion here could
    /// pass against an empty catalogue: an absent key comes back as the key.
    func testAbsentKeyEchoesItselfAndReadsAsNil() {
        let absent = "no_such.key.anywhere"
        XCTAssertEqual(Localized.text(absent), absent)
        XCTAssertNil(Localized.optionalText(absent))
    }

    func testSubstitutionAppliesArgumentsToTheLookupResult() {
        // No catalogue entry needed: an absent key comes back verbatim, which
        // makes the key itself a convenient format string to assert on.
        XCTAssertEqual(Localized.format("%@ / %lld", "a", 2), "a / 2")
        XCTAssertEqual(Localized.format("create_alarm.wake_up"), "Подъём")
    }

    // MARK: - Layer 3: the plural nouns

    /// Every form of every pluralised noun must come back as copy, not as a
    /// key. `PluralTests` checks the words are the *right* words; this checks
    /// that all twelve keys exist, including the ones no boundary in
    /// `PluralTests` happens to land on.
    func testEveryPluralFormResolves() {
        for noun in ["plural.days", "plural.mornings", "plural.snoozes", "plural.snoozes_after"] {
            for category in ["one", "few", "many"] {
                let key = "\(noun).\(category)"
                XCTAssertNotNil(Localized.optionalText(key), "missing catalogue key: \(key)")
            }
        }
    }

    /// The genitive-under-«после» set is a separate entry whose `few` collapses
    /// onto `many` on purpose (#604). Asserting the collapse here — next to the
    /// nominative set that does *not* collapse — is what stops a future reader
    /// from "fixing" the duplication in the catalogue.
    func testGenitiveSnoozeFormsDifferFromTheNominativeOnes() {
        XCTAssertEqual(Localized.text("plural.snoozes_after.few"), Localized.text("plural.snoozes_after.many"))
        XCTAssertNotEqual(Localized.text("plural.snoozes.few"), Localized.text("plural.snoozes.many"))
        XCTAssertNotEqual(Localized.text("plural.snoozes_after.one"), Localized.text("plural.snoozes.one"))
    }

    // MARK: - Layer 4: the plural-variation shape #598-#601 migrate to

    /// `example.days_count` is the worked example of a real `Variations →
    /// Plural` entry: the number lives in the string, so the catalogue picks
    /// the form itself and `Plural` drops out of the loop.
    ///
    /// It is here because the shape is not guessable — `xcstringstool` rejects
    /// a plural variation whose value omits the number, which is exactly why
    /// the `plural.*` nouns above are flat keys instead. Keeping a compiled,
    /// asserted specimen means the next four issues copy something known to
    /// work rather than rediscovering the error message.
    ///
    /// The locale is passed explicitly: CI's simulator is not Russian, and
    /// `String.localizedStringWithFormat` would silently apply English rules.
    func testPluralVariationExampleSelectsRussianForms() {
        let format = Localized.bundle.localizedString(
            forKey: "example.days_count",
            value: nil,
            table: nil
        )
        let rendered = { (count: Int) in
            String(format: format, locale: AppLocale.display, arguments: [count])
        }
        XCTAssertEqual(rendered(1), "1 день")
        XCTAssertEqual(rendered(3), "3 дня")
        XCTAssertEqual(rendered(7), "7 дней")
        XCTAssertEqual(rendered(11), "11 дней")
    }
}
