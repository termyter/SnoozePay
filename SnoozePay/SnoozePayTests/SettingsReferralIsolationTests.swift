import UIKit
import XCTest
@testable import SnoozePay

/// The Settings screen must reach its stores through injected services,
/// never through their `.shared` instances: `ReferralService` (#690) and
/// `ThemeService` (#700).
///
/// `.shared` is bound to `UserDefaults.standard`, and `getMyCode()` is not a
/// read: it GENERATES a code and persists it on first call. So the moment the
/// «Пригласить друга» section is laid out in the ON position — which the suite
/// does since #676 — the screen writes `referral_my_code` into the real
/// defaults of whoever is running it: the test host, and on device the user.
///
/// Why this is worth a test rather than a one-line fix and no coverage: the
/// leak is invisible today. The write is idempotent, nothing else in the suite
/// reads that key, and CI boots a clean simulator, so the damage is deferred —
/// the first `ReferralService` test that asserts first-run state against
/// `.standard` becomes order-dependent and fails looking like a bug in itself.
/// A regression here would be silent again, so it is pinned by measuring
/// `UserDefaults.standard` directly, before and after.
///
/// Every test that drives the screen asserts BOTH that the injected store
/// received the state and that `UserDefaults.standard` did not move. The two
/// are not equal in strength and it is worth being precise about which does
/// the work: a `UserDefaults(suiteName:)` store is disjoint from `.standard`,
/// so «the injected suite has the code» is the assertion that fails under the
/// old behaviour, on a clean host and on a host that already carries the key
/// alike. «`.standard` is unchanged» is the weaker of the two on its own — it
/// would pass on a host where the key is already present, because
/// `getMyCode()` reads an existing valid code back instead of writing. It is
/// kept because it states the user-visible promise directly (#690 is «tests
/// write into the real user's settings»), and because it is what would catch
/// a future call site that writes to both stores.
///
/// The theme store is the case where only the first kind of assertion can
/// work: showing the segment reads `preferred_theme` and never writes it, so
/// no amount of watching `.standard` catches Settings reading the runner's own
/// theme. `testTheThemeSegmentReadsTheInjectedStore` covers it from the read
/// side instead, and the reasoning for the two seeded suites is on that test.
///
/// One test breaks that pattern and asserts neither half:
/// `testTheDefaultInitializerKeepsTheSharedService` pins the production
/// default, which means evaluating the real `.shared` graph, which writes. It
/// snapshots the keys that graph can move and puts them back — the reasoning
/// is on the test itself.
@MainActor
final class SettingsReferralIsolationTests: XCTestCase {

    /// Keys `ReferralService` owns in whatever `UserDefaults` it is handed.
    /// Spelled out rather than read off the service because they are `private`
    /// there — and because a test that asked the service for its own key names
    /// could not catch the service renaming them out from under a migration.
    private let myCodeKey = "referral_my_code"
    private let appliedCodeKey = "referral_applied_code"
    /// `BalanceService`'s cache of the wallet total. Here because the apply
    /// path spends money, not just referral state.
    private let balanceKey = "user_balance"
    /// `ThemeService`'s preference. Spelled out for the same reason as the
    /// referral keys: it is `private` on the service, and a test that asked
    /// the service for its own key could not notice a rename.
    private let themeKey = "preferred_theme"

    /// Everything in `.standard` that resolving `ReferralService.shared` can
    /// move, directly or through the `BalanceService.shared` it pulls in.
    private var sharedGraphKeys: [String] {
        [myCodeKey, appliedCodeKey, balanceKey, "balance_ledger_opening"]
    }

