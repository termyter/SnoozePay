import XCTest
@testable import SnoozePay

/// Guards acknowledge buttons from both sides: no hardcoded title *in the
/// sources*, and no second spelling *in the catalogue*.
///
/// The two halves are here because neither can see the other's defect. A source
/// scan is blind to a call site that correctly reads a key whose *value* is
/// wrong; a catalogue scan is blind to a call site that never opens the
/// catalogue at all. #650 shipped only the second and #664 only the first, and
/// each was believed at the time to close the class.
///
/// # Why the source scan exists at all
///
/// #650 swept `Localizable.xcstrings` with a regex, found no Latin
/// acknowledgement left in it, and declared the class closed. Seven call sites
/// were nevertheless still passing a bare `"OK"` straight to `UIAlertAction`
/// (#664) — they never appear in the catalogue precisely *because* they bypass
/// it, so a catalogue-shaped check is structurally blind to them. The only
/// place that defect is visible is the source line, so that is what the first
/// test reads. The second one, added by #751, reads the catalogue — see
/// `testCatalogueSpellsAcknowledgementInExactlyOnePlace` for the symmetric
/// argument.
///
/// # What counts as a violation
///
/// A `UIAlertAction(title:)` whose title is a string literal that reads as an
/// acknowledgement: `OK`, `Ok`, `ok` in Latin and `ОК`, `Ок`, `ок` in Cyrillic.
/// The two scripts are indistinguishable on screen and equally wrong, so both
/// are matched — the fix for either is the same key, `common.button.ok`.
///
/// A non-acknowledgement literal — a «Отмена», a «Настройки» — is deliberately
/// *not* matched. Those belong to the wider literal migration, and flagging one
/// here would make this test fail for a reason it cannot describe.
///
/// The pair that sentence used to name lived in `AppDelegate` and no longer
/// does: #752 moved both into the catalogue, so at the time of writing the
/// exclusion costs nothing — no `UIAlertAction` in the app passes a literal
/// title at all. It is stated for the next such button, not for a live one.
/// Item 2 below says the same thing about `UIAlertController(title:)`, where
/// there IS still a live case; an earlier revision of this file had the two
/// paragraphs contradicting each other on where the remaining literals are.
///
/// # What it still cannot see
///
/// Naming the remainder is the point — #650 failed by being trusted wider than
/// its reach, and this file can fail the same way.
///
/// 1. **A title routed through a local variable** (`let ok = "OK"; …title: ok`)
///    reads as an identifier at the call site. Accepted: the shape this file
///    exists to stop is the copy-pasted one-liner, which is how all seven
///    arrived.
/// 2. **`UIAlertController(title:)`.** The pattern matches `UIAlertAction`
///    only, so an alert's own title stays invisible here — including the one
///    literal left in `AppDelegate`, «Будильник», which belongs to the wider
///    literal migration. Its neighbour «Уведомления выключены» was the other
///    until #752 moved it, with its body and its two buttons, into the
///    catalogue; `AppDelegateAlertTests` now pins those words.
///
/// The third entry this list carried until #751 — a catalogue key whose own
/// value is Latin — is no longer a blind spot of the *file*, only of the source
/// scan: `testCatalogueSpellsAcknowledgementInExactlyOnePlace` reads the
/// catalogue itself. The live case it was written for was
/// `referral.applied.confirm`, which rendered `"OK"` in the referral «Код
/// применён» alert while every other acknowledge button read «Ок»; #751 deleted
/// the key and pointed that call site at `common.button.ok`.
final class AlertButtonLocalizationTests: XCTestCase {

    /// The catalogue key every acknowledge button has to go through.
    private static let acknowledgeKey = "common.button.ok"

    /// `UIAlertAction(title: "<literal>"` with the whitespace tolerances a
    /// multi-line call site needs. Only a *literal* is captured; a
    /// `Localized.text(…)` argument does not open with a quote and so never
    /// matches.
    private static let literalTitlePattern = #"UIAlertAction\(\s*title:\s*"([^"\n]*)""#

    /// Asserts on the offender *list*, not on a count: the failure message then
    /// names the file and line to fix, which is the whole difference between a
    /// test that stops the eighth literal and a test that merely reports one.
    func testEveryAlertAcknowledgeButtonReadsFromTheCatalogue() throws {
        let sourceRoot = Self.appSourceRoot()
        let regex = try NSRegularExpression(pattern: Self.literalTitlePattern)

        var offenders: [String] = []

        for file in Self.swiftFiles(under: sourceRoot) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)

