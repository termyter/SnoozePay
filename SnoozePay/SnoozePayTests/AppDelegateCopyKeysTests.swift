import Foundation
import XCTest
@testable import SnoozePay

/// Pins the catalogue keys `AppDelegate` reads to the call sites that read
/// them (#791).
///
/// `AppDelegateAlertTests` pins the *words* of the notifications-disabled
/// alert, but by its own copy of each key string — so a typo in the key at the
/// call site left it green: the test kept asking the catalogue about the right
/// key, while the user saw the raw key, which is what `Localized.text` hands
/// back on a miss. The keys here are read off the sources themselves by
/// `CatalogueKeyScanner`, the outside opinion `AlarmEditorCopyTests` already
/// compares its table against (#767), and checked in both directions:
///
///  * every key the sources read resolves in the catalogue — the half this
///    suite exists for, and the one a call-site typo trips;
///  * the table below equals what the sources read — a key the sources stopped
///    reading, or started reading, is named rather than absorbed.
///
/// `SceneDelegate.swift` is deliberately not scanned: it hands nothing to
/// `Localized` today. Listing it would add a file that contributes no keys,
/// and `testEveryAppDelegateSourceIsScanned` is what keeps the next
/// `AppDelegate+….swift` split (the shape #813 took) inside the scan.
@MainActor
final class AppDelegateCopyKeysTests: XCTestCase {

    /// Relative to the app's source root. Both halves of `AppDelegate`: the
    /// alert builders — and every catalogue read — moved to the extension in
    /// #813. The host file reads no key today; it is listed because it holds
    /// the instance entry points, and the corrupt-data message literals there
    /// are copy a later migration may move onto the catalogue.
    private static let sources = ["AppDelegate.swift", "AppDelegate+Alerts.swift"]

    /// The keys those sources read, transcribed rather than derived: a list
    /// computed from the reading would agree with any typo in it. The words
    /// behind them are pinned elsewhere, and each group names where.
    private static let keysTheSourcesRead: Set<String> = [
        // Notifications-disabled alert (#752) — words in
        // `AppDelegateAlertTests.testNotificationsDisabledAlertCopyResolvesToTheShippedWords`.
        "permissions.alert.notifications_disabled.title",
        "permissions.alert.notifications_disabled.message",
        "common.button.cancel",
        "common.button.settings",
        // Corrupt-data alert's only button — spelling owned by
        // `AlertButtonLocalizationTests`.
        "common.button.ok"
    ]

    private static let reading = CatalogueKeyScanner.read(sources, under: appSourceDirectory())

    /// The half #791 was filed for. Walks the reading, not the table: a typo at
    /// the call site puts the misspelled key into the reading and nowhere else,
    /// and that key is exactly the one that must be asked about.
    func testEveryKeyTheSourcesReadIsInTheCatalogue() {
        assertTheScanReadSomething()
        XCTAssertEqual(
            Self.missingFromCatalogue(Self.reading.keys), [],
            "AppDelegate asks the catalogue for keys it does not hold — the user "
                + "sees the raw key where the copy should be"
        )
    }

    func testKeyTableHoldsExactlyTheKeysTheSourcesRead() {
        assertTheScanReadSomething()
        let gaps = Self.coverageGaps(table: Self.keysTheSourcesRead, read: Self.reading.keys)
        XCTAssertEqual(
            gaps.unpinned, [],
            "AppDelegate reads keys this table does not list — add them, and pin "
                + "their words in the suite that owns the screen: \(gaps.unpinned)"
        )
        XCTAssertEqual(
            gaps.stale, [],
            "this table lists keys AppDelegate no longer reads — the expectation "
                + "stands over nothing: \(gaps.stale)"
        )
    }

    /// The assertion `sources` cannot make about itself. #813 split the alerts
    /// out into a new file; a further split holding a new key would sit in
    /// neither the reading nor the table, and both comparisons above would stay
    /// silent about it.
    func testEveryAppDelegateSourceIsScanned() throws {
        let root = Self.appSourceDirectory()
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("AppDelegate") && $0.hasSuffix(".swift") }

        XCTAssertFalse(onDisk.isEmpty, "no AppDelegate sources under \(root.path) — this check would be vacuous")
        XCTAssertEqual(
            Set(onDisk), Set(Self.sources),
            "the AppDelegate sources on disk and the scanned list differ — add the new file to `sources`"
        )
    }

    /// The mutant #791 describes, run on every CI pass rather than once in a PR
    /// nobody re-runs: the real `AppDelegate+Alerts.swift` with two letters of
    /// the title key transposed, every other file of `sources` as it is, pushed
    /// through the same scanner and the same two comparisons as the checks
    /// above.
    func testATypoInTheAlertTitleKeyGoesRed() throws {
        let root = Self.appSourceDirectory()
        let correct = "\"permissions.alert.notifications_disabled.title\""
        let typo = "\"permissions.alert.notifications_disabled.titel\""
        // Over `sources`, not a hand-picked pair: a file added there with keys
        // of its own must not turn this red for a reason it does not name.
        var mutated: Set<String> = []
        var mutatedAFile = false
        for name in Self.sources {
            var text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            if name == "AppDelegate+Alerts.swift" {
                mutatedAFile = text.contains(correct)
                text = text.replacingOccurrences(of: correct, with: typo)
            }
            mutated.formUnion(CatalogueKeyScanner.keys(in: text))
        }
        XCTAssertTrue(
            mutatedAFile,
            "test precondition: the title key is no longer spelled at its call site, so there is nothing to mutate"
        )

        XCTAssertEqual(
            Self.missingFromCatalogue(mutated), ["permissions.alert.notifications_disabled.titel"]
        )
        let gaps = Self.coverageGaps(table: Self.keysTheSourcesRead, read: mutated)
        XCTAssertEqual(gaps.unpinned, ["permissions.alert.notifications_disabled.titel"])
        XCTAssertEqual(gaps.stale, ["permissions.alert.notifications_disabled.title"])
    }

    // MARK: - Helpers

    /// Unreadable sources are a failure, not a file with no keys: a scan that
    /// quietly reads less is the defect this suite closes, moved one level out.
    private func assertTheScanReadSomething(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(
            Self.reading.unreadable, [],
            "listed sources could not be read — renamed or moved, and their keys are outside every check here",
            file: file, line: line
        )
        XCTAssertFalse(
            Self.reading.keys.isEmpty,
            "the scan read no keys at all: the comparisons would be vacuous",
            file: file, line: line
        )
    }

    /// Keys with no catalogue entry, or whose entry is the key itself — both
    /// render the key on screen.
    private static func missingFromCatalogue(_ keys: Set<String>) -> [String] {
        keys.filter { Localized.optionalText($0) == nil || Localized.text($0) == $0 }.sorted()
    }

    private static func coverageGaps(
        table: Set<String>, read: Set<String>
    ) -> (unpinned: [String], stale: [String]) {
        (read.subtracting(table).sorted(), table.subtracting(read).sorted())
    }

    /// `<root>/SnoozePay/SnoozePay`, derived from this file's compiled-in path
    /// — the worktree it was built from — for the reasons
    /// `AlarmEditorCopyTests.alarmSourceDirectory()` spells out.
    private static func appSourceDirectory(filePath: StaticString = #filePath) -> URL {
        // <root>/SnoozePay/SnoozePayTests/AppDelegateCopyKeysTests.swift
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()  // SnoozePayTests
            .deletingLastPathComponent()  // SnoozePay (project dir)
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("SnoozePay/SnoozePay")
    }
}
