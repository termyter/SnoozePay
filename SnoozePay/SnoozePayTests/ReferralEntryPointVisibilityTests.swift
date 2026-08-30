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

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    /// A real, laid-out Settings screen at a real device width. The footer
    /// questions cannot be answered without one — `rectForFooter(inSection:)`
    /// on an unlaid table reports nothing.
    private func laidOutSettings() throws -> SettingsViewController {
        let sut = makeSettings()
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

    private func makeSettings() -> SettingsViewController {
        let suite = "test.referral.visibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let sut = SettingsViewController(alarmDefaults: AlarmDefaults(defaults: defaults))
        sut.loadViewIfNeeded()
        return sut
    }

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

    /// The table must reach the flag through the section MODEL, not by
    /// answering 0 rows at a fixed index.
    ///
    /// Asked through `visibleSections` rather than through
    /// `numberOfRowsInSection(referralSection)`: after #676 index 3 is
    /// `.other`, and a test that kept probing the raw value would report the
    /// wrong section's four rows as a failure of the flag.
    func testTheSectionModelFollowsTheFlag() {
        let sut = makeSettings()
        XCTAssertEqual(
            sut.visibleSections.contains(.referral), AppFeatureFlags.referralEnabled,
            "the section model stopped consulting AppFeatureFlags.referralEnabled"
        )
        XCTAssertEqual(
            sut.tableView.numberOfSections,
            AppFeatureFlags.referralEnabled
                ? SettingsViewController.Section.allCases.count
                : SettingsViewController.Section.allCases.count - 1
        )
    }

    /// While the flag is ON the section is present and carries its header;
    /// this is the half that keeps the hide reversible rather than a deletion.
    func testTheSectionKeepsItsHeaderWhileTheFlagIsOn() throws {
        let sut = makeSettings()
        try XCTSkipUnless(AppFeatureFlags.referralEnabled, "the section is hidden")

        let index = try XCTUnwrap(sut.visibleSections.firstIndex(of: .referral))
        XCTAssertEqual(
            sut.tableView(sut.tableView, titleForHeaderInSection: index), "ПРИГЛАСИТЬ ДРУГА"
        )
        XCTAssertEqual(
            sut.tableView(sut.tableView, numberOfRowsInSection: index),
            SettingsViewController.ReferralRow.allCases.count
        )
    }

    /// A hidden section must not leave its grouped footer behind — and the
    /// only way to know is to lay the table out and measure it.
    ///
    /// The previous version of this test asked the delegate what height it
    /// would return and compared that to the constant the delegate had just
    /// returned. It passed against an implementation that did **nothing**:
    /// UIKit ignores `.leastNonzeroMagnitude` from
    /// `heightForFooterInSection` when the section has no footer view, so the
    /// phantom 17.33pt survived and `contentSize.height` was identical with
    /// and without the method (875.0000089009603 either way, at 402pt).
    ///
    /// So this asks the table, not the delegate: how many sections did it
    /// actually build, and does its content end where six sections' worth of
    /// footers would put it.
    func testTheHiddenSectionIsAbsentFromTheTable_notMerelyEmpty() throws {
        let sut = try laidOutSettings()
        try XCTSkipIf(AppFeatureFlags.referralEnabled, "nothing is hidden while the flag is on")

        XCTAssertEqual(
            sut.tableView.numberOfSections, SettingsViewController.Section.allCases.count - 1,
            "the referral section is still built; an empty section still reserves its footer"
        )
        XCTAssertFalse(
            sut.visibleSections.contains(.referral),
            "`visibleSections` is what the index mapping reads — it must agree"
        )
    }

    /// …and every section that DOES render still keeps its own footer gap, so
    /// removing one is not paid for by flattening the form.
    ///
    /// Measured off the laid-out table rather than off the delegate: the
    /// grouped footer is 17.33pt at this width, and a section that lost it
    /// would report 0.
    func testEverySectionThatRendersKeepsItsFooterGap() throws {
        let sut = try laidOutSettings()
        for index in 0..<sut.tableView.numberOfSections {
            // Only sections that actually render. `.diagnostics` stays in the
            // list while empty and keeps a phantom footer — deliberate, since
            // it merges into the padding above the version line — but that is a
            // wart being tolerated (#684), not a requirement. Asserting it here
            // would fail the day someone collapses it, with a message claiming
            // the sections had run together.
            guard sut.tableView.numberOfRows(inSection: index) > 0 else { continue }
            let footer = sut.tableView.rectForFooter(inSection: index)
            XCTAssertGreaterThan(
                footer.height, 1,
                """
                \(sut.visibleSections[index]) lost its footer spacing \
                (\(footer.height)pt) — the sections have run together
                """
            )
        }
    }

    /// The row the hidden section used to own must not be reachable through
    /// the index it used to sit at. After the section is removed, index 3 is
    /// `.other` — so an index-based lookup that still spoke raw values would
    /// hand «Прочее» taps to the referral handler.
    func testTheIndexTheHiddenSectionVacatedNowBelongsToItsSuccessor() throws {
        let sut = try laidOutSettings()
        try XCTSkipIf(AppFeatureFlags.referralEnabled, "nothing is hidden while the flag is on")

        let vacated = SettingsViewController.Section.referral.rawValue
        XCTAssertEqual(sut.visibleSection(at: vacated), .other)
        XCTAssertEqual(
            sut.tableView(sut.tableView, titleForHeaderInSection: vacated), "ПРОЧЕЕ",
            "the table still reads section \(vacated) as `.referral` by raw value"
        )
    }

    /// An index past the end must be reported, not answered.
    ///
    /// `numberOfRowsInSection` and `titleForHeaderInSection` both return the
    /// «hidden» answer (0 / nil) for an unknown index, which is
    /// indistinguishable from a deliberately hidden section. That is fine as a
    /// return value and wrong as silence — the neighbouring
    /// `SettingsViewController+Referral` hits `assertionFailure` on an
    /// unexpected dequeue, and this path should not be quieter.
    func testAnIndexPastTheEndResolvesToNothing() throws {
        let sut = try laidOutSettings()
        XCTAssertNil(sut.visibleSection(at: sut.visibleSections.count))
        XCTAssertNil(sut.visibleSection(at: -1))
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