            for match in regex.matches(in: contents, range: range) {
                guard let literalRange = Range(match.range(at: 1), in: contents) else { continue }
                let literal = String(contents[literalRange])
                guard Self.readsAsAcknowledgement(literal) else { continue }

                let line = Self.lineNumber(of: match.range.location, in: contents)
                let name = file.lastPathComponent
                offenders.append("\(name):\(line) — UIAlertAction(title: \"\(literal)\")")
            }
        }

        XCTAssertEqual(
            offenders, [],
            """
            Alert acknowledge button hardcoded instead of read from the catalogue. \
            Replace the literal with Localized.text("\(Self.acknowledgeKey)"):
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// The complement of the scan: the key the scan pushes everyone towards has
    /// to actually resolve. `Localized.text` echoes an absent key, so a rename
    /// in the catalogue would otherwise leave every call site of it rendering
    /// the key itself as a button title. Deliberately not counting them here:
    /// #664 added eight, the catalogue key had readers before that, and a
    /// number in a comment goes stale on the next alert.
    func testAcknowledgeKeyResolvesToCopyRatherThanTheKey() {
        let copy = Localized.text(Self.acknowledgeKey)

        XCTAssertNotEqual(copy, Self.acknowledgeKey, "\(Self.acknowledgeKey) is missing from the catalogue")
        XCTAssertEqual(copy, "Ок", "The catalogue comment pins this spelling — «Ок», not «ОК» or «OK»")
    }

    /// The catalogue half, and the reason #751 exists.
    ///
    /// The scan above reads call sites, so a call site that properly goes
    /// through `Localized.text(…)` is clean *by construction*, whatever the key
    /// on the other end holds. `referral.applied.confirm` was exactly that: a
    /// second acknowledge key whose ru value was Latin `"OK"`, sitting through
    /// #664's green run while the app rendered «Ок» everywhere else and `"OK"`
    /// there. So this one reads the copy rather than the call sites.
    ///
    /// The expectation is written out as a literal rather than derived from the
    /// catalogue: a set built by filtering the file under test and compared
    /// against itself agrees with every possible version of that file,
    /// including one that has grown a tenth spelling. A new key whose Russian
    /// value reads as an acknowledgement therefore goes red naming that key —
    /// and the fix is to delete it and send its call site to
    /// `common.button.ok`, not to widen this expectation.
    func testCatalogueSpellsAcknowledgementInExactlyOnePlace() throws {
        let acknowledgements = try Self.shippedRussianCopy().filter { Self.readsAsAcknowledgement($0.value) }

        XCTAssertEqual(
            acknowledgements, [Self.acknowledgeKey: "Ок"],
            """
            An acknowledge button lives in the catalogue outside \(Self.acknowledgeKey). \
            Two keys are two spellings on screen: delete the extra entry and point \
            its call site at \(Self.acknowledgeKey).
            """
        )
    }

    // MARK: - Helpers

    /// Every ru key/value pair the built app ships as a plain string, read out
    /// of the compiled `ru.lproj/Localizable.strings`.
    ///
    /// «Plain string» is the limit, and it is narrower than «everything»: plural
    /// and variation entries compile into `Localizable.stringsdict` instead and
    /// are not seen here — 462 of the catalogue's 464 keys reach this table. An
    /// acknowledge button is never a plural, so the guard above is unaffected;
    /// a future check that needs the other two has to read the other file.
    ///
    /// Only `ru` is read, which is the whole catalogue today
    /// (`sourceLanguage: ru`, one localization). Whoever adds the second
    /// language under #569 has to widen this — the guard does not follow them
    /// on its own, and it will not say so.
    ///
    /// The compiled side rather than the source `.xcstrings`, for two reasons:
    /// it is what the app renders — an entry that never reached the build is
    /// not a spelling anyone can see — and it needs no path into the checkout,
    /// which on the simulator exists only through `#filePath`.
    ///
    /// `LocalizableCatalogTests` already pins that this URL resolves; the
    /// unwrap here is so a missing table reads as *this* failure rather than as
    /// an empty scan quietly agreeing with itself.
    private static func shippedRussianCopy() throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "ru.lproj"),
            "ru.lproj/Localizable.strings is missing from the app bundle"
        )
        let data = try Data(contentsOf: url)
        // `xcstringstool` emits an XML plist here, not the old-style text
        // format, so this parses rather than needing a `.strings` reader.
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: String], "ru.lproj/Localizable.strings is not a string table")
    }

    /// `Ок`/`ОК`/`OK`/`ok`… all collapse onto the same two letters. Cyrillic
    /// `О`/`К` are folded onto their Latin twins because the screen cannot tell
    /// them apart either.
    private static func readsAsAcknowledgement(_ literal: String) -> Bool {
        let folded = literal
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "О", with: "O")
            .replacingOccurrences(of: "К", with: "K")
        return folded == "OK"
    }

    /// The app sources of *this* checkout, derived from the compiled-in path of
    /// this file rather than from an absolute path.
    ///
    /// Parallel agents each build from their own worktree, so a hardcoded
    /// `/Users/…` would have every one of them scanning the same foreign clone
    /// — the check would pass while the code under review went unread.
    /// `#filePath` is the worktree the test was compiled from, by construction.
    /// `git rev-parse` is not an option here: this runs on the simulator, where
    /// spawning a subprocess is unavailable.
    private static func appSourceRoot(filePath: StaticString = #filePath) -> URL {
        // <root>/SnoozePay/SnoozePayTests/AlertButtonLocalizationTests.swift
        let thisFile = URL(fileURLWithPath: "\(filePath)")
        let repoRoot = thisFile
            .deletingLastPathComponent()  // SnoozePayTests
            .deletingLastPathComponent()  // SnoozePay (project dir)
            .deletingLastPathComponent()  // repo root
        let sources = repoRoot
            .appendingPathComponent("SnoozePay")
            .appendingPathComponent("SnoozePay")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory)
        // Loud rather than skipped: a scan that silently finds no files is a
        // green light nobody earned.
        XCTAssertTrue(
            exists && isDirectory.boolValue,
            "App sources not found at \(sources.path) — derived from \(thisFile.path)"
        )
        return sources
    }

    private static func swiftFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            XCTFail("Could not enumerate \(root.path)")
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        XCTAssertFalse(files.isEmpty, "No Swift sources under \(root.path) — the scan would pass vacuously")
        return files
    }

    /// Offsets come out of `NSRegularExpression` in UTF-16, so the conversion
    /// has to go through `String.Index(utf16Offset:in:)` — counting `Character`s
    /// would drift on the Cyrillic literals this test exists to find.
    private static func lineNumber(of utf16Offset: Int, in contents: String) -> Int {
        let index = String.Index(utf16Offset: utf16Offset, in: contents)
        return contents[contents.startIndex..<index].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
