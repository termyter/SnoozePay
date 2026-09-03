import XCTest
@testable import SnoozePay

/// Pins the three strings the app hands to AlarmKit and AppIntents for a
/// ringing alarm: the text of the alert's secondary button, and the names of
/// the two intents wired to the alert's actions (which Shortcuts and Siri
/// show). Whether the system also paints the stop intent's name on the alert
/// is not established here — see `AlarmKitCopy`.
///
/// All three were literals in `AlarmKitIntents` / `AlarmKitScheduler`, and they
/// were invisible to every other test here for a mechanical reason.
/// `AlarmButton(text:)` and `AppIntent.title` take a `LocalizedStringResource`,
/// and a resource built from a string literal uses that literal as its **lookup
/// key**; the lookup misses and hands the literal straight back. So the words
/// rendered correctly while living entirely in Swift — which is exactly the
/// state that ships Russian copy to an English user with nothing going red.
///
/// # One of the three moved; two are pinned instead
///
/// The secondary button is an ordinary `AlarmButton`, so it now reads
/// `alarm_kit.action.snooze.priced` at runtime. The two intent titles cannot:
/// AppIntents exports them at build time and `appintentsmetadataprocessor`
/// refuses both a runtime-computed value and any bundle but the main one, which
/// is the one bundle this app's copy is unreachable through while
/// `knownRegions` is `(en, Base)` (#596). `AlarmKitCopy` records the four
/// spellings that were tried and what the processor said to each; #727 tracks
/// the rest.
///
/// So for those two the assertion is weaker and deliberately so: the literal is
/// still what renders, and what is checked is that it has not drifted from the
/// catalogue entry holding the same words. That does not localize the button —
/// it stops the two copies of it from diverging without anyone noticing.
///
/// Layers, so a red run names which one broke:
///
///  1. **Catalogue** — the three keys exist and do not resolve to themselves.
///     `Localized.text` echoes an absent key, so a typo'd key would otherwise
///     ship as `alarm_kit.action.stop`.
///  2. **Copy** — the words are byte-for-byte the literals that stood on
///     `origin/main` before this change, transcribed here rather than read back
///     out of the file under test. A list derived from the catalogue would
///     agree with any mistake in it.
///  3. **Call site** — `AlarmKitCopy` is invoked and the resource it hands to
///     AlarmKit is rendered back to a `String`, and the two intent titles are
///     rendered the same way and compared with the catalogue.
///
/// # What no assertion here reaches
///
/// Where any of it is shown. That needs a device with an armed alarm, and this
/// project's tests run on a CI simulator. The layer-3 assertions render each
/// resource through the same `Bundle.main` path the system uses, so the claim
/// they support is "the resource carries these words", not "this surface
/// shows them" — least of all for the stop intent, whose title may or may not
/// reach the alert at all (see `AlarmKitCopy`).
final class AlarmKitCopyTests: XCTestCase {

    /// Transcribed from the literals as they stood on `origin/main` —
    /// `AlarmKitIntents:54`, `AlarmKitIntents:84` and the interpolated one at
    /// `AlarmKitScheduler:469`.
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

    // MARK: - Layer 3': the two literals AppIntents will not let us move

    /// `StopAlarmIntent.title` and `SnoozeAlarmIntent.title` are still Swift
    /// literals, because `appintentsmetadataprocessor` exports intent titles at
    /// build time and refuses every bundle but the main one — see
    /// `AlarmKitCopy` for the four spellings and its answer to each, and #727.
    ///
    /// This is the strongest assertion available under that constraint: the
    /// catalogue holds the words, and if someone translates or rewords an
    /// entry, this goes red and says the literal did not follow. It does
    /// **not** claim either intent reads the catalogue — neither does.
    func testIntentTitleLiteralsStillAgreeWithTheirCatalogueEntries() throws {
        #if canImport(AppIntents)
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("The AlarmKit intents are gated to iOS 26.")
        }
        XCTAssertEqual(
            String(localized: StopAlarmIntent.title),
            Localized.text(AlarmKitCopy.stopKey),
            "the stop intent's name drifted from alarm_kit.action.stop"
        )
        XCTAssertEqual(
            String(localized: SnoozeAlarmIntent.title),
            Localized.text(AlarmKitCopy.snoozeKey),
            "the snooze intent's name drifted from alarm_kit.action.snooze"
        )
        #else
        throw XCTSkip("AppIntents is unavailable in this build.")
        #endif
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