    /// Name + store for every throwaway suite this case created, so tearDown
    /// can delete the plists it left in the host container.
    private var suites: [(name: String, defaults: UserDefaults)] = []
    private var hostWindows: [UIWindow] = []
    /// Cells are handed out `unowned`-ish by the table; hold them so
    /// `sut.friendCodeInput` (a `weak var`) survives to be asserted on.
    private var retainedCells: [UITableViewCell] = []
    /// Named pasteboards this case created, torn down with the suites. Nothing
    /// in either test target touched `UIPasteboard` before this file, and the
    /// first thing to do so should not be the thing that clobbers the
    /// developer's clipboard.
    private var pasteboardNames: [UIPasteboard.Name] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        retainedCells.removeAll()
        suites.forEach { $0.defaults.removePersistentDomain(forName: $0.name) }
        suites.removeAll()
        pasteboardNames.forEach { UIPasteboard.remove(withName: $0) }
        pasteboardNames.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeSuite(_ label: String) -> UserDefaults {
        let name = "test.settings.referral.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        suites.append((name: name, defaults: defaults))
        return defaults
    }

    /// A private pasteboard, removed in tearDown. Registered on the same line
    /// it is created, so a failure between here and the assertions still frees
    /// it.
    private func makePasteboard() -> UIPasteboard {
        let pasteboard = UIPasteboard.withUniqueName()
        pasteboardNames.append(pasteboard.name)
        return pasteboard
    }

