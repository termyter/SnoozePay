import UIKit
import XCTest
@testable import SnoozePay

/// Every way INTO the referral programme is gated on
/// `AppFeatureFlags.referralEnabled`, which ships `false` (#676): the code a
/// user copies resolves nowhere and the bonus is credited from the local
/// wallet, so the screen promises a payout that does not exist.
///
/// Two things are asserted separately here, and the distinction is the point:
///
///   1. **Both positions of the flag**, through the pure helpers. A test that
///      only checked the shipped value would pass just as happily against a
///      section that had been deleted outright — and would tell us nothing
///      about whether flipping the flag back actually restores anything.
///   2. **The live wiring**, expressed against `AppFeatureFlags.referralEnabled`
///      rather than a hardcoded `0`. That keeps this suite green through the
///      one-line flip we expect to make once a backend exists, while still
///      failing if the table stops consulting the flag at all.
///
/// What is deliberately NOT asserted: that the flag is currently `false`.
/// That is a PM decision, not an invariant, and pinning it would turn the
/// intended one-line re-enable into a two-line one.
@MainActor
final class ReferralEntryPointVisibilityTests: XCTestCase {

    private func makeSettings() -> SettingsViewController {
        let suite = "test.referral.visibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let sut = SettingsViewController(alarmDefaults: AlarmDefaults(defaults: defaults))
        sut.loadViewIfNeeded()
        return sut
    }

    private var referralSection: Int { SettingsViewController.Section.referral.rawValue }

    // MARK: - Settings section, both flag positions

    func testReferralSectionHasNoRowsWhenTheFlagIsOff() {
        XCTAssertEqual(SettingsViewController.referralRowCount(referralEnabled: false), 0)
    }

    /// Turning the flag back on must return the whole section, not a subset —
    /// this is what makes the hide reversible rather than a slow deletion.
    func testReferralSectionReturnsEveryRowWhenTheFlagIsOn() {
        XCTAssertEqual(
            SettingsViewController.referralRowCount(referralEnabled: true),
            SettingsViewController.ReferralRow.allCases.count
        )
        XCTAssertEqual(SettingsViewController.ReferralRow.allCases.count, 3)
    }

    /// A hidden section must not leave its caps header behind: the header is
    /// what a user would read as "the feature is here", and an empty
    /// «ПРИГЛАСИТЬ ДРУГА» would be worse than the section itself.
    func testReferralHeaderDisappearsWithTheSection() {
        XCTAssertNil(SettingsViewController.referralSectionTitle(referralEnabled: false))
        XCTAssertEqual(
            SettingsViewController.referralSectionTitle(referralEnabled: true),
            "ПРИГЛАСИТЬ ДРУГА"
        )
    }

    // MARK: - Live table follows the flag

    func testSettingsTableRowCountFollowsTheFlag() {
        let sut = makeSettings()
        XCTAssertEqual(
            sut.tableView(sut.tableView, numberOfRowsInSection: referralSection),
            SettingsViewController.referralRowCount(referralEnabled: AppFeatureFlags.referralEnabled),
            "the data source stopped consulting AppFeatureFlags.referralEnabled"
        )
    }

    func testSettingsTableHeaderFollowsTheFlag() {
        let sut = makeSettings()
        XCTAssertEqual(
            sut.tableView(sut.tableView, titleForHeaderInSection: referralSection),
            SettingsViewController.referralSectionTitle(referralEnabled: AppFeatureFlags.referralEnabled)
        )
        // No title → no header view and no header height, so the hidden
        // section cannot show up as a bare gap with a divider.
        if !AppFeatureFlags.referralEnabled {
            XCTAssertNil(sut.tableView(sut.tableView, viewForHeaderInSection: referralSection))
            XCTAssertEqual(
                sut.tableView(sut.tableView, heightForHeaderInSection: referralSection),
                CGFloat.leastNonzeroMagnitude
            )
        }
    }

    /// The grouped footer gap is the other half of "hidden": `.referral` sits
    /// between «ПРАВИЛА» and «ПРОЧЕЕ», so a section that renders nothing but
    /// still reserves its footer reads as a double break in the middle of the
    /// form. `.diagnostics` never exposed this because it sits last.
    func testHiddenSectionReservesNoFooterGap() throws {
        let sut = makeSettings()
        try XCTSkipIf(AppFeatureFlags.referralEnabled, "nothing is hidden while the flag is on")

        XCTAssertEqual(
            sut.tableView(sut.tableView, heightForFooterInSection: referralSection),
            CGFloat.leastNonzeroMagnitude
        )
    }

    /// …and sections that do render keep the system spacing, so collapsing the
    /// empty one is not paid for by flattening the whole form.
    func testRenderedSectionsKeepTheSystemFooterGap() {
        let sut = makeSettings()
        for section in [SettingsViewController.Section.finance, .rules, .other] {
            XCTAssertEqual(
                sut.tableView(sut.tableView, heightForFooterInSection: section.rawValue),
                UITableView.automaticDimension,
                "\(section) lost its footer spacing"
            )
        }
    }

    // MARK: - The DEBUG shortcut on Statistics

    #if DEBUG
    /// The stats DEBUG row is the only other door into `ReferralViewController`.
    /// If it stayed wired, "hidden" would depend on which configuration you
    /// happen to be running — which is exactly the kind of half-hidden state
    /// this issue is removing.
    func testStatisticsDebugShortcutFollowsTheFlag() throws {
        let row = StatisticsViewController().makeDebugButtonsRow()
        let stack = try XCTUnwrap(row as? UIStackView)
        let labels = stack.arrangedSubviews.compactMap { $0.accessibilityLabel }

        XCTAssertEqual(
            labels.contains("Реферальная программа"),
            AppFeatureFlags.referralEnabled,
            "debug shortcut visibility diverged from the flag; labels: \(labels)"
        )
        // The neighbouring shortcuts are untouched — the gate is one button,
        // not the whole DEBUG row.
        XCTAssertTrue(labels.contains("Streak modal"), "labels: \(labels)")
        XCTAssertTrue(labels.contains("AlarmOff warning"), "labels: \(labels)")
    }
    #endif

    // MARK: - Hidden, not removed

    /// The cells behind the section are still registered on the table, so the
    /// section is dormant rather than dismantled. Together with the untouched
    /// `Referral*Tests` suites this is what separates #676 from a deletion.
    func testReferralCellsRemainRegistered() {
        let sut = makeSettings()
        XCTAssertNotNil(sut.tableView.dequeueReusableCell(withIdentifier: ReferralMyCodeCell.reuseID))
        XCTAssertNotNil(sut.tableView.dequeueReusableCell(withIdentifier: ReferralFriendInputCell.reuseID))
        XCTAssertNotNil(sut.tableView.dequeueReusableCell(withIdentifier: ReferralCaptionCell.reuseID))
    }
}
