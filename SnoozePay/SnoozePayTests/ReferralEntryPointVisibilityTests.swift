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

    /// Name + store for every throwaway suite `makeSettings` builds, so
    /// tearDown can delete the domain instead of leaving it behind.
    ///
    /// This became load-bearing with the referral seam (#690) and was not
    /// before: while the screen held `ReferralService.shared`, `getMyCode()`
    /// wrote into `UserDefaults.standard` and these suites were never written
    /// to, so they never materialised. Now the write lands here, and
    /// `makeSettings()` runs eight times per pass of this class — eight
    /// orphaned domains in the test host's container, with `cfprefsd` holding
    /// each registered one for the life of the process. CI boots a clean
    /// simulator and would never show it; a developer machine accumulates it.
    private var suites: [(name: String, defaults: UserDefaults)] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        suites.forEach { $0.defaults.removePersistentDomain(forName: $0.name) }
        suites.removeAll()
        super.tearDown()
    }

    /// A real, laid-out Settings screen at a real device width. The footer
    /// questions cannot be answered without one — `rectForFooter(inSection:)`
    /// on an unlaid table reports nothing.
    private func laidOutSettings(
        referralEnabled: Bool = AppFeatureFlags.referralEnabled,
        recoveryVisible: Bool = false
    ) throws -> SettingsVisibilityController {
        let sut = makeSettings(recoveryVisible: recoveryVisible)
        sut.referralEnabled = referralEnabled
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

    private func makeSettings(recoveryVisible: Bool = false) -> SettingsVisibilityController {
        let suite = "test.referral.visibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        suites.append((name: suite, defaults: defaults))
        // The referral service is pinned to the same throwaway suite, not left
        // at `.shared`. Laying the section out in the ON position calls
        // `getMyCode()`, which GENERATES AND PERSISTS a code on first read —
        // against `.shared` that write lands in `UserDefaults.standard` (#690).
        let sut = SettingsVisibilityController(
            alarmDefaults: AlarmDefaults(defaults: defaults),
            referralService: ReferralService(
                defaults: defaults,
                balanceService: BalanceService(
                    defaults: defaults,
                    notificationCenter: NotificationCenter()
                )
            )
        )
        sut.recoveryVisible = recoveryVisible
        sut.loadViewIfNeeded()
        return sut
    }

    // MARK: - Section model, both flag positions

    func testTheSectionModelDropsReferralWhenTheFlagIsOff() {
        let sections = SettingsViewController.visibleSections(referralEnabled: false, recoveryVisible: true)
        XCTAssertFalse(sections.contains(.referral))
        XCTAssertEqual(sections.count, SettingsViewController.Section.allCases.count - 1)
    }

    /// Turning the flag back on must return the whole section, not a subset —
    /// this is what makes the hide reversible rather than a slow deletion.
    ///
    /// This used to assert `referralRowCount(referralEnabled:)`, a helper that
    /// was gated a second time behind a `switch` the section had already been
    /// filtered out of. The off-branch was unreachable in production, so the
    /// test was green against code that never ran. Both helpers are gone; the
    /// model has one gate and it is asserted here and on a live table below.
    func testTheSectionModelRestoresReferralWhenTheFlagIsOn() {
        let sections = SettingsViewController.visibleSections(referralEnabled: true, recoveryVisible: true)
        XCTAssertEqual(sections, SettingsViewController.Section.allCases)
        XCTAssertEqual(SettingsViewController.ReferralRow.allCases.count, 3)
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
                ? SettingsViewController.Section.allCases.count - 1
                : SettingsViewController.Section.allCases.count - 2
        )
    }

    /// While the flag is ON the section is present and carries its header;
    /// this is the half that keeps the hide reversible rather than a deletion.
    ///
    /// It used to `XCTSkipUnless(AppFeatureFlags.referralEnabled)` — i.e. it
    /// never ran, because the shipped flag is `false`. A skipped test is not
    /// coverage: invert the `filter` in `visibleSections(referralEnabled:)`
    /// and nothing would have gone red until someone flipped the flag for
    /// real. `referralEnabled` is settable per instance now, so both
    /// positions lay out on a real table.
    func testTheSectionKeepsItsHeaderWhileTheFlagIsOn() throws {
        let sut = try laidOutSettings(referralEnabled: true)

        XCTAssertEqual(
            sut.tableView.numberOfSections,
            SettingsViewController.Section.allCases.count - 1,
            "the table did not build the referral section back"
        )

        let index = try XCTUnwrap(sut.visibleSections.firstIndex(of: .referral))
        XCTAssertEqual(
            sut.tableView(sut.tableView, titleForHeaderInSection: index), "ПРИГЛАСИТЬ ДРУГА"
        )
        XCTAssertEqual(
            sut.tableView(sut.tableView, numberOfRowsInSection: index),
            SettingsViewController.ReferralRow.allCases.count
        )
    }

    /// Flipping the flag on a table that is ALREADY laid out rebuilds it.
    ///
    /// Every other test here sets `referralEnabled` before hosting, so none of
    /// them executes the `didSet`. Delete that `didSet` and they all stay
    /// green — this is the only test that goes red, which is why it exists:
    /// a table left with a stale `numberOfSections` while `visibleSections`
    /// returns the new list routes taps to the wrong section.
    func testFlippingTheFlagOnALaidOutTableRebuildsIt() throws {
        let sut = try laidOutSettings(referralEnabled: false)
        XCTAssertEqual(
            sut.tableView.numberOfSections,
            SettingsViewController.Section.allCases.count - 2
        )

        sut.referralEnabled = true

        XCTAssertEqual(
            sut.tableView.numberOfSections,
            SettingsViewController.Section.allCases.count - 1,
            "the table did not rebuild when the flag flipped under it"
        )
        let index = try XCTUnwrap(sut.visibleSections.firstIndex(of: .referral))
        XCTAssertEqual(
            sut.tableView(sut.tableView, titleForHeaderInSection: index), "ПРИГЛАСИТЬ ДРУГА"
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
    /// actually build? Healthy Settings has neither optional section, so
    /// neither can reserve a phantom footer.
    func testTheHiddenSectionIsAbsentFromTheTable_notMerelyEmpty() throws {
        let sut = try laidOutSettings(referralEnabled: false)

        XCTAssertEqual(
            sut.tableView.numberOfSections, SettingsViewController.Section.allCases.count - 2,
            "a hidden section is still built; an empty section still reserves its footer"
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
            XCTAssertGreaterThan(sut.tableView.numberOfRows(inSection: index), 0)
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

    /// Exercise the real mapping and row factories in every combination,
    /// including recovery without referral: it must occupy index 4, not its
    /// raw value 5. No shared repository is corrupted to reach that state.
    func testOptionalSectionsMapToTheirRowsInEveryCombination() throws {
        let cases: [((referral: Bool, recovery: Bool), [SettingsViewController.Section])] = [
            ((false, false), [.finance, .soundNotifications, .rules, .other]),
            ((true, false), [.finance, .soundNotifications, .rules, .referral, .other]),
            ((false, true), [.finance, .soundNotifications, .rules, .other, .diagnostics]),
            ((true, true), [.finance, .soundNotifications, .rules, .referral, .other, .diagnostics])
        ]
        for (flags, expected) in cases {
            let sut = try laidOutSettings(referralEnabled: flags.referral, recoveryVisible: flags.recovery)
            XCTAssertEqual(sut.visibleSections, expected)
            XCTAssertEqual(sut.tableView.numberOfSections, expected.count)
            for (index, section) in expected.enumerated() {
                XCTAssertEqual(sut.visibleSection(at: index), section)
                XCTAssertGreaterThan(sut.tableView.numberOfRows(inSection: index), 0)
                XCTAssertNotNil(sut.tableView(sut.tableView, titleForHeaderInSection: index))
                XCTAssertGreaterThan(sut.tableView.rectForFooter(inSection: index).height, 1)
            }
            XCTAssertNil(sut.visibleSection(at: expected.count))
            if flags.recovery {
                let index = try XCTUnwrap(sut.visibleSections.firstIndex(of: .diagnostics))
                XCTAssertEqual(sut.tableView.numberOfRows(inSection: index), 1)
                let cell = sut.tableView(sut.tableView, cellForRowAt: IndexPath(row: 0, section: index))
                XCTAssertTrue(cell is SettingsIconRowCell)
                XCTAssertTrue(containsRecoveryTitle(in: cell))
            }
        }
    }

    /// Returning from a failed repository load and from recovery rebuilds the
    /// existing table; the diagnostic row must appear and disappear as a
    /// section, while the following version footer remains a table footer.
    func testRecoveryVisibilityRebuildsTheLaidOutTableOnAppearance() throws {
        let sut = try laidOutSettings(referralEnabled: false)
        XCTAssertEqual(sut.tableView.numberOfSections, 4)

        sut.recoveryVisible = true
        sut.viewWillAppear(false)
        sut.tableView.layoutIfNeeded()
        XCTAssertEqual(sut.visibleSection(at: 4), .diagnostics)
        XCTAssertEqual(sut.tableView.numberOfSections, 5)
        XCTAssertEqual(sut.tableView.numberOfRows(inSection: 4), 1)

        sut.recoveryVisible = false
        sut.viewWillAppear(false)
        sut.tableView.layoutIfNeeded()
        XCTAssertEqual(sut.tableView.numberOfSections, 4)
        XCTAssertNil(sut.visibleSection(at: 4))
    }

    /// Removing an empty section removes its footer, not the version line or
    /// the final visible section's spacing. Measure the laid-out boundary in
    /// both themes instead of pinning the old 17.33pt empty-section artifact.
    func testVersionFooterFollowsTheLastVisibleSectionInBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for recovery in [false, true] {
                let sut = try laidOutSettings(referralEnabled: false, recoveryVisible: recovery)
                sut.view.window?.overrideUserInterfaceStyle = style
                sut.view.window?.layoutIfNeeded()
                sut.tableView.layoutIfNeeded()
                let footer = try XCTUnwrap(sut.tableView.tableFooterView)
                footer.layoutIfNeeded()
                let lastIndex = sut.tableView.numberOfSections - 1
                let sectionEnd = sut.tableView.rect(forSection: lastIndex).maxY
                XCTAssertEqual(footer.frame.minY, sectionEnd, accuracy: 1 / sut.tableView.traitCollection.displayScale)
                XCTAssertGreaterThan(footer.bounds.height, 0)
                let label = try XCTUnwrap(footer.subviews.compactMap { $0 as? UILabel }.first)
                XCTAssertEqual(label.text, SettingsViewController.versionFooterString())
                XCTAssertGreaterThan(label.frame.minY, 0)
                XCTAssertLessThan(label.frame.maxY, footer.bounds.height)
            }
        }
    }

    private func containsRecoveryTitle(in view: UIView) -> Bool {
        if let label = view as? UILabel, label.text == Localized.text("settings.recovery.row_title") {
            return true
        }
        return view.subviews.contains { containsRecoveryTitle(in: $0) }
    }

    /// The row the hidden section used to own must not be reachable through
    /// the index it used to sit at. After the section is removed, index 3 is
    /// `.other` — so an index-based lookup that still spoke raw values would
    /// hand «Прочее» taps to the referral handler.
    func testTheIndexTheHiddenSectionVacatedNowBelongsToItsSuccessor() throws {
        let sut = try laidOutSettings(referralEnabled: false)

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
    /// #676 removed.
    ///
    /// The ON position, which is the half that was missing (#691): the single
    /// test here used to assert `contains(…) == AppFeatureFlags.referralEnabled`
    /// against a flag that ships `false`, i.e. `false == false` — green just as
    /// happily against a shortcut deleted outright. Now `referralShortcutEnabled`
    /// is settable per instance, so the button has to actually be built.
    func testTheStatisticsShortcutIsBuiltWhenTheFlagIsOn() throws {
        let labels = try debugRowLabels(referralShortcutEnabled: true)

        XCTAssertTrue(
            labels.contains("Referral program"),
            "the ON position builds no referral shortcut; labels: \(labels)"
        )
    }

    /// …and the OFF position, which is what ships. Asserted as a pair with the
    /// test above: either one alone passes against a hardcoded answer.
    func testTheStatisticsShortcutIsAbsentWhenTheFlagIsOff() throws {
        let labels = try debugRowLabels(referralShortcutEnabled: false)
        let labelsWithTheFlagOn = try debugRowLabels(referralShortcutEnabled: true)

        XCTAssertFalse(
            labels.contains("Referral program"),
            "the referral shortcut survived the OFF position; labels: \(labels)"
        )
        // The neighbouring shortcuts are untouched — the gate is one button,
        // not the whole DEBUG row.
        XCTAssertTrue(labels.contains("Streak modal"), "labels: \(labels)")
        XCTAssertTrue(labels.contains("AlarmOff warning"), "labels: \(labels)")
        XCTAssertEqual(
            labelsWithTheFlagOn.count, labels.count + 1,
            "the flag moved something other than the one referral button"
        )
    }

    /// Present is not the same as wired: a button that renders and does
    /// nothing would satisfy both tests above. So this taps the real control
    /// on a hosted screen and asks the navigation stack where it landed.
    ///
    /// The push itself (bar restored, canon chrome) belongs to
    /// `NavigationBarSymmetryTests`, which reaches `debugReferralTapped` by
    /// selector. This one starts from the button, so a shortcut wired to the
    /// wrong action — or to nothing — is caught here rather than nowhere.
    func testTappingTheStatisticsShortcutOpensTheReferralScreen() throws {
        let sut = StatisticsViewController()
        sut.referralShortcutEnabled = true
        let stack = UINavigationController(rootViewController: sut)
        let window = makeHostWindow()
        window.rootViewController = stack
        sut.loadViewIfNeeded()

        let button = try XCTUnwrap(
            try liveDebugRow(of: sut).arrangedSubviews
                .compactMap { $0 as? SPButton }
                .first { $0.accessibilityLabel == "Referral program" },
            "the hosted screen has no referral shortcut to tap"
        )
        button.sendActions(for: .touchUpInside)

        XCTAssertTrue(
            stack.topViewController is ReferralViewController,
            """
            tapping the shortcut landed on \
            \(String(describing: stack.topViewController)) — the button is \
            built but not wired to the referral screen
            """
        )
    }

    /// The live screen must reach the flag through `referralShortcutEnabled`,
    /// not by reading `AppFeatureFlags` inline again.
    ///
    /// Expressed against the shipped flag rather than a literal so the suite
    /// survives the one-line re-enable; the two tests above are what pin the
    /// behaviour in each position.
    func testTheStatisticsScreenSeedsItsShortcutFromTheSharedFlag() throws {
        let sut = StatisticsViewController()
        XCTAssertEqual(sut.referralShortcutEnabled, AppFeatureFlags.referralEnabled)

        let window = makeHostWindow()
        window.rootViewController = sut
        sut.loadViewIfNeeded()

        let labels = try liveDebugRow(of: sut).arrangedSubviews.compactMap { $0.accessibilityLabel }
        XCTAssertEqual(
            labels.contains("Referral program"), AppFeatureFlags.referralEnabled,
            "the built screen stopped following its own flag; labels: \(labels)"
        )
    }

    // MARK: - DEBUG-row helpers

    private func debugRowLabels(referralShortcutEnabled: Bool) throws -> [String] {
        let sut = StatisticsViewController()
        sut.referralShortcutEnabled = referralShortcutEnabled
        let stack = try XCTUnwrap(sut.makeDebugButtonsRow() as? UIStackView)
        return stack.arrangedSubviews.compactMap { $0.accessibilityLabel }
    }

    /// The DEBUG row as `setupLayout()` actually installed it — found by the
    /// shortcut it always carries rather than by position, so reordering the
    /// cards above does not turn into a failure about the referral flag.
    private func liveDebugRow(of sut: StatisticsViewController) throws -> UIStackView {
        try XCTUnwrap(
            sut.contentStack.arrangedSubviews
                .compactMap { $0 as? UIStackView }
                .first { candidate in
                    candidate.arrangedSubviews.contains { $0.accessibilityLabel == "Streak modal" }
                },
            "the statistics screen built no DEBUG shortcut row"
        )
    }

    private func makeHostWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 900))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        hostWindows.append(window)
        return window
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

/// Only the recovery read is replaced. The production section mapping,
/// data source, row construction and lifecycle reloads are exercised intact.
private final class SettingsVisibilityController: SettingsViewController {
    var recoveryVisible = false

    override var isRecoveryVisible: Bool { recoveryVisible }
}
