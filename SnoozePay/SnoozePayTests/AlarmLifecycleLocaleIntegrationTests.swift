import XCTest
@testable import SnoozePay

/// Combined resource/formatter evidence, without changing process language or stores.
final class AlarmLifecycleLocaleIntegrationTests: XCTestCase {
    func testBothSelectedLanguagesReachEveryFullCandidateResource() throws {
        let russian = Localized.localizedBundle(for: ["ru"])
        let english = Localized.localizedBundle(for: ["en"])
        XCTAssertEqual(russian.bundleURL.lastPathComponent, "ru.lproj")
        XCTAssertEqual(english.bundleURL.lastPathComponent, "en.lproj")
        let russianKeys = try compiledKeys(in: russian)
        let englishKeys = try compiledKeys(in: english)
        let optionalEnglishFew: Set<String> = [
            "plural.days.few", "plural.mornings.few",
            "plural.snoozes.few", "plural.snoozes_after.few"
        ]
        XCTAssertEqual(russianKeys.count, 505, "Keep the complete frozen full-candidate resource set")
        XCTAssertTrue(optionalEnglishFew.isSubset(of: russianKeys))
        XCTAssertEqual(englishKeys, russianKeys.subtracting(optionalEnglishFew))
        for (language, bundle) in [("ru", russian), ("en", english)] {
            for key in russianKeys.sorted() {
                let text = Localized.optionalText(key, in: bundle)
                if language == "en", optionalEnglishFew.contains(key) {
                    XCTAssertNil(text, "Optional EN few must not fall through to Russian: \(key)")
                    continue
                }
                let resolved = try XCTUnwrap(text, "\(language) selector lost \(key)")
                XCTAssertNotEqual(resolved, key, "\(language) key echo: \(key)")
                XCTAssertFalse(resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                if language == "en" {
                    XCTAssertNil(resolved.range(of: #"\p{Script=Cyrillic}"#, options: .regularExpression), key)
                }
            }
        }
    }

    func testCombinedFinishRecoveryAndPhotoCopyUsesTheSelectedCompiledLanguage() {
        let copy = [
            ("firing.finish.recovery.title", "Незавершённая попытка", "Pending finish"),
            ("firing.finish.recovery.retry", "Повторить завершение", "Confirm Pending Finish"),
            ("settings.recovery.alarms_failed_title",
             "Восстановление будильников не завершено", "Alarm Recovery Incomplete"),
            ("create_alarm.theme_picker.error.title", "Не удалось сохранить фото", "Couldn’t Save Photo"),
            ("create_alarm.theme_picker.error.message",
             "Попробуйте выбрать другое изображение.", "Try choosing a different image.")
        ]
        for language in ["ru", "en"] {
            let bundle = Localized.localizedBundle(for: ["de", language])
            XCTAssertEqual(bundle.bundleURL.lastPathComponent, "\(language).lproj")
            for (key, russian, english) in copy {
                XCTAssertEqual(Localized.text(key, in: bundle), language == "ru" ? russian : english, key)
            }
        }
    }

    func testDecodedCivilAndLegacyClocksKeepAuthorityAcrossTextAndRegionSelections() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let rawFourUTC = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 4)))
        let clock = try XCTUnwrap(TimeOfDay(hour: 7, minute: 4))
        let civil = Alarm(time: rawFourUTC, clockTime: clock, name: "Locale civil")
        let legacy = Alarm(time: rawFourUTC, name: "Locale legacy")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode([civil, legacy])
        let decoded = try JSONDecoder().decode([Alarm].self, from: bytes)
        let loadedCivil = try XCTUnwrap(decoded.first { $0.id == civil.id })
        let loadedLegacy = try XCTUnwrap(decoded.first { $0.id == legacy.id })
        let scenarios = [
            ("en", "ru_RU@hours=h23", "Wake-up", "7:04", "7:00", "5:00"),
            ("ru", "en_US@hours=h12", "Подъём", "7:04 AM", "7:00 AM", "5:00 AM")
        ]
        for (language, region, wake, civilTime, legacyAtThree, legacyAtOne) in scenarios {
            let bundle = Localized.localizedBundle(for: ["de", language])
            XCTAssertEqual(Localized.text("create_alarm.wake_up", in: bundle), wake)
            XCTAssertEqual(AppLocale.textLocale(for: ["de", language]).language.languageCode?.identifier, language)
            let regional = Locale(identifier: region)
            for (offset, legacyTime) in [(3, legacyAtThree), (1, legacyAtOne)] {
                var reader = utc
                reader.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: offset * 3600))
                XCTAssertEqual(normalizedClock(loadedCivil, locale: regional, calendar: reader), civilTime)
                XCTAssertEqual(normalizedClock(loadedLegacy, locale: regional, calendar: reader), legacyTime)
            }
        }
        XCTAssertEqual(loadedCivil.clockTime, clock)
        XCTAssertNil(loadedLegacy.clockTime)
        XCTAssertEqual(loadedCivil.time, rawFourUTC)
        XCTAssertEqual(loadedLegacy.time, rawFourUTC)
        XCTAssertEqual(try encoder.encode(decoded), bytes,
                       "Display selection must not migrate persisted clock authority")
    }

    func testUnpricedSnoozeResourceNeverInventsWalletCurrency() {
        for penalty in [50.0, 0.001] {
            XCTAssertEqual(AlarmKitCopy.pricedSnooze(penalty: penalty, currency: nil), "Поспать ещё")
            XCTAssertEqual(
                String(localized: AlarmKitCopy.pricedSnoozeTitle(penalty: penalty, currency: nil)),
                "Поспать ещё"
            )
        }
    }

    private func compiledKeys(in bundle: Bundle) throws -> Set<String> {
        let stringsURL = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let strings = try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])
        var keys = Set(strings.keys)
        if let pluralsURL = bundle.url(forResource: "Localizable", withExtension: "stringsdict") {
            let plurals = try XCTUnwrap(NSDictionary(contentsOf: pluralsURL) as? [String: Any])
            keys.formUnion(plurals.keys)
        }
        return keys
    }

    private func normalizedClock(_ alarm: Alarm, locale: Locale, calendar: Calendar) -> String {
        WallClockFormatter.string(from: alarm, style: .compact, locale: locale, calendar: calendar)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
