import XCTest
@testable import SnoozePay

/// Guards the three strings handed to AlarmKit and AppIntents: the priced
/// secondary-button label, and the two intent names shown in Shortcuts/Siri.
/// Intent metadata uses static catalogue keys in the main bundle; each actual
/// title resource is rendered in RU and EN so a missing key cannot pass by
/// echoing its spelling. The priced button is resolved at schedule time using
/// the app's language and is a separate surface from the intent's name.
///
/// These tests cover resources and copy, not system presentation. An armed
/// alarm and physical Shortcuts/Siri checks remain #727 acceptance; changing
/// an intent title does not configure the system-owned stop-button label.
final class AlarmKitCopyTests: XCTestCase {

    /// Transcribed from the literals as they stood on `origin/main` —
    /// `StopAlarmIntent.title`, `SnoozeAlarmIntent.title` and the snooze
    /// button title `AlarmKitScheduler.makePresentation(for:)` used to
    /// interpolate (now `AlarmKitCopy.pricedSnoozeTitle(penalty:)`).
    private static let copy: [String: String] = [
        "alarm_kit.action.stop": "Выключить будильник",
        "alarm_kit.action.snooze": "Поспать ещё",
        "alarm_kit.action.snooze.priced": "Поспать ещё (−%@)"
    ]

    // MARK: - Layer 1: the catalogue

    func testEveryMigratedKeyResolvesToCopyRatherThanToItself() {
        for key in Self.copy.keys.sorted() {
            XCTAssertNotNil(Localized.optionalText(key), "missing catalogue key: \(key)")
            XCTAssertNotEqual(
                Localized.text(key), key,
                "\(key) resolves to itself — the entry is absent or holds the key as its value"
            )
        }
    }

    // MARK: - Layer 2: the words did not change

