import Foundation
import UIKit
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
/// `SceneDelegate.swift` is scanned too since #733 moved the tab bar's three
/// labels onto the catalogue: it is the other file in the target's root, and
/// no screen suite reads it. `testEveryAppDelegateSourceIsScanned` is what
/// keeps the next `AppDelegate+….swift` split (the shape #813 took) inside the
/// scan.
///
/// # Where the words of the #733 keys are pinned
///
/// `rootTargetWords` pins every one of them at the catalogue level. On top of
/// that, most are pinned where the user reads them:
///
///  * the three banners — `AppBannerPostingTests`, off the posted request;
///  * `alarm_failure.corrupted.title` — `AppDelegateAlertTests`, off the
///    presented alert;
///  * the three `tab.*` labels — `testTabBarItemsCarryTheShippedWords` below,
///    off `SceneDelegate.makeMainTabBar()`.
///
/// Two are pinned at the catalogue level **only**, because the call site that
/// builds them is out of reach without raising the whole app:
/// `alarm_failure.corrupted.message` and
/// `alarm_failure.corrupted.message_fallback`. Both are chosen inside
/// `AppDelegate.presentAlarmDataCorruptedAlert(error:)`, a private instance
/// method that walks the live window before presenting.
@MainActor
final class AppDelegateCopyKeysTests: XCTestCase {

    /// Relative to the app's source root. Both halves of `AppDelegate`, plus
    /// `SceneDelegate.swift` (#733). The host file builds the three banners and
    /// the corrupt-data message; the extension, since #813, builds the alerts.
    /// `AppDelegate+NotificationRouting.swift` (#842) reads no key and holds no
    /// copy; it is listed because the on-disk check below wants every
    /// `AppDelegate` source in the scan.
    private static let sources = [
        "AppDelegate.swift", "AppDelegate+Alerts.swift", "AppDelegate+NotificationRouting.swift",
        "SceneDelegate.swift"
    ]

    /// The copy #733 moved out of the target's root files, byte for byte what
    /// the literals it replaced read. Templates are spelled with their
    /// specifiers: an entry edit that drops or doubles one is a red test here,
    /// not a banner missing its number.
    private static let rootTargetWords: [String: String] = [
        "alarm_failure.silent_audio.title": "Будильник звучит беззвучно",
        "alarm_failure.silent_audio.body":
            "Не удалось включить звук — откройте приложение и выключите будильник вручную.",
        "alarm_failure.reschedule.title": "Будильники не перевзведены",
        "alarm_failure.reschedule.body":
            "Не удалось перепланировать будильники (%lld) — "
            + "откройте приложение и проверьте разрешения на уведомления.",
        "alarm_failure.snooze.title": "Откладывание не запланировано",
        "alarm_failure.snooze.body_refunded": "Установите запасной — %@",
        "alarm_failure.snooze.body_charged":
            "Установите запасной. Списание не возвращено — обратитесь в поддержку. %@",
        "alarm_failure.corrupted.title": "Будильник",
        "alarm_failure.corrupted.message":
            "Будильник прозвенел, но его данные повреждены и экран не загрузился. Подробности: %@",
        "alarm_failure.corrupted.message_fallback":
            "Будильник прозвенел, но его данные не удалось загрузить. "
            + "Откройте приложение и проверьте список будильников.",
        "tab.alarms": "Будильники",
        "tab.wallet": "Кошелёк",
        "tab.statistics": "Статистика"
    ]

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
        "common.button.ok",
        // #733 — words in `rootTargetWords` above; the header names which of
        // them are also pinned at the call site.
        "alarm_failure.silent_audio.title",
        "alarm_failure.silent_audio.body",
        "alarm_failure.reschedule.title",
        "alarm_failure.reschedule.body",
        "alarm_failure.snooze.title",
        "alarm_failure.snooze.body_refunded",
        "alarm_failure.snooze.body_charged",
        "alarm_failure.corrupted.title",
        "alarm_failure.corrupted.message",
        "alarm_failure.corrupted.message_fallback",
        "tab.alarms",
        "tab.wallet",
        "tab.statistics"
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

    /// The words of #733, read through the same `Localized.text` the call sites
    /// use. The only pin `alarm_failure.corrupted.message` and its fallback
    /// have — see the header.
    func testRootTargetCopyResolvesToTheShippedWords() {
        for (key, words) in Self.rootTargetWords.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(Localized.text(key), words, "catalogue entry \(key)")
        }
        XCTAssertEqual(
            Set(Self.rootTargetWords.keys).subtracting(Self.keysTheSourcesRead), [],
            "the words table pins keys the key table does not list"
        )
    }

    /// The tab labels at their call site: the three items `makeMainTabBar`
    /// builds, in the order the bar shows them.
    func testTabBarItemsCarryTheShippedWords() throws {
        let tabBarController = try XCTUnwrap(SceneDelegate.makeMainTabBar() as? UITabBarController)
        let titles = try XCTUnwrap(tabBarController.viewControllers).map(\.tabBarItem.title)
        XCTAssertEqual(titles, ["Будильники", "Кошелёк", "Статистика"])
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
            Set(onDisk), Set(Self.sources.filter { $0.hasPrefix("AppDelegate") }),
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
