import XCTest
@testable import SnoozePay

/// Issue #632 — «Связаться с нами» shows `support@snoozepay.app` on a second
/// line, and that line was clipped through the middle: the descenders of `y`
/// and `pp` fell below the fold, so the address read `support@snoozepav.app`,
/// a domain that does not exist.
///
/// The row was not broken. Its SECTION was: `.other` self-sized only its theme
/// row, so the contact row took the fixed 52pt rhythm, and
/// `UIView-Encapsulated-Layout-Height` — required priority — beat the cell's
/// own bottom constraint.
///
/// Heights are asserted, not `numberOfLines`: a two-line label inside a row
/// pinned to 52pt looks exactly like the bug, and only the measurement catches
/// that pairing. Same reasoning as `SettingsRowTitleWrappingTests` (#519).
@MainActor
final class SettingsSubtitleRowHeightTests: XCTestCase {

    /// The narrowest shipping width, so the result does not depend on the
    /// brand faces being registered in the test host.
    private let rowWidth: CGFloat = 320

    private var suites: [(name: String, defaults: UserDefaults)] = []

    override func tearDown() {
        suites.forEach { $0.defaults.removePersistentDomain(forName: $0.name) }
        suites.removeAll()
        super.tearDown()
    }

    /// Every store this screen touches is pinned to one throwaway suite —
    /// including the referral service.
    ///
    /// `testReferralKeepsItsOwnRowHeights` lays the section out in the ON
    /// position, and it is only `heightForRowAt` (not `cellForRowAt`) that
    /// keeps `getMyCode()` from running today: add a `layoutIfNeeded()` here
    /// and the screen would generate and persist `referral_my_code` into
    /// `UserDefaults.standard` again, which is exactly #690. The seam costs
    /// six lines; relying on which delegate method a test happens to call
    /// costs the next author the same afternoon.
    private func makeSUT() -> SettingsViewController {
        let suite = "test.settings.subtitle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        suites.append((name: suite, defaults: defaults))
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
        return sut
    }

    private func contactCell() -> SettingsIconRowCell {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(
            systemName: "envelope",
            iconColor: AppColors.fg3,
            title: "Связаться с нами",
            subtitle: AppConstants.supportEmail,
            accessory: .disclosureIndicator
        )
        cell.frame = CGRect(
            x: 0, y: 0,
            width: rowWidth, height: SettingsIconRowCell.minimumRowHeight
        )
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        return cell
    }

