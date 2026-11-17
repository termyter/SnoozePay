import XCTest
@testable import SnoozePay

/// Real compiled language resources, selected by the same immutable path as
/// production. Literal expectations remain independent of the catalogue.
final class AppLanguageTests: XCTestCase {

    func testCompiledLanguagesAndPreferenceFallback() {
        XCTAssertEqual(Set(Bundle.main.localizations).subtracting(["Base"]), ["en", "ru"])
        for (preferences, expected) in [
            (["ru", "en"], "ru"), (["en", "ru"], "en"),
            (["de", "ru"], "ru"), (["de", "en"], "en"),
            (["ru-RU"], "ru"), (["en-GB"], "en"), (["de"], "en"), ([], "en")
        ] {
            XCTAssertEqual(AppLocale.textLocale(for: preferences).identifier, expected, "\(preferences)")
            let bundle = Localized.localizedBundle(for: preferences)
            XCTAssertEqual(bundle.bundleURL.lastPathComponent, "\(expected).lproj")
            XCTAssertEqual(
                Localized.text("create_alarm.wake_up", in: bundle), expected == "ru" ? "Подъём" : "Wake-up"
            )
        }
    }

    func testBothCompiledNounTablesAndEnglishOptionalForms() {
        let nouns = [
            ("days", "день", "дня", "дней", "day", "days"),
            ("mornings", "утро", "утра", "утр", "morning", "mornings"),
            ("snoozes", "откладывание", "откладывания", "откладываний", "snooze", "snoozes"),
            ("snoozes_after", "откладывания", "откладываний", "откладываний", "snooze", "snoozes")
        ]
        for (language, region) in [("en", "ru_RU"), ("ru", "en_US")] {
            let bundle = Localized.localizedBundle(for: [language])
            let textLocale = AppLocale.textLocale(for: [language])
            XCTAssertNotEqual(textLocale.language.languageCode, Locale(identifier: region).language.languageCode)
            for (noun, ruOne, ruFew, ruMany, enOne, enMany) in nouns {
                let key = "plural.\(noun)"
                let forms = PluralForms(catalogKey: key, bundle: bundle)
                let one = language == "en" ? enOne : ruOne
                let few = language == "en" ? enMany : ruFew
                let many = language == "en" ? enMany : ruMany
                XCTAssertEqual(forms.one, one, key)
                XCTAssertEqual(forms.few, few, key)
                XCTAssertEqual(forms.many, many, key)
                XCTAssertEqual(Plural.word(1, forms, locale: textLocale), one, key)
                XCTAssertEqual(Plural.word(2, forms, locale: textLocale), few, key)
                XCTAssertEqual(Plural.word(21, forms, locale: textLocale), language == "en" ? many : one, key)
                if language == "en" {
                    XCTAssertNil(Localized.optionalText("\(key).few", in: bundle), key)
                }
            }
        }
    }

    func testCompiledPluralVariationsFollowTextEvenOnTheOtherRegion() {
        for (language, region, expected) in [
            ("en", "ru_RU", [
                "Snooze for 1 minute", "Snooze for 2 minutes", "Snooze for 21 minutes", "Snooze for 22 minutes"
            ]),
            ("ru", "en_US", [
                "Отложить на 1 минуту", "Отложить на 2 минуты", "Отложить на 21 минуту", "Отложить на 22 минуты"
            ])
        ] {
            let template = Localized.text(
                "firing.snooze.accessibility", in: Localized.localizedBundle(for: [language])
            )
            for (count, literal) in zip([1, 2, 21, 22], expected) {
                XCTAssertEqual(Localized.formatted(
                    template: template, arguments: [count],
                    textLocale: AppLocale.textLocale(for: [language]), regionalLocale: Locale(identifier: region)
                ), literal)
            }
        }
    }

    func testTextFormattingKeepsRegionalNumberAndLocalePreferences() {
        let english = Locale(identifier: "en")
        let russianRegion = Locale(identifier: "ru_RU@numbers=latn;hours=h23")
        let combined = AppLocale.textFormattingLocale(textLocale: english, regionalLocale: russianRegion)
        XCTAssertEqual(combined.language.languageCode?.identifier, "en")
        XCTAssertEqual(combined.region, russianRegion.region)
        XCTAssertEqual(combined.numberingSystem, russianRegion.numberingSystem)
        XCTAssertEqual(combined.hourCycle, russianRegion.hourCycle)
        XCTAssertEqual(Localized.formatted(
            template: "%.1f", arguments: [2.5], textLocale: english, regionalLocale: russianRegion
        ), "2,5")
        XCTAssertEqual(Localized.formatted(
            template: "%.1f", arguments: [2.5], textLocale: Locale(identifier: "ru"),
            regionalLocale: Locale(identifier: "en_US")
        ), "2.5")
        XCTAssertEqual(StatisticsViewModel.barValueText(2.5, locale: russianRegion), "2,5")
        XCTAssertEqual(WallClockFormatter.string(
            minutesSinceMidnight: 19 * 60 + 5, style: .compact, locale: russianRegion
        ), "19:05")
    }
}