    /// Settings with every store it reads through pinned to `defaults`, laid
    /// out at a real device width with the referral section visible.
    ///
    /// `themeService` joined the list in #700. Its seam is not new — the
    /// parameter has had a `.shared` default since #49 — but this helper went
    /// on letting it fall through, so laying the screen out read
    /// `preferred_theme` out of the runner's own settings and the segment
    /// rendered whatever theme the machine happened to be in.
    ///
    /// «Every store it reads through» is now the literal truth rather than an
    /// approximation, and the whole-domain assertion in the write-side test is
    /// what keeps it that way. The screen does still force three singletons —
    /// `AlarmRepository.shared`, `TransactionRepository.shared` and, as the
    /// latter's default, `WakeEventStore.shared` — through `isRecoveryVisible`.
    /// They are left shared on purpose: `lastLoadFailed` is an in-memory
    /// `Bool` behind a serial queue, and none of the three initializers reads
    /// `UserDefaults`. Four singletons, not three, though — they force
    /// `AlarmScheduler.shared` as `AlarmRepository`'s default scheduler, and
    /// through it `UNUserNotificationCenter.current()` and
    /// `AlarmManager.shared` (`AppDelegate` forces the same one at launch, so
    /// the first touch is normally long before this window), so
    /// «cannot move a key» is NOT claimed for the whole closure: the
    /// whole-domain diff below is what actually holds that line, and it names
    /// the key if one ever moves. A seam for the three would buy nothing here
    /// and would hide that fact behind an injection.
    ///
    /// The wallet comes back with it: the apply path credits 200 ₽, so «where
    /// did the money land» is half of what there is to assert, and the
    /// service is otherwise unreachable from the test once it is inside the
    /// view controller.
    private func laidOutSettings(
        defaults: UserDefaults
    ) -> (sut: SettingsViewController, wallet: BalanceService) {
        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        let sut = SettingsViewController(
            themeService: ThemeService(defaults: defaults),
            alarmDefaults: AlarmDefaults(defaults: defaults),
            referralService: ReferralService(defaults: defaults, balanceService: wallet)
        )
        sut.loadViewIfNeeded()
        sut.referralEnabled = true

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 900))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        window.rootViewController = sut
        window.makeKeyAndVisible()
        hostWindows.append(window)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        sut.tableView.layoutIfNeeded()
        return (sut: sut, wallet: wallet)
    }

    /// Builds one referral row through the real data source. Asked explicitly
    /// rather than left to the layout pass so the test does not depend on the
    /// row happening to be on screen at this window height.
    private func referralCell(
        _ row: SettingsViewController.ReferralRow,
        of sut: SettingsViewController
    ) throws -> UITableViewCell {
        let section = try XCTUnwrap(
            sut.visibleSections.firstIndex(of: .referral),
            "the referral section is not visible — `referralEnabled` did not take"
        )
        let cell = sut.tableView(
            sut.tableView,
            cellForRowAt: IndexPath(row: row.rawValue, section: section)
        )
        retainedCells.append(cell)
        return cell
    }

    private func labelTexts(in view: UIView) -> [String] {
        var found: [String] = []
        for subview in view.subviews {
            if let label = subview as? UILabel, let text = label.text {
                found.append(text)
            }
            found.append(contentsOf: labelTexts(in: subview))
        }
        return found
    }

    // MARK: - The write side

    /// Keys that differ between two `dictionaryRepresentation()` snapshots,
    /// including keys that appeared or disappeared. Values are compared with
    /// `isEqual` rather than `==`: the dictionary is `[String: Any]`, and
    /// every property-list type it can hold is an `NSObject`.
    private static func changedKeys(
        from before: [String: Any],
        to after: [String: Any]
    ) -> [String] {
        Set(before.keys).union(after.keys).filter { key in
            switch (before[key], after[key]) {
            case (nil, nil): return false
            case let (old?, new?): return !(old as AnyObject).isEqual(new)
            default: return true
            }
        }.sorted()
    }

    /// Laying the screen out must not move ANY key in `UserDefaults.standard`,
    /// which is what this test's name has always said and what it now
    /// measures: the whole of `dictionaryRepresentation()`, before and after.
    ///
    /// It used to watch two keys, `referral_my_code` and
    /// `referral_applied_code` — the pair #690 had just stopped leaking. That
    /// is a narrower promise than the name, and the gap was not theoretical:
    /// the theme row read `preferred_theme` straight out of the real defaults
    /// for as long as this file has existed (#700), and a future write to
    /// `stored_alarms` or `user_balance` from this screen would have gone
    /// through green as well.
    ///
    /// The snapshot spans more than the keys SnoozePay owns — the app domain
    /// plus the global and registration domains the process can see. That is
    /// the point: a key this file has never heard of is exactly what it is
    /// hunting. The cost is that a system-owned key moving inside the window
    /// would fail it too. The failure names the key, and if one ever shows up
    /// the fix is to narrow the measurement AND this test's name in the same
    /// commit — narrowing only the measurement is how it got here.
    func testLayingOutTheReferralSectionLeavesStandardDefaultsUntouched() throws {
        let standard = UserDefaults.standard
        let before = standard.dictionaryRepresentation()

        let defaults = makeSuite("write")
        let sut = laidOutSettings(defaults: defaults).sut
        let cell = try referralCell(.myCode, of: sut)

        // Snapshot and verdict both go before the `XCTUnwrap`s below. Taking
        // only the snapshot early is not enough: a throwing unwrap returns from
        // the method, so the assertion this test is NAMED for would be skipped
        // and the run would report a different failure than the one that
        // matters. Nothing but the act sits between the two snapshots.
        let after = standard.dictionaryRepresentation()
        let moved = Self.changedKeys(from: before, to: after)
        XCTAssertTrue(
            moved.isEmpty,
            """
            laying out Settings moved \(moved) in UserDefaults.standard — the real user's settings. \
            A referral or theme key there means a store went back to `.shared`; any other key \
            means the screen grew a write this file does not know about
            """
        )

        let stored = try XCTUnwrap(
            defaults.string(forKey: myCodeKey),
            """
            no `\(myCodeKey)` in the injected store after the section was laid out — \
            either the screen is back on `ReferralService.shared`, or the service \
            renamed the key this test spells out
            """
        )
        XCTAssertEqual(stored.count, 6)
        XCTAssertTrue(
            labelTexts(in: cell).contains(stored),
            "the rendered row shows a code that is not the injected store's"
        )
    }

    // MARK: - The theme store

    /// The theme segment must read its position from the injected
    /// `ThemeService`. Until #700 it read `ThemeService.shared`, i.e.
    /// `preferred_theme` in `.standard`, so the row rendered the theme of
    /// whoever was running the suite — and the write-side test above could
    /// not see it, because showing the segment only reads.
    ///
    /// Two screens, two suites, two different seeded themes. One would not be
    /// enough: `ThemeService.shared` reads a single value, and a screen back
    /// on the singleton would still match a seed that happened to agree with
    /// the host machine. It cannot agree with both `light` and `dark` at
    /// once, so the pair goes red under the old behaviour on any host, without
    /// the segment assertions consulting — let alone writing — what the host
    /// has. (The test does read `preferred_theme` from `.standard` once — that
    /// is the baseline for the third assertion, that laying Settings out did
    /// not write the host's theme. The two index assertions never touch it.)
    ///
    /// The raw values are spelled out rather than taken from
    /// `ThemeService.Theme`, and the expected indices are literals rather than
    /// `themeSegmentIndex` evaluated a second time: the mapping from stored
    /// string to segment position is the thing under test, so it cannot also
    /// be the source of the expectation.
    func testTheThemeSegmentReadsTheInjectedStore() {
        let standard = UserDefaults.standard
        let themeBefore = standard.string(forKey: themeKey)

        let lightStore = makeSuite("theme.light")
        lightStore.set("light", forKey: themeKey)
        let darkStore = makeSuite("theme.dark")
        darkStore.set("dark", forKey: themeKey)

        XCTAssertEqual(
            laidOutSettings(defaults: lightStore).sut.themeSegmentIndex, 1,
            """
            the segment is not on «Светлая» — the screen read the theme from somewhere \
            other than the store it was handed
            """
        )
        XCTAssertEqual(
            laidOutSettings(defaults: darkStore).sut.themeSegmentIndex, 2,
            """
            the segment is not on «Тёмная» — the screen read the theme from somewhere \
            other than the store it was handed
            """
        )

        XCTAssertEqual(
            standard.string(forKey: themeKey), themeBefore,
            "`\(themeKey)` in UserDefaults.standard changed — laying out Settings wrote the user's theme"
        )
    }

    // MARK: - The read side

    /// The friend-input row reads `appliedFriendCode`, and it must read it from
    /// the injected store too: seeded there, the row comes back pre-filled and
    /// frozen. Against `.shared` the seed would be invisible and the row would
    /// render editable and empty.
    func testTheFriendInputRowReadsTheAppliedCodeFromTheInjectedStore() throws {
        let standard = UserDefaults.standard
        let appliedBefore = standard.string(forKey: appliedCodeKey)

        let defaults = makeSuite("read")
        defaults.set("ABCDEF", forKey: appliedCodeKey)

        let sut = laidOutSettings(defaults: defaults).sut
        _ = try referralCell(.friendInput, of: sut)

        let input = try XCTUnwrap(sut.friendCodeInput)
        XCTAssertEqual(
            input.textField.text, "ABCDEF",
            "the row did not see the applied code seeded in the injected store"
        )
        XCTAssertFalse(
            input.textField.isEnabled,
            "an already-redeemed code must freeze the field — the bonus is one-shot"
        )

        XCTAssertEqual(
            standard.string(forKey: appliedCodeKey), appliedBefore,
            "`\(appliedCodeKey)` in UserDefaults.standard changed"
        )
    }

    // MARK: - The other two call sites

    /// `copyMyCodeToPasteboard` is the second `getMyCode()` call site, and
    /// until now nothing in the suite called it — put `ReferralService.shared`
    /// back on that one line and every other test here stays green.
    ///
    /// The copy goes to a pasteboard this test owns, via the same kind of seam
    /// as the service. `UIPasteboard.general` is shared process-wide and, in
    /// the Simulator, synced to the Mac's clipboard by default — asserting
    /// against it would mean this file reproduced #690 against a different
    /// shared store while claiming to close it. An owned pasteboard also lets
    /// the value be read back without the system paste prompt that reading
    /// another writer's `.general` content can raise.
    ///
    /// `.general` is deliberately neither read nor asserted on here: the
    /// production default is pinned separately by the fact that the parameter
    /// has one, and reading it is the part with the side effects.
    func testCopyingTheCodeReadsTheInjectedStore() throws {
        let standard = UserDefaults.standard
        let myCodeBefore = standard.string(forKey: myCodeKey)

        let defaults = makeSuite("copy")
        let sut = laidOutSettings(defaults: defaults).sut
        let pasteboard = makePasteboard()

        sut.copyMyCodeToPasteboard(pasteboard: pasteboard)

        let stored = try XCTUnwrap(defaults.string(forKey: myCodeKey))
        XCTAssertEqual(
            pasteboard.string, stored,
            "the copied code is not the one in the injected store"
        )
        XCTAssertEqual(
            standard.string(forKey: myCodeKey), myCodeBefore,
            "copying the code wrote `\(myCodeKey)` into UserDefaults.standard"
        )
    }

    /// The apply path is the expensive one, and the reason it is pinned even
    /// though no screen test taps «Применить» today: `applyFriendCode` writes
    /// `referral_applied_code` AND credits 200 ₽ through `BalanceService`. On
    /// `.shared` both land in the real user's defaults — a future test that
    /// exercises the button would silently top up `user_balance` on whatever
    /// machine ran it, which is a strictly worse version of #690.
    func testApplyingAFriendCodeWritesOnlyToTheInjectedStores() throws {
        let standard = UserDefaults.standard
        let appliedBefore = standard.string(forKey: appliedCodeKey)
        let balanceBefore = standard.object(forKey: balanceKey) as? Double

        let defaults = makeSuite("apply")
        // Own code fixed rather than generated: `applyFriendCode` rejects a
        // self-apply, and a generated code could collide with the one being
        // applied. Vanishingly unlikely, and free to rule out entirely.
        defaults.set("ABCDEF", forKey: myCodeKey)

        let fixture = laidOutSettings(defaults: defaults)
        _ = try referralCell(.friendInput, of: fixture.sut)
        let input = try XCTUnwrap(fixture.sut.friendCodeInput)
        input.textField.text = "BCDEFG"

        fixture.sut.handleApplyFriendCodeTapped()

        XCTAssertNil(
            input.error,
            "the apply was rejected, so the assertions below would pass for the wrong reason"
        )
        XCTAssertEqual(
            defaults.string(forKey: appliedCodeKey), "BCDEFG",
            "the redeemed code did not land in the injected store"
        )
        XCTAssertEqual(
            fixture.wallet.balance, ReferralService.referralBonusAmount,
            "the bonus did not land in the injected wallet"
        )

        XCTAssertEqual(
            standard.string(forKey: appliedCodeKey), appliedBefore,
            "applying a friend code wrote `\(appliedCodeKey)` into UserDefaults.standard"
        )
        XCTAssertEqual(
            standard.object(forKey: balanceKey) as? Double, balanceBefore,
            "applying a friend code credited real money into `\(balanceKey)` in UserDefaults.standard"
        )
    }

    // MARK: - The default the app ships with

    /// Production still gets the shared instance. Without this, the seam could
    /// be «fixed» by handing every caller its own service — which would give
    /// the app a second referral store and a code that changes per screen.
    ///
    /// This is the one test here that cannot avoid the real `.shared` graph —
    /// pinning the default IS evaluating it — and that graph writes. Resolving
    /// `ReferralService.shared` forces `BalanceService.shared`, whose `init`
    /// ends in `readRawBalance()`, and that path is not a read: it adopts an
    /// opening balance (`balance_ledger_opening`) and rewrites the
    /// `user_balance` cache when the ledger derives a different total. Whether
    /// it fires here depends on who forced the singleton first, which is
    /// exactly the order dependence this file exists to remove.
    ///
    /// So the four keys are captured and PUT BACK rather than asserted
    /// unchanged. An assertion would encode the order dependence instead of
    /// removing it: it would be green only while some alphabetically earlier
    /// test happened to pay for the singleton first, and red the day this class
    /// ran alone. Restoring leaves `.standard` as found in either order, and
    /// the wallet re-derives from the ledger on its next read, so nothing
    /// downstream is left holding a stale cache.
    func testTheDefaultInitializerKeepsTheSharedService() {
        let standard = UserDefaults.standard
        let before = sharedGraphKeys.map { ($0, standard.object(forKey: $0)) }
        defer {
            for (key, value) in before {
                if let value {
                    standard.set(value, forKey: key)
                } else {
                    standard.removeObject(forKey: key)
                }
            }
        }

        XCTAssertTrue(SettingsViewController().referralService === ReferralService.shared)
    }
}
