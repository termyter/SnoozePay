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

    /// Configured first, overridden second: the labels must follow a live
    /// category change, not only the category they were built under.
    private func iconRow(
        _ category: UIContentSizeCategory, title: String, subtitle: String? = nil
    ) -> SettingsIconRowCell {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(
            systemName: "rublesign.circle", iconColor: AppColors.warn400, title: title,
            subtitle: subtitle, trailingText: "50 ₽", accessory: .disclosureIndicator
        )
        override(cell, to: category)
        cell.frame = CGRect(x: 0, y: 0, width: rowWidth, height: SettingsIconRowCell.minimumRowHeight)
        cell.frame.size.height = fittedHeight(of: cell)
        cell.layoutIfNeeded()
        return cell
    }

    private func override(_ view: UIView, to category: UIContentSizeCategory) {
        view.traitOverrides.preferredContentSizeCategory = category
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, category, "override did not land")
    }

    /// Fitted at the content view's real width. The disclosure accessory makes
    /// it narrower than the row; fitting at the full row width wraps the title
    /// into a line too few, and the row then clips it.
    private func fittedHeight(of cell: UITableViewCell) -> CGFloat {
        cell.layoutIfNeeded()
        return cell.contentView.systemLayoutSizeFitting(
            CGSize(width: cell.contentView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
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
        // Measured outside the label's own cap: `sizeThatFits` honours
        // `numberOfLines`, so a two-line cap would "fit" a truncated title.
        XCTAssertEqual(grownTitle.numberOfLines, 0, "the title is capped at a line count")
        XCTAssertFalse(isClipped(grownTitle), "the title is truncated")
        XCTAssertGreaterThan(fittedHeight(of: grown), fittedHeight(of: regular), "the row did not grow")
    }

    func testAtAX3TheSubtitleAndTheValueGrow() throws {
        let subtitle = AppConstants.supportEmail
        let regular = iconRow(.large, title: "Связаться с нами", subtitle: subtitle)
        let grown = iconRow(.accessibilityExtraExtraExtraLarge, title: "Связаться с нами", subtitle: subtitle)
        XCTAssertGreaterThan(
            try label(subtitle, in: grown).font.pointSize, try label(subtitle, in: regular).font.pointSize,
            "the subtitle did not scale"
        )
        XCTAssertGreaterThan(
            try label("50 ₽", in: grown).font.pointSize, try label("50 ₽", in: regular).font.pointSize,
            "the trailing value did not scale"
        )
    }

    func testAtAX3TheThemeTitleGrows() throws {
        let title = Localized.text("settings.theme.title")
        let regular = ThemeSegmentCell(style: .default, reuseIdentifier: nil)
        regular.configure(selectedIndex: 0) { _ in }
        override(regular, to: .large)
        let grown = ThemeSegmentCell(style: .default, reuseIdentifier: nil)
        grown.configure(selectedIndex: 0) { _ in }
        override(grown, to: .accessibilityExtraExtraExtraLarge)

        let regularFont = try label(title, in: regular).font!
        XCTAssertEqual(regularFont.pointSize, AppTypography.bodyLg.pointSize)
        XCTAssertEqual(regularFont.fontName, AppTypography.bodyLg.fontName)
        XCTAssertGreaterThan(try label(title, in: grown).font.pointSize, regularFont.pointSize)
        XCTAssertEqual(try label(title, in: grown).numberOfLines, 0, "the theme title cannot wrap")
    }

    func testAtAX3TheLegalTextGrows() throws {
        func textFont(_ category: UIContentSizeCategory) throws -> UIFont {
            let legal = LegalViewController(title: "Privacy")
            legal.loadViewIfNeeded()
            override(legal.view, to: category)
            let textView = try XCTUnwrap(descendants(of: UITextView.self, in: legal.view).first)
            return try XCTUnwrap(textView.font)
        }
        let regular = try textFont(.large)
        XCTAssertEqual(regular.pointSize, AppTypography.body.pointSize)
        XCTAssertGreaterThan(try textFont(.accessibilityExtraExtraExtraLarge).pointSize, regular.pointSize)
    }

    /// The height the label's text needs at its current width with no line
    /// cap exceeds the height it was given. Half a point absorbs rounding; a
    /// clipped label is a whole line short.
    private func isClipped(_ label: UILabel) -> Bool {
        let unlimited = label.textRect(
            forBounds: CGRect(x: 0, y: 0, width: label.bounds.width, height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: 0
        )
        return unlimited.height > label.bounds.height + 0.5
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

    private func headerLabel(in sut: SettingsViewController) throws -> UILabel {
        let header = try XCTUnwrap(descendants(of: SettingsSectionHeaderView.self, in: sut.view).first)
        return try XCTUnwrap(descendants(of: UILabel.self, in: header).first)
    }

    private func headerFont(in sut: SettingsViewController) throws -> UIFont {
        let text = try XCTUnwrap(try headerLabel(in: sut).attributedText)
        return try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    }

    /// Tracking must stay +0.12em of whatever size the caps scaled to.
    private func assertHeaderKerningFollowsTheFont(in sut: SettingsViewController) throws {
        let text = try XCTUnwrap(try headerLabel(in: sut).attributedText)
        let kern = try XCTUnwrap(text.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        let font = try headerFont(in: sut)
        XCTAssertEqual(
            kern / font.pointSize, AppTypography.capsKerning / AppTypography.caps.pointSize, accuracy: 0.0001
        )
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
        let volume = IndexPath(
            row: SettingsViewController.SoundRow.volume.rawValue,
            section: try XCTUnwrap(sut.visibleSections.firstIndex(of: .soundNotifications))
        )
        // A one-line row in the hosted table measures 53pt, not the bare 52pt
        // floor: the table rounds the self-sized height up. That is today's
        // value, measured with the same test on the pre-#1111 code (27dec8f8),
        // so it is pinned exactly rather than as `>=`.
        let todaysOneLineRowHeight = SettingsIconRowCell.minimumRowHeight + 1
        let volumeCell = try XCTUnwrap(sut.tableView.cellForRow(at: volume))
        XCTAssertEqual(
            volumeCell.contentView.bounds.height, todaysOneLineRowHeight, accuracy: 0.01,
            "a one-line row changed height at the default size"
        )
        XCTAssertEqual(try headerFont(in: sut).fontName, AppTypography.caps.fontName)
        try assertHeaderKerningFollowsTheFont(in: sut)
    }

    func testTheScreenAtAX3GrowsItsHeadersAndRows() throws {
        let regular = hostedSettings(.large)
        let grown = hostedSettings(.accessibilityExtraExtraExtraLarge)
        let first = IndexPath(row: 0, section: 0)

        XCTAssertGreaterThan(try headerFont(in: grown).pointSize, try headerFont(in: regular).pointSize)
        try assertHeaderKerningFollowsTheFont(in: grown)
        XCTAssertEqual(try headerLabel(in: grown).numberOfLines, 0, "the section header cannot wrap")
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
        // Probed at AXL and AX3 while writing this: every row self-sizes
        // around its wrapped text, none is clipped.
        let rows = grown.tableView.visibleCells
        XCTAssertGreaterThan(rows.count, 3, "too few rows on screen to say anything")
        for cell in rows {
            let labels = descendants(of: UILabel.self, in: cell.contentView)
            for label in labels where !label.isHidden && label.text != nil {
                XCTAssertFalse(isClipped(label), "«\(label.text ?? "")» is clipped at AX3")
            }
        }
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }
}