    private func fittedHeight(of cell: UITableViewCell) -> CGFloat {
        cell.contentView.systemLayoutSizeFitting(
            CGSize(width: rowWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    // MARK: - The measurement that proves 52 was clipping

    func testARowWithASubtitleNeedsMoreThanTheRowRhythm() {
        XCTAssertGreaterThan(
            fittedHeight(of: contactCell()), SettingsIconRowCell.minimumRowHeight,
            "Title + subtitle does not fit the 52pt rhythm — a fixed height can only clip it"
        )
    }

    /// Not merely "taller": tall enough for the whole glyph box. A row short by
    /// two points still eats the descenders, which is exactly how a `y` came to
    /// look like a `v`.
    func testTheSubtitleGetsItsFullLineHeightIncludingDescenders() throws {
        let cell = contactCell()
        cell.frame.size.height = fittedHeight(of: cell)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let subtitle = try XCTUnwrap(
            descendants(of: UILabel.self, in: cell)
                .first { $0.text == AppConstants.supportEmail },
            "subtitle label not found"
        )
        let font = try XCTUnwrap(subtitle.font)

        XCTAssertGreaterThanOrEqual(
            subtitle.frame.height, font.lineHeight - 0.5,
            "The subtitle box is shorter than its own line height — descenders are cut"
        )
        XCTAssertLessThanOrEqual(
            subtitle.frame.maxY, cell.contentView.bounds.height + 0.5,
            "The subtitle overflows the content view, so the row clips it"
        )
    }

    // MARK: - The fix itself

    /// Iterated over the LIVE indices, not over `Section.allCases.rawValue`.
    ///
    /// After #676 a hidden section is absent, so raw values and table indices
    /// no longer agree: `.other` (4) would resolve to `.diagnostics`, and
    /// `.diagnostics` (5) to nothing at all. Both would pass vacuously —
    /// `heightForRowAt` answers `automaticDimension` for everything that is not
    /// `.referral`, including an index that resolves to `nil` — and the failure
    /// message would name the wrong section.
    func testEverySettingsSectionOutsideReferralSelfSizes() {
        let sut = makeSUT()
        let table = sut.tableView

        for index in sut.visibleSections.indices where sut.visibleSections[index] != .referral {
            let height = sut.tableView(table, heightForRowAt: IndexPath(row: 0, section: index))
            XCTAssertEqual(
                height, UITableView.automaticDimension,
                "\(sut.visibleSections[index]) returns a fixed height — "
                    + "the next row that grows will be clipped"
            )
        }
        XCTAssertTrue(
            sut.visibleSections.contains(.other),
            "the loop stopped covering `.other`, which is the section this file exists for"
        )
    }

    /// The contact row specifically, named so a future reader can trace the
    /// issue straight to the assertion.
    ///
    /// The live index, for the reason spelled out above: at the raw value this
    /// used to pass while measuring `.diagnostics`, i.e. the guard for #632
    /// («support@snoozepav.app», a domain that does not exist) had quietly
    /// stopped touching the row it is named for.
    func testContactRowSelfSizes() throws {
        let sut = makeSUT()
        let indexPath = IndexPath(
            row: SettingsViewController.OtherRow.contact.rawValue,
            section: try XCTUnwrap(sut.visibleSections.firstIndex(of: .other))
        )

        XCTAssertEqual(
            sut.tableView(sut.tableView, heightForRowAt: indexPath),
            UITableView.automaticDimension
        )
    }

    // MARK: - What must not change

    /// Self-sizing must not make short rows shrink: the cell's 999-priority
    /// floor is what keeps the 52pt rhythm across sections.
    func testAOneLineRowStillMeasuresAtTheRowRhythm() {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(systemName: "bell", iconColor: AppColors.fg3, title: "Вибрация")
        cell.frame = CGRect(
            x: 0, y: 0,
            width: rowWidth, height: SettingsIconRowCell.minimumRowHeight
        )
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        XCTAssertEqual(
            fittedHeight(of: cell), SettingsIconRowCell.minimumRowHeight, accuracy: 0.5,
            "A one-line row must keep the 52pt rhythm"
        )
    }

    /// Referral keeps its own heights — it is built from different cells with
    /// no shared floor, so it was deliberately left out of the rewrite.
    ///
    /// Skipped while the section is hidden (#676). It used to run anyway and
    /// pass: with `.referral` absent, `heightForRowAt` fell through to the
    /// `automaticDimension` branch for a section that does not exist, and
    /// `XCTAssertNotEqual(-1, -1)` is the only reason it was noticed at all.
    /// A test that keeps reporting green about an unreachable path is worse
    /// than no test.
    func testReferralKeepsItsOwnRowHeights() throws {
        let sut = makeSUT()
        // Not `XCTSkipUnless(AppFeatureFlags.referralEnabled)`: the shipped
        // flag is `false`, so that form never ran at all — and a test that
        // never runs is exactly the failure this doc describes, one level up.
        sut.referralEnabled = true
        let section = try XCTUnwrap(sut.visibleSections.firstIndex(of: .referral))
        let indexPath = IndexPath(
            row: SettingsViewController.ReferralRow.myCode.rawValue,
            section: section
        )

        XCTAssertNotEqual(
            sut.tableView(sut.tableView, heightForRowAt: indexPath),
            UITableView.automaticDimension
        )
    }

    // MARK: - Helper

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T { found.append(match) }
            found.append(contentsOf: descendants(of: type, in: subview))
        }
        return found
    }
}
