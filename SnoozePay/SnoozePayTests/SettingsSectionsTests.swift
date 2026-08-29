import XCTest
@testable import SnoozePay

/// Composition coverage for Settings V3 (#283): which rows live in which
/// section, the version footer string, and the data-source row counts. These
/// run on the main actor because they touch a `UIViewController` table.
@MainActor
final class SettingsSectionsTests: XCTestCase {

    private func makeSUT() -> SettingsViewController {
        let suite = "test.settings.sections.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let sut = SettingsViewController(alarmDefaults: AlarmDefaults(defaults: defaults))
        sut.loadViewIfNeeded()
        return sut
    }

    // MARK: - Section order

    func testSectionOrder_matchesDesign() {
        XCTAssertEqual(
            SettingsViewController.Section.allCases,
            [.finance, .soundNotifications, .rules, .referral, .other, .diagnostics]
        )
    }

    func testLegacySectionsRemoved() {
        // АККАУНТ (history + balance) and a standalone ОФОРМЛЕНИЕ section are
        // gone — there is no `.account` / `.appearance` case anymore. Asserting
        // the count is the compile-safe way to lock the section list. The
        // appended `.diagnostics` recovery section (#102) brings the total to 6.
        XCTAssertEqual(SettingsViewController.Section.allCases.count, 6)
    }

    // MARK: - Recovery section visibility (#102)

    func testRecoveryHidden_whenNoLoadFailed() {
        XCTAssertFalse(
            SettingsViewController.shouldShowRecovery(alarmFailed: false, transactionFailed: false)
        )
    }

    func testRecoveryVisible_whenAlarmLoadFailed() {
        XCTAssertTrue(
            SettingsViewController.shouldShowRecovery(alarmFailed: true, transactionFailed: false)
        )
    }

    func testRecoveryVisible_whenTransactionLoadFailed() {
        XCTAssertTrue(
            SettingsViewController.shouldShowRecovery(alarmFailed: false, transactionFailed: true)
        )
    }

    func testRecoveryVisible_whenBothFailed() {
        XCTAssertTrue(
            SettingsViewController.shouldShowRecovery(alarmFailed: true, transactionFailed: true)
        )
    }

    // MARK: - Row composition per section

    func testFinanceSection_priceThenSnoozeDuration() {
        let sut = makeSUT()
        let section = SettingsViewController.Section.finance.rawValue
        XCTAssertEqual(sut.tableView(sut.tableView, numberOfRowsInSection: section), 2)
        XCTAssertEqual(SettingsViewController.FinanceRow.defaultPrice.rawValue, 0)
        XCTAssertEqual(SettingsViewController.FinanceRow.snoozeDuration.rawValue, 1)
    }

    /// The section lost its middle row when #566 dropped the Critical Alerts
    /// affordance — AlarmKit already rings through silent mode, and the
    /// entitlement that row advertised is not one Apple grants alarm apps.
    /// Pinning the count as well as the case list keeps a re-added row from
    /// silently shifting `indexPath.row` under the two survivors.
    func testSoundSection_volumeThenVibration() {
        let sut = makeSUT()
        let section = SettingsViewController.Section.soundNotifications.rawValue
        XCTAssertEqual(sut.tableView(sut.tableView, numberOfRowsInSection: section), 2)
        XCTAssertEqual(
            SettingsViewController.SoundRow.allCases,
            [.volume, .vibration]
        )
        XCTAssertEqual(SettingsViewController.SoundRow.volume.rawValue, 0)
        XCTAssertEqual(SettingsViewController.SoundRow.vibration.rawValue, 1)
    }

    func testRulesSection_progressiveOnly() {
        let sut = makeSUT()
        let section = SettingsViewController.Section.rules.rawValue
        // Only «Прогрессивная цена» — «Бонус за серию»/«Защита от скуки» are
        // intentionally omitted (no backing rule).
        XCTAssertEqual(sut.tableView(sut.tableView, numberOfRowsInSection: section), 1)
    }

    func testOtherSection_privacyTermsContactTheme() {
        let sut = makeSUT()
        let section = SettingsViewController.Section.other.rawValue
        XCTAssertEqual(sut.tableView(sut.tableView, numberOfRowsInSection: section), 4)
        XCTAssertEqual(
            SettingsViewController.OtherRow.allCases,
            [.privacy, .terms, .contact, .theme]
        )
    }

    // MARK: - Section headers

    func testSectionHeaders_copy() {
        let sut = makeSUT()
        let table = sut.tableView
        XCTAssertEqual(
            sut.tableView(table, titleForHeaderInSection: SettingsViewController.Section.finance.rawValue),
            "ФИНАНСЫ"
        )
        XCTAssertEqual(
            sut.tableView(table, titleForHeaderInSection: SettingsViewController.Section.soundNotifications.rawValue),
            "ЗВУК И УВЕДОМЛЕНИЯ"
        )
        XCTAssertEqual(
            sut.tableView(table, titleForHeaderInSection: SettingsViewController.Section.rules.rawValue),
            "ПРАВИЛА"
        )
        XCTAssertEqual(
            sut.tableView(table, titleForHeaderInSection: SettingsViewController.Section.other.rawValue),
            "ПРОЧЕЕ"
        )
    }

    // MARK: - Version footer

    func testVersionFooterString_format() {
        let bundle = Bundle(for: SettingsSectionsTests.self)
        // The test bundle still carries the two version keys; only the format
        // matters here, not the exact numbers.
        let footer = SettingsViewController.versionFooterString(bundle: bundle)
        XCTAssertTrue(footer.hasPrefix("SnoozePay "), "footer: \(footer)")
        XCTAssertTrue(footer.contains(" · build "), "footer: \(footer)")
    }

    func testVersionFooterString_missingKeysFallBack() {
        // A bundle with no Info.plist version keys → both components show "—"
        // but the structure (prefix + "· build") survives.
        // swiftlint:disable:next discouraged_direct_init
        let empty = Bundle()
        let footer = SettingsViewController.versionFooterString(bundle: empty)
        XCTAssertEqual(footer, "SnoozePay — · build —")
    }
}
