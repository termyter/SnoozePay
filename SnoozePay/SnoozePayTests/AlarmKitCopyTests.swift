import XCTest
@testable import SnoozePay

/// Pins the copy that the last slice of #598 moved out of `AlarmKitIntents` /
/// `AlarmKitScheduler` and into `Localizable.xcstrings`: the three buttons iOS
/// renders while an alarm rings — on the lock screen, in the Dynamic Island and
/// in a banner.
///
/// These three were the last literals in the Models/Services/Utilities scope
/// and also the loudest copy in the app, and they were invisible to every other
/// test here for a mechanical reason. `AlarmButton(text:)` and `AppIntent.title`
/// take a `LocalizedStringResource`, and a resource built from a string literal
/// uses that literal as its **lookup key**; the lookup misses and hands the
/// literal straight back. So the words rendered correctly while living entirely
/// in Swift — which is exactly the state that ships a Russian lock-screen
/// button to an English user with nothing going red.
///
/// Three layers, so a red run names which one broke:
///
///  1. **Catalogue layer** — the three keys exist and do not resolve to
///     themselves. `Localized.text` echoes an absent key, so a typo'd key would
///     otherwise ship as `alarm_kit.action.stop` on the lock screen.
///  2. **Copy layer** — the words are byte-for-byte the literals that stood on
///     `origin/main` before the move, transcribed here rather than read back
///     out of the file under test. A list derived from the catalogue would
///     agree with any mistake in it.
///  3. **Call-site layer** — `AlarmKitCopy` is invoked, and the
///     `LocalizedStringResource` it hands to AlarmKit is rendered back to a
///     `String`. Layers 1 and 2 cannot see a call site wired to the wrong key,
///     and neither can see a resource that carries a *key* rather than words —
///     which is the whole defect being fixed.
///
/// # What no assertion here reaches
///
/// What the system actually paints on a locked screen. That needs a device with
/// an armed alarm, and this project's tests run on a CI simulator. The layer-3
/// assertions render the resource through the same `Bundle.main` path the
/// system uses, which is as close as a unit test gets; the claim they support
/// is "the resource carries words, not a key", not "the lock screen shows them".
final class AlarmKitCopyTests: XCTestCase {

    /// Transcribed from the literals as they stood on `origin/main` before this
    /// slice — `AlarmKitIntents:54`, `AlarmKitIntents:84` and the interpolated
    /// one at `AlarmKitScheduler:469`.
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

    // MARK: - Layer 3: the call sites are wired to those keys

    func testCopyAccessorsReadAsWordsRatherThanAsKeys() {
        XCTAssertEqual(AlarmKitCopy.stop, "Выключить будильник")
        XCTAssertEqual(AlarmKitCopy.snooze, "Поспать ещё")
        XCTAssertNotEqual(AlarmKitCopy.stop, AlarmKitCopy.stopKey)
        XCTAssertNotEqual(AlarmKitCopy.snooze, AlarmKitCopy.snoozeKey)
    }

    /// Reproduces the pre-migration composition — literal prefix, formatted
    /// sum, closing bracket — from the parts rather than from the new format,
    /// so a change to either side shows up as a difference in words.
    func testPricedSnoozeRendersWhatTheInterpolatedLiteralRendered() {
        for penalty in [50.0, 100.0, 1234.0] {
            let expected = "Поспать ещё (\u{2212}\(MoneyFormatter.string(penalty)))"
            XCTAssertEqual(AlarmKitCopy.pricedSnooze(penalty: penalty), expected)
        }
    }

    /// The defect this slice fixed, asserted directly: a resource whose key is
    /// absent from the catalogue renders as that key. Rendering the three
    /// resources back and finding words means they carry words — which is what
    /// keeps the lock screen from reading `alarm_kit.action.stop` after #596
    /// touches `knownRegions`.
    func testResourcesHandedToAlarmKitCarryWordsAndNotKeys() {
        XCTAssertEqual(String(localized: AlarmKitCopy.stopTitle), AlarmKitCopy.stop)
        XCTAssertEqual(String(localized: AlarmKitCopy.snoozeTitle), AlarmKitCopy.snooze)
        XCTAssertEqual(
            String(localized: AlarmKitCopy.pricedSnoozeTitle(penalty: 50)),
            AlarmKitCopy.pricedSnooze(penalty: 50)
        )
    }

    // MARK: - The three surfaces that say «the same thing» differently

    /// «Поспать ещё» is byte-identical to `firing.action.snooze`, and the two
    /// are separate entries on purpose: that key titles the pre-#472
    /// `UNNotificationCategory` that nothing schedules any more
    /// (`AlarmScheduler.registerCategories`) and will be deleted with it, while
    /// this one is live on every ringing alarm.
    ///
    /// Both values are asserted, so editing either one alone goes red — and the
    /// red run is the notice that the other surface did *not* follow.
    func testTheLockScreenSnoozeKeepsItsOwnKeyDespiteIdenticalWords() {
        XCTAssertNotEqual(AlarmKitCopy.snoozeKey, "firing.action.snooze")
        XCTAssertEqual(Localized.text("firing.action.snooze"), "Поспать ещё")
        XCTAssertEqual(AlarmKitCopy.snooze, "Поспать ещё")
    }

    /// «Stop» is said three different ways on three surfaces, and #723 moved
    /// the strings without picking a winner: merging any pair would rewrite
    /// what a user reads somewhere, which is a copy decision rather than a
    /// migration. The reasoning lives in each entry's `comment`; this pins the
    /// state that reasoning describes, so a silent alignment costs a red run
    /// instead of shipping.
    func testTheThreeWaysTheAppSaysStopStayDistinct() {
        let system = AlarmKitCopy.stop
        let legacyNotification = Localized.text("firing.action.dismiss")
        let inApp = Localized.text("firing.button.dismiss")

        XCTAssertEqual(system, "Выключить будильник")
        XCTAssertEqual(legacyNotification, "Выключить")
        XCTAssertEqual(inApp, "Я встал — выключить")
        XCTAssertEqual(Set([system, legacyNotification, inApp]).count, 3)
    }
}
