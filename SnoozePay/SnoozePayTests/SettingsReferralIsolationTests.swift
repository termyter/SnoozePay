import UIKit
import XCTest
@testable import SnoozePay

/// The Settings screen must reach referral state through an injected
/// `ReferralService`, never through `ReferralService.shared` (#690).
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
/// The pair of assertions in `testLayingOutTheReferralSection...` is
/// deliberate and neither half stands alone:
///
///   * «standard is unchanged» alone passes on a host that ALREADY has
///     `referral_my_code` — the buggy code would read the existing value back
///     and write nothing.
///   * «the injected suite got the code» alone passes on a host where the
///     screen wrote to both.
///
/// Together they say the code came from, and went to, the injected store.
@MainActor
final class SettingsReferralIsolationTests: XCTestCase {

    /// Keys `ReferralService` owns in whatever `UserDefaults` it is handed.
    /// Spelled out rather than read off the service because they are `private`
    /// there — and because a test that asked the service for its own key names
    /// could not catch the service renaming them out from under a migration.
    private let myCodeKey = "referral_my_code"
    private let appliedCodeKey = "referral_applied_code"

    /// Name + store for every throwaway suite this case created, so tearDown
    /// can delete the plists it left in the host container.
    private var suites: [(name: String, defaults: UserDefaults)] = []
    private var hostWindows: [UIWindow] = []
    /// Cells are handed out `unowned`-ish by the table; hold them so
    /// `sut.friendCodeInput` (a `weak var`) survives to be asserted on.
    private var retainedCells: [UITableViewCell] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        retainedCells.removeAll()
        suites.forEach { $0.defaults.removePersistentDomain(forName: $0.name) }
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeSuite(_ label: String) -> UserDefaults {
        let name = "test.settings.referral.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        suites.append((name: name, defaults: defaults))
        return defaults
    }

    /// Settings with every store it touches pinned to `defaults`, laid out at a
    /// real device width with the referral section visible.
    private func laidOutSettings(defaults: UserDefaults) -> SettingsViewController {
        let sut = SettingsViewController(
            alarmDefaults: AlarmDefaults(defaults: defaults),
            referralService: ReferralService(
                defaults: defaults,
                balanceService: BalanceService(
                    defaults: defaults,
                    notificationCenter: NotificationCenter()
                )
            )
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
        return sut
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

    func testLayingOutTheReferralSectionLeavesStandardDefaultsUntouched() throws {
        let standard = UserDefaults.standard
        let myCodeBefore = standard.string(forKey: myCodeKey)
        let appliedBefore = standard.string(forKey: appliedCodeKey)

        let defaults = makeSuite("write")
        let sut = laidOutSettings(defaults: defaults)
        let cell = try referralCell(.myCode, of: sut)

        let stored = try XCTUnwrap(
            defaults.string(forKey: myCodeKey),
            "the screen generated no code in the injected store — it is still reading `.shared`"
        )
        XCTAssertEqual(stored.count, 6)
        XCTAssertTrue(
            labelTexts(in: cell).contains(stored),
            "the rendered row shows a code that is not the injected store's"
        )

        XCTAssertEqual(
            standard.string(forKey: myCodeKey), myCodeBefore,
            "`\(myCodeKey)` in UserDefaults.standard changed — Settings still writes to the real user's defaults"
        )
        XCTAssertEqual(
            standard.string(forKey: appliedCodeKey), appliedBefore,
            "`\(appliedCodeKey)` in UserDefaults.standard changed"
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

        let sut = laidOutSettings(defaults: defaults)
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

    // MARK: - The default the app ships with

    /// Production still gets the shared instance. Without this, the seam could
    /// be «fixed» by handing every caller its own service — which would give
    /// the app a second referral store and a code that changes per screen.
    func testTheDefaultInitializerKeepsTheSharedService() {
        XCTAssertTrue(SettingsViewController().referralService === ReferralService.shared)
    }
}