    func testMigratedCopyStillReadsTheWayItDidBefore() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for \(key)")
        }
    }

    /// The price is substituted, not concatenated, so the specifier is part of
    /// the copy and a translator can move it. `%@` and nothing else: the sum
    /// arrives already formatted by `MoneyFormatter`, so `%lld` here would
    /// render a pointer-sized integer instead of «50 ₽».
    func testPricedSnoozeKeepsExactlyOnePercentAtSpecifier() {
        let format = Localized.text(AlarmKitCopy.pricedSnoozeKey)
        XCTAssertEqual(format.components(separatedBy: "%").count - 1, 1, "expected exactly one specifier")
        XCTAssertTrue(format.contains("%@"), "the sum is pre-formatted text, so the specifier must be %@")
    }

    /// The sign in front of the sum is U+2212 MINUS SIGN, the same glyph the
    /// design system uses everywhere else for a debit. A hyphen-minus looks
    /// almost identical in a diff and noticeably worse next to mono digits.
    func testPricedSnoozeUsesTheMinusSignRatherThanAHyphen() {
        let format = Localized.text(AlarmKitCopy.pricedSnoozeKey)
        XCTAssertTrue(format.contains("\u{2212}"), "expected U+2212 MINUS SIGN")
        XCTAssertFalse(format.contains("-"), "hyphen-minus crept into the price format")
    }

    // MARK: - Layer 3: the secondary button, which does read the catalogue

    /// Reproduces the pre-migration composition — literal prefix, formatted
    /// sum, closing bracket — from the parts rather than from the new format,
    /// so a change to either side shows up as a difference in words.
    func testPricedSnoozeRendersWhatTheInterpolatedLiteralRendered() {
        for penalty in [50.0, 100.0, 1234.0] {
            let expected = "Поспать ещё (\u{2212}\(MoneyFormatter.string(penalty)))"
            XCTAssertEqual(AlarmKitCopy.pricedSnooze(penalty: penalty), expected)
        }
    }

    /// The defect this change fixed on the one surface it could, asserted
    /// directly: a resource whose key is absent from the catalogue renders as
    /// that key. Rendering it back and finding words means it carries words.
    func testTheSecondaryButtonResourceCarriesWordsAndNotAKey() {
        XCTAssertEqual(
            String(localized: AlarmKitCopy.pricedSnoozeTitle(penalty: 50)),
            AlarmKitCopy.pricedSnooze(penalty: 50)
        )
        XCTAssertFalse(
            String(localized: AlarmKitCopy.pricedSnoozeTitle(penalty: 50))
                .contains(AlarmKitCopy.pricedSnoozeKey)
        )
    }

    func testPricedSnoozeQuotesActualCurrencyAndNeverAdvertisesSubminorAsZero() throws {
        for code in ["RUB", "USD", "EUR", "JPY", "KWD"] {
            let currency = try XCTUnwrap(Currency(code: code))
            for penalty in [50.0, 1.25, 0.001] {
                let quote = MoneyFormatter.quotedString(penalty, currency: currency) ?? "—"
                let expected = "Поспать ещё (−\(quote))"
                XCTAssertEqual(AlarmKitCopy.pricedSnooze(penalty: penalty, currency: currency), expected)
                XCTAssertEqual(String(localized: AlarmKitCopy.pricedSnoozeTitle(
                    penalty: penalty, currency: currency
                )), expected)
                if code != "RUB" { XCTAssertFalse(expected.contains("₽")) }
            }
        }
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertEqual(AlarmKitCopy.pricedSnooze(penalty: 0.001, currency: usd), "Поспать ещё (−—)")
    }

    // MARK: - Layer 4: exported intent resources in both languages

    func testIntentTitlesResolveMainBundleCatalogueInRussianAndEnglish() throws {
        #if canImport(AppIntents)
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("The AlarmKit intents are gated to iOS 26.")
        }
        assertIntentTitle(
            StopAlarmIntent.title, key: "alarm_kit.action.stop",
            russian: "Выключить будильник", english: "Turn Off Alarm"
        )
        assertIntentTitle(
            SnoozeAlarmIntent.title, key: "alarm_kit.action.snooze",
            russian: "Поспать ещё", english: "Snooze"
        )
        #else
        throw XCTSkip("AppIntents is unavailable in this build.")
        #endif
    }

    private func assertIntentTitle(
        _ title: LocalizedStringResource, key: String, russian: String, english: String
    ) {
        XCTAssertEqual(title.key, key, "AppIntents must export the symbolic catalogue key")
        XCTAssertEqual(title.table, "Localizable")
        // `bundle` is a computed description, not the initializer's stored
        // enum case. A main-bundle resource can be returned as its file URL.
        // Check the destination, retaining rejection of any foreign bundle.
        switch title.bundle {
        case .main:
            break
        case .atURL(let url):
            XCTAssertEqual(
                url.standardizedFileURL, Bundle.main.bundleURL.standardizedFileURL,
                "AppIntents requires a main-bundle title resource: \(key)"
            )
        case .forClass(let type):
            XCTFail("Unexpected class-bundle title resource for \(key): \(type)")
        @unknown default:
            XCTFail("Unknown title resource bundle for \(key): \(title.bundle)")
        }
        for (identifier, expected) in [("ru_RU", russian), ("en_US", english)] {
            // Mutate a copy: resolving Siri's locale must not pin the static
            // metadata to the app's language or modify it for another caller.
            var localizedTitle = title
            localizedTitle.locale = Locale(identifier: identifier)
            let rendered = String(localized: localizedTitle)
            XCTAssertEqual(rendered, expected, "\(key) in \(identifier)")
            XCTAssertNotEqual(rendered, key, "missing compiled catalogue entry: \(key)")
        }
    }

    /// The priced secondary button uses a separate entry from the bare intent
    /// name in both languages. The preformatted amount keeps its own currency;
    /// translating the button does not convert a rouble charge into dollars.
    func testPricedButtonCatalogueKeepsTheAmountInBothLanguages() {
        for (identifier, expected) in [
            ("ru_RU", "Поспать ещё (−50 ₽)"),
            ("en_US", "Snooze (−50 ₽)")
        ] {
            let locale = Locale(identifier: identifier)
            let format = String(localized: LocalizedStringResource(
                "alarm_kit.action.snooze.priced", table: "Localizable", locale: locale
            ))
            XCTAssertNotEqual(format, AlarmKitCopy.pricedSnoozeKey)
            XCTAssertEqual(String(format: format, locale: locale, arguments: ["50 ₽"]), expected)
        }
        XCTAssertNotEqual(AlarmKitCopy.pricedSnoozeKey, AlarmKitCopy.snoozeKey)
    }

    // MARK: - The keys that hold the same words on purpose

    /// «Поспать ещё» is byte-identical to `firing.action.snooze`, and the two
    /// are separate entries on purpose — but not for the reason an earlier
    /// draft of this file gave, which was that one of them is live on a ringing
    /// alarm. It is not: the alert's snooze button reads
    /// ``AlarmKitCopy/pricedSnoozeKey``, and ``AlarmKitCopy/snoozeKey`` is the
    /// intent's name in Shortcuts.
    ///
    /// The reason they stay apart is that `firing.action.snooze` titles the
    /// pre-#472 `UNNotificationCategory` that nothing schedules any more
    /// (`AlarmScheduler.registerCategories`) and is expected to be deleted with
    /// it. One key for both would make that deletion take a live Shortcuts name
    /// with it — a change whose blast radius is invisible from where it is
    /// made. Since the words are identical either way, no user sees a
    /// difference; this is a namespace choice, not a copy one.
    ///
    /// Both values are asserted, so editing either one alone goes red — and the
    /// red run is the notice that the other did *not* follow.
    func testTheSnoozeIntentNameKeepsItsOwnKeyDespiteIdenticalWords() {
        XCTAssertNotEqual(AlarmKitCopy.snoozeKey, "firing.action.snooze")
        XCTAssertEqual(Localized.text("firing.action.snooze"), "Поспать ещё")
        XCTAssertEqual(Localized.text(AlarmKitCopy.snoozeKey), "Поспать ещё")
    }

    /// «Stop» is said three different ways in three places, and this change
    /// moved strings without picking a winner: merging any pair would rewrite
    /// what a user reads somewhere, which is a copy decision rather than a
    /// migration. #712's criterion for merging — the two literals were
    /// byte-identical — does not reach these, because they are not. The
    /// reasoning lives in each entry's `comment`; this pins the state that
    /// reasoning describes, so a silent alignment costs a red run instead of
    /// shipping.
    func testTheThreeWaysTheAppSaysStopStayDistinct() {
        let system = Localized.text(AlarmKitCopy.stopKey)
        let legacyNotification = Localized.text("firing.action.dismiss")
        let inApp = Localized.text("firing.button.dismiss")

        XCTAssertEqual(system, "Выключить будильник")
        XCTAssertEqual(legacyNotification, "Выключить")
        XCTAssertEqual(inApp, "Я встал — выключить")
        XCTAssertEqual(Set([system, legacyNotification, inApp]).count, 3)
    }
}
