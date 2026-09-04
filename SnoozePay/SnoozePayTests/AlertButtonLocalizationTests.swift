import XCTest
@testable import SnoozePay

/// Guards acknowledge buttons against a hardcoded title *in the sources*.
///
/// Not "every `UIAlertController`" — the scan reads source lines, so it sees
/// exactly the defects that are visible there. Its three blind spots are listed
/// below, and one of them is currently occupied.
///
/// # Why this scans sources instead of the catalogue
///
/// #650 swept `Localizable.xcstrings` with a regex, found no Latin
/// acknowledgement left in it, and declared the class closed. Seven call sites
/// were nevertheless still passing a bare `"OK"` straight to `UIAlertAction`
/// (#664) — they never appear in the catalogue precisely *because* they bypass
/// it, so a catalogue-shaped check is structurally blind to them. The only
/// place the defect is visible is the source line, so that is what this reads.
///
/// # What counts as a violation
///
/// A `UIAlertAction(title:)` whose title is a string literal that reads as an
/// acknowledgement: `OK`, `Ok`, `ok` in Latin and `ОК`, `Ок`, `ок` in Cyrillic.
/// The two scripts are indistinguishable on screen and equally wrong, so both
/// are matched — the fix for either is the same key, `common.button.ok`.
///
/// Non-acknowledgement literals (`"Отмена"`, `"Настройки"` in `AppDelegate`)
/// are deliberately *not* matched. They belong to the wider literal migration
/// and flagging them here would make this test fail for a reason it cannot
/// describe.
///
/// # What it cannot see
///
/// Three things, and naming them is the point — #650 failed by being trusted
/// wider than its reach, and this test can fail the same way.
///
/// 1. **A title routed through a local variable** (`let ok = "OK"; …title: ok`)
///    reads as an identifier at the call site. Accepted: the shape this file
///    exists to stop is the copy-pasted one-liner, which is how all seven
///    arrived.
/// 2. **A catalogue key whose own value is Latin.** There is a live one:
///    `referral.applied.confirm` renders `"OK"`, so the app reads «Ок»
///    everywhere `common.button.ok` is used and «OK» in that one alert. The
///    call site is
///    `Localized.text(…)`, i.e. not a literal, so this scan is *structurally*
///    blind to it. Tracked in #751.
/// 3. **`UIAlertController(title:)`.** The pattern matches `UIAlertAction`
///    only, so an alert's own title stays invisible here — including the two
///    literal ones left in `AppDelegate`: «Уведомления выключены» is tracked in
///    #752, «Будильник» belongs to the wider literal migration.
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

    // MARK: - Helpers

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
