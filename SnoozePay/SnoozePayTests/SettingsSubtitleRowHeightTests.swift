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

    private func makeSUT() -> SettingsViewController {
        let suite = "test.settings.subtitle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let sut = SettingsViewController(alarmDefaults: AlarmDefaults(defaults: defaults))
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

    func testEverySettingsSectionOutsideReferralSelfSizes() {
        let sut = makeSUT()
        let table = sut.tableView

        for section in SettingsViewController.Section.allCases where section != .referral {
            let height = sut.tableView(table, heightForRowAt: IndexPath(row: 0, section: section.rawValue))
            XCTAssertEqual(
                height, UITableView.automaticDimension,
                "\(section) returns a fixed height — the next row that grows will be clipped"
            )
        }
    }

    /// The contact row specifically, named so a future reader can trace the
    /// issue straight to the assertion.
    func testContactRowSelfSizes() {
        let sut = makeSUT()
        let indexPath = IndexPath(
            row: SettingsViewController.OtherRow.contact.rawValue,
            section: SettingsViewController.Section.other.rawValue
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
    func testReferralKeepsItsOwnRowHeights() {
        let sut = makeSUT()
        let indexPath = IndexPath(
            row: SettingsViewController.ReferralRow.myCode.rawValue,
            section: SettingsViewController.Section.referral.rawValue
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
