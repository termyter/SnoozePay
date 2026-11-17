import UIKit
import XCTest
@testable import SnoozePay

/// Dynamic Type, slice 1: the scaling seam and the Settings screen (#1111).
///
/// Every measurement overrides the category explicitly — `.large` for "today"
/// and AX3 for "grown" — so neither depends on what the simulator is set to,
/// and the AX3 override can never equal the screen's own value and measure
/// nothing.
@MainActor
final class SettingsDynamicTypeTests: XCTestCase {

    private let rowWidth: CGFloat = 320
    private let longTitle = "Цена откладывания по умолчанию"
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    private static let large = UITraitCollection(preferredContentSizeCategory: .large)
    private static let ax3 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)

    /// Each scaled role next to the fixed role it must equal at `.large`.
    private struct Role {
        let name: String
        let fixed: UIFont
        let scaled: () -> UIFont
    }

    private var roles: [Role] {
        [
            Role(name: "bodyLg", fixed: AppTypography.bodyLg) { AppTypography.scaledBodyLg },
            Role(name: "body", fixed: AppTypography.body) { AppTypography.scaledBody },
            Role(name: "meta", fixed: AppTypography.meta) { AppTypography.scaledMeta },
            Role(name: "caps", fixed: AppTypography.caps) { AppTypography.scaledCaps() }
        ]
    }

    // MARK: - Seam

    /// The font a label carrying `make()` actually renders under `traits`.
    /// Measured through a label because that is how every call site consumes
    /// a role: `UIFontMetrics` without explicit traits ignores
    /// `performAsCurrent`, and the label re-scales from its own traits.
    private static func resolve(_ make: () -> UIFont, under traits: UITraitCollection) -> UIFont {
        let host = UIView()
        let label = UILabel()
        label.font = make()
        label.adjustsFontForContentSizeCategory = true
        host.addSubview(label)
        host.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        host.updateTraitsIfNeeded()
        return label.font
    }

    func testEveryScaledRoleIsTheFixedFontAtTheDefaultSize() {
        for role in roles {
            let font = Self.resolve(role.scaled, under: Self.large)
            XCTAssertEqual(font.pointSize, role.fixed.pointSize, "\(role.name) moved at the default size")
            XCTAssertEqual(font.fontName, role.fixed.fontName, "\(role.name) changed face")
        }
    }

    func testEveryScaledRoleGrowsAndStopsAtTheCap() {
        for role in roles {
            let font = Self.resolve(role.scaled, under: Self.ax3)
            XCTAssertGreaterThan(font.pointSize, role.fixed.pointSize, "\(role.name) ignores Dynamic Type")
            XCTAssertLessThanOrEqual(
                font.pointSize, role.fixed.pointSize * AppTypography.maximumScale,
                "\(role.name) exceeded the cap"
            )
            XCTAssertEqual(font.fontName, role.fixed.fontName, "\(role.name) changed face when scaled")
        }
    }

    func testTheLargestAccessibilitySizeIsCappedAtTwice() {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let font = AppTypography.scaled(AppTypography.bodyLg, as: .body, compatibleWith: traits)
        XCTAssertEqual(font.pointSize, AppTypography.bodyLg.pointSize * 2, accuracy: 0.01)
    }

    // MARK: - Icon row

    private func iconRow(_ category: UIContentSizeCategory, title: String) -> SettingsIconRowCell {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(
            systemName: "rublesign.circle", iconColor: AppColors.warn400, title: title,
            trailingText: "50 ₽", accessory: .disclosureIndicator
        )
        cell.traitOverrides.preferredContentSizeCategory = category
        cell.updateTraitsIfNeeded()
        XCTAssertEqual(cell.traitCollection.preferredContentSizeCategory, category, "override did not land")
        cell.frame = CGRect(x: 0, y: 0, width: rowWidth, height: fittedHeight(of: cell))
        cell.layoutIfNeeded()
        return cell
    }

    private func fittedHeight(of cell: UITableViewCell) -> CGFloat {
        cell.layoutIfNeeded()
        return cell.contentView.systemLayoutSizeFitting(
            CGSize(width: rowWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func label(_ text: String, in root: UIView) throws -> UILabel {
        try XCTUnwrap(descendants(of: UILabel.self, in: root).first { $0.text == text }, "no label «\(text)»")
    }

    func testAtTheDefaultSizeTheRowIsUnchanged() throws {
        let short = iconRow(.large, title: "Вибрация")
        XCTAssertEqual(fittedHeight(of: short), SettingsIconRowCell.minimumRowHeight, accuracy: 0.5)
        let title = try label("Вибрация", in: short)
        XCTAssertEqual(title.font.pointSize, AppTypography.bodyLg.pointSize)
        XCTAssertEqual(title.font.fontName, AppTypography.bodyLg.fontName)
        XCTAssertEqual(try label("50 ₽", in: short).font.pointSize, AppTypography.meta.pointSize)
    }

    func testAtAX3TheTitleGrowsWrapsAndTheRowGrows() throws {
        let regular = iconRow(.large, title: longTitle)
        let grown = iconRow(.accessibilityExtraExtraExtraLarge, title: longTitle)
        let regularTitle = try label(longTitle, in: regular)
        let grownTitle = try label(longTitle, in: grown)

        XCTAssertGreaterThan(grownTitle.font.pointSize, regularTitle.font.pointSize, "title font did not scale")
        XCTAssertGreaterThan(
            grownTitle.frame.height, grownTitle.font.lineHeight * 1.5, "the title stays on one line"
        )
        let needed = grownTitle.sizeThatFits(
            CGSize(width: grownTitle.bounds.width, height: .greatestFiniteMagnitude)
        ).height
        XCTAssertLessThanOrEqual(needed, grownTitle.bounds.height + 0.5, "the title is truncated")
        XCTAssertGreaterThan(fittedHeight(of: grown), fittedHeight(of: regular), "the row did not grow")
    }

    // MARK: - Hosted screen

    private func hostedSettings(_ category: UIContentSizeCategory) -> SettingsViewController {
        let defaults = makeIsolatedDefaults()
        let sut = SettingsViewController(
            themeService: ThemeService(defaults: defaults),
            alarmDefaults: AlarmDefaults(defaults: defaults),
            referralService: ReferralService(
                defaults: defaults,
                balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
            ),
            walletCurrencyStore: WalletCurrencyStore(defaults: defaults),
            priceContextSource: { .scale(.rouble) },
            notificationCenter: NotificationCenter()
        )
        sut.traitOverrides.preferredContentSizeCategory = category
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 900))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = sut
        window.makeKeyAndVisible()
        hostWindows.append(window)
        sut.updateTraitsIfNeeded()
        XCTAssertEqual(sut.traitCollection.preferredContentSizeCategory, category, "override did not land")
        window.layoutIfNeeded()
        return sut
    }

    private func headerFont(in sut: SettingsViewController) throws -> UIFont {
        let header = try XCTUnwrap(descendants(of: SettingsSectionHeaderView.self, in: sut.view).first)
        let label = try XCTUnwrap(descendants(of: UILabel.self, in: header).first)
        let text = try XCTUnwrap(label.attributedText)
        return try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    }

    func testTheScreenAtTheDefaultSizeKeepsTodaysFontsAndRows() throws {
        let sut = hostedSettings(.large)
        let first = IndexPath(row: 0, section: 0)
        XCTAssertEqual(try headerFont(in: sut).pointSize, AppTypography.caps.pointSize)
        let cell = try XCTUnwrap(sut.tableView.cellForRow(at: first))
        let title = try XCTUnwrap(descendants(of: UILabel.self, in: cell.contentView).first)
        XCTAssertEqual(title.font.pointSize, AppTypography.bodyLg.pointSize)
        XCTAssertEqual(title.font.fontName, AppTypography.bodyLg.fontName)
        XCTAssertGreaterThanOrEqual(sut.tableView.rectForRow(at: first).height, SettingsIconRowCell.minimumRowHeight)
    }

    func testTheScreenAtAX3GrowsItsHeadersAndRows() throws {
        let regular = hostedSettings(.large)
        let grown = hostedSettings(.accessibilityExtraExtraExtraLarge)
        let first = IndexPath(row: 0, section: 0)

        XCTAssertGreaterThan(try headerFont(in: grown).pointSize, try headerFont(in: regular).pointSize)
        XCTAssertGreaterThan(
            grown.tableView.rectForHeader(inSection: 0).height,
            regular.tableView.rectForHeader(inSection: 0).height,
            "the section header did not grow"
        )
        XCTAssertGreaterThan(
            grown.tableView.rectForRow(at: first).height,
            regular.tableView.rectForRow(at: first).height,
            "the first Settings row did not grow"
        )
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }
}
