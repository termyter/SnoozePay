import UIKit
import XCTest
@testable import SnoozePay

/// Dynamic Type, slice 2: the alarms list — `AlarmCell`, the list header with
/// its balance pill, and the empty state (#1111).
///
/// Same approach as `SettingsDynamicTypeTests`: every measurement overrides the
/// category explicitly (`.large` for today, AX5 — the largest — for grown), so nothing depends
/// on what the simulator is set to.
@MainActor
final class AlarmsListDynamicTypeTests: XCTestCase {

    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
    /// The narrowest supported phone: the hardest width for the grown card.
    private let narrow: CGFloat = 375
    private let wide: CGFloat = 402
    private let caps = "БУДНИ · ПН–ПТ"

    // Today's geometry, measured with these harnesses on the pre-#1111-list
    // code (0928c768) at both widths, so they are pinned exactly.
    private let todaysCardHeight: CGFloat = 197 + 1.0 / 3
    private let todaysHeaderHeight: CGFloat = 144
    private let todaysEmptyBodyHeight: CGFloat = 69 + 2.0 / 3
    /// The body's top in a 402×620 overlay, centred as today.
    private let todaysEmptyBodyMinY: CGFloat = 296 + 2.0 / 3

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Seam

    func testTheListRolesAreTheFixedFontsAtTheDefaultSizeAndCappedAtAX5() {
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let grown = UITraitCollection(preferredContentSizeCategory: Self.ax5)
        let roles: [(fixed: UIFont, scaled: (UITraitCollection) -> UIFont)] = [
            (AppTypography.clockLg, { AppTypography.scaledClockLg(compatibleWith: $0) }),
            (AppTypography.h1, { AppTypography.scaledH1(compatibleWith: $0) }),
            (AppTypography.h2, { AppTypography.scaledH2(compatibleWith: $0) })
        ]
        for (fixed, scaled) in roles {
            let name = "\(fixed.fontName) \(fixed.pointSize)"
            XCTAssertEqual(scaled(large).pointSize, fixed.pointSize, "\(name) moved at the default size")
            XCTAssertEqual(scaled(large).fontName, fixed.fontName, "\(name) changed face")
            XCTAssertGreaterThan(scaled(grown).pointSize, fixed.pointSize, "\(name) ignores Dynamic Type")
            XCTAssertLessThanOrEqual(scaled(grown).pointSize, fixed.pointSize * AppTypography.maximumScale)
        }
    }

    // MARK: - Alarm card

    private func card(
        _ category: UIContentSizeCategory, width: CGFloat? = nil, time: String = "07:00",
        sound: String = "Soft Dawn"
    ) -> AlarmCell {
        let cell = AlarmCell(style: .default, reuseIdentifier: nil)
        cell.configure(
            time: time, daysCaps: caps, priceText: "50 ₽", priceCurrency: .rub,
            multiplier: "×2", soundName: sound, enabled: true
        )
        override(cell, to: category)
        layOut(cell, width: width ?? narrow)
        return cell
    }

    private func layOut(_ cell: UITableViewCell, width: CGFloat) {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 200)
        cell.frame.size.height = fittedHeight(of: cell)
        cell.layoutIfNeeded()
    }

    func testAtTheDefaultSizeTheCardIsUnchanged() throws {
        for width in [narrow, wide] {
            let cell = card(.large, width: width)
            XCTAssertEqual(fittedHeight(of: cell), todaysCardHeight, accuracy: 0.01, "card height moved at \(width)")
            let clock = try label("07:00", in: cell)
            XCTAssertEqual(clock.font.pointSize, AppTypography.clockLg.pointSize)
            XCTAssertEqual(clock.font.fontName, AppTypography.clockLg.fontName)
            XCTAssertEqual(clock.numberOfLines, 1)
            XCTAssertEqual(try attributedFont(of: label(caps, in: cell)).pointSize, AppTypography.caps.pointSize)
            let pills = descendants(of: SPPill.self, in: cell)
            XCTAssertEqual(pills.count, 3)
            XCTAssertEqual(Set(pills.map(\.frame.minY)).count, 1, "the pills left their row")
            pills.forEach { XCTAssertEqual($0.frame.height, 26, accuracy: 0.01, "a pill changed height") }
            XCTAssertEqual(try attributedFont(of: label("50 ₽", in: cell)).pointSize, AppTypography.caps.pointSize)
        }
    }

    func testAtAX5TheCardTextGrowsCappedAndTheCardGrows() throws {
        let regular = card(.large)
        let grown = card(Self.ax5)
        for text in ["07:00", caps, "50 ₽", "×2", "Soft Dawn"] {
            let before = try attributedFont(of: label(text, in: regular)).pointSize
            let after = try attributedFont(of: label(text, in: grown)).pointSize
            XCTAssertGreaterThan(after, before, "«\(text)» did not scale")
            XCTAssertLessThanOrEqual(after, before * AppTypography.maximumScale, "«\(text)» exceeded the cap")
        }
        XCTAssertGreaterThan(fittedHeight(of: grown), fittedHeight(of: regular) + 40, "the card did not grow")
        assertNothingClipped(in: grown)
    }

    /// The switch sits beside the caps row; the grown clock spans the card and
    /// must start below the switch, and the pills stack inside the card.
    func testAtAX5TheToggleClockAndPillsDoNotCollide() throws {
        for time in ["07:00", "7:30 PM"] {
            let cell = card(Self.ax5, time: time, sound: "Своя мелодия")
            let surface = try XCTUnwrap(cell.toggleSwitch.superview)
            let toggle = cell.toggleSwitch.convert(cell.toggleSwitch.bounds, to: surface)
            let clock = try label(time, in: cell)
            let clockFrame = clock.convert(clock.bounds, to: surface)
            XCTAssertFalse(toggle.intersects(clockFrame), "toggle \(toggle) overlaps clock \(clockFrame)")
            // One line — a time never wraps — and, shrunk to fit or not, still
            // drawn larger than today's 64pt.
            XCTAssertEqual(clock.numberOfLines, 1)
            XCTAssertGreaterThan(try drawnPointSize(of: clock), AppTypography.clockLg.pointSize, "\(time) drawn")
            XCTAssertLessThanOrEqual(toggle.maxX, surface.bounds.maxX, "toggle left the card")
            let pills = descendants(of: SPPill.self, in: cell).map { $0.convert($0.bounds, to: surface) }
            for pill in pills {
                XCTAssertLessThanOrEqual(
                    pill.maxX, surface.bounds.maxX - AppSpacing.sp5 + 0.5, "pill \(pill) overflows"
                )
                XCTAssertGreaterThanOrEqual(pill.minY, clockFrame.maxY, "pill \(pill) overlaps the clock")
            }
            XCTAssertEqual(Set(pills.map(\.minX)).count, 1, "pills are not stacked at AX5")
            assertNothingClipped(in: cell)
        }
    }

    func testTheCardFollowsALiveCategoryChange() throws {
        let cell = card(.large)
        let clock = try label("07:00", in: cell)
        override(cell, to: Self.ax5)
        layOut(cell, width: narrow)
        XCTAssertGreaterThan(clock.font.pointSize, AppTypography.clockLg.pointSize)
        XCTAssertGreaterThan(fittedHeight(of: cell), todaysCardHeight + 40)
        assertNothingClipped(in: cell)
        override(cell, to: .large)
        layOut(cell, width: narrow)
        XCTAssertEqual(fittedHeight(of: cell), todaysCardHeight, accuracy: 0.01, "did not return to today's card")
        XCTAssertEqual(clock.font.pointSize, AppTypography.clockLg.pointSize)
    }

    /// Flipping the switch re-renders the caps row; it must keep the grown size
    /// and +0.12em tracking, not fall back to the fixed 12pt.
    func testTogglingAtAX5KeepsTheScaledCaps() throws {
        let cell = card(Self.ax5)
        cell.toggleSwitch.isOn = false
        cell.toggleSwitch.sendActions(for: .valueChanged)
        let text = try XCTUnwrap(try label(caps, in: cell).attributedText)
        let font = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let kern = try XCTUnwrap(text.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        XCTAssertGreaterThan(font.pointSize, AppTypography.caps.pointSize)
        XCTAssertEqual(
            kern / font.pointSize, AppTypography.capsKerning / AppTypography.caps.pointSize, accuracy: 0.0001
        )
    }

    /// A self-sizing table re-measures the row when the category changes under it.
    func testAHostedListRowGrowsOnALiveCategoryChange() throws {
        let source = OneCardSource()
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: narrow, height: 800), style: .plain)
        table.register(AlarmCell.self, forCellReuseIdentifier: AlarmCell.reuseID)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 160
        table.dataSource = source
        let window = host(table)
        window.layoutIfNeeded()
        let row = IndexPath(row: 0, section: 0)
        XCTAssertEqual(table.rectForRow(at: row).height, todaysCardHeight, accuracy: 1)

        override(table, to: Self.ax5)
        window.layoutIfNeeded()
        let grown = table.rectForRow(at: row).height
        XCTAssertGreaterThan(grown, todaysCardHeight + 40, "the row kept today's height")
        let cell = try XCTUnwrap(table.cellForRow(at: row))
        XCTAssertEqual(cell.bounds.height, grown, accuracy: 1, "the cell was not resized to its row")
        assertNothingClipped(in: cell)
    }

    /// A table that is already at the largest size when its first row is
    /// dequeued — users with large text on at launch take this path.
    func testAHostedListRowStartingAtAX5IsGrownFromTheFirstLayout() throws {
        let source = OneCardSource()
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: narrow, height: 800), style: .plain)
        table.register(AlarmCell.self, forCellReuseIdentifier: AlarmCell.reuseID)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 160
        table.dataSource = source
        override(table, to: Self.ax5)
        let window = host(table)
        window.layoutIfNeeded()
        let row = IndexPath(row: 0, section: 0)
        let height = table.rectForRow(at: row).height
        XCTAssertGreaterThan(height, todaysCardHeight + 40, "the first layout used today's height")
        let cell = try XCTUnwrap(table.cellForRow(at: row))
        XCTAssertEqual(cell.bounds.height, height, accuracy: 1)
        assertNothingClipped(in: cell)
    }

    /// XL–XXXL: the text grows but is not an accessibility size. On the
    /// narrowest phone the pill row no longer fits, so the pills stack and no
    /// pill wraps mid-word — with the longest real sound names and a 4-digit price.
    func testFromXLThePillsStackAndNothingIsSqueezed() throws {
        for category in [UIContentSizeCategory.extraLarge, .extraExtraLarge, .extraExtraExtraLarge] {
            for sound in ["Размышление", "Своя мелодия", "Колокольчик"] {
                let cell = AlarmCell(style: .default, reuseIdentifier: nil)
                cell.configure(
                    time: "07:00", daysCaps: caps, priceText: "1 000 ₽", priceCurrency: .rub,
                    multiplier: "×2", soundName: sound, enabled: true
                )
                override(cell, to: category)
                layOut(cell, width: narrow)
                let surface = try XCTUnwrap(cell.toggleSwitch.superview)
                let pills = descendants(of: SPPill.self, in: cell).map { $0.convert($0.bounds, to: surface) }
                XCTAssertEqual(pills.count, 3)
                XCTAssertEqual(Set(pills.map(\.minX)).count, 1, "\(category.rawValue) \(sound): pills not stacked")
                for pill in pills {
                    XCTAssertLessThanOrEqual(pill.maxX, surface.bounds.maxX - AppSpacing.sp5 + 0.5)
                }
                assertNothingClipped(in: cell)
            }
        }
    }

    /// At the default size long content still truncates on one line inside
    /// today's 26pt pills, as before #1111 — no pill wraps and grows.
    func testAtTheDefaultSizeLongPillContentStaysOneLine() throws {
        let cell = AlarmCell(style: .default, reuseIdentifier: nil)
        cell.configure(
            time: "07:00", daysCaps: caps, priceText: "1 000 000 ₽", priceCurrency: .rub,
            multiplier: "×2", soundName: "Bach's Badinerie", enabled: true
        )
        override(cell, to: .large)
        layOut(cell, width: narrow)
        let pills = descendants(of: SPPill.self, in: cell)
        XCTAssertEqual(pills.count, 3)
        XCTAssertEqual(Set(pills.map(\.frame.minY)).count, 1, "the pills left their row")
        for pill in pills {
            XCTAssertEqual(pill.frame.height, 26, accuracy: 0.01, "a pill wrapped at the default size")
        }
        XCTAssertEqual(fittedHeight(of: cell), todaysCardHeight, accuracy: 0.01)
    }

    // MARK: - Header

    private func header(
        _ category: UIContentSizeCategory, width: CGFloat? = nil, balance: Decimal = 840,
        hint: String = "Хватит на 16 откладываний"
    ) -> SPAlarmsListHeader {
        let view = SPAlarmsListHeader()
        view.setBalance(balance, currency: .rub, hint: hint, isLow: false)
        override(view, to: category)
        let width = width ?? wide
        view.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        view.frame.size.height = fitted(view, width: width)
        view.layoutIfNeeded()
        return view
    }

    func testAtTheDefaultSizeTheHeaderIsUnchanged() throws {
        let view = header(.large)
        XCTAssertEqual(view.frame.height, todaysHeaderHeight, accuracy: 0.01)
        let title = try label(Localized.text("alarms.title"), in: view)
        XCTAssertEqual(try attributedFont(of: title).pointSize, AppTypography.h1.pointSize)
        XCTAssertEqual(try attributedFont(of: title).fontName, AppTypography.h1.fontName)
        let caps = try label(Localized.text("common.caps.balance"), in: view)
        let amount = try amountLabel(in: view)
        XCTAssertEqual(try attributedFont(of: amount).pointSize, 14)
        XCTAssertEqual(amount.font.pointSize, 14)
        XCTAssertEqual(caps.frame.minY, 12, accuracy: 0.01)
        XCTAssertEqual(amount.frame.minX, caps.frame.maxX + AppSpacing.sp2, accuracy: 0.01, "amount left the caps row")
        XCTAssertEqual(try label("Хватит на 16 откладываний", in: view).font.pointSize, AppTypography.meta.pointSize)
        XCTAssertEqual(view.pillTone, .normal)
    }

    func testAtAX5TheHeaderTextGrowsAndTheAmountMovesUnderTheCaps() throws {
        let regular = header(.large)
        let grown = header(Self.ax5)
        for text in [Localized.text("alarms.title"), Localized.text("common.caps.balance")] {
            let before = try attributedFont(of: label(text, in: regular)).pointSize
            let after = try attributedFont(of: label(text, in: grown)).pointSize
            XCTAssertGreaterThan(after, before, "«\(text)» did not scale")
            XCTAssertLessThanOrEqual(after, before * AppTypography.maximumScale)
        }
        let amountSize = try attributedFont(of: amountLabel(in: grown)).pointSize
        XCTAssertGreaterThan(amountSize, 14, "the amount did not scale")
        XCTAssertLessThanOrEqual(amountSize, 14 * AppTypography.maximumScale)
        let hint = try label("Хватит на 16 откладываний", in: grown)
        XCTAssertGreaterThan(hint.font.pointSize, AppTypography.meta.pointSize)
        XCTAssertFalse(isClipped(hint), "the hint is clipped")
        let caps = try label(Localized.text("common.caps.balance"), in: grown)
        let amount = try amountLabel(in: grown)
        XCTAssertGreaterThanOrEqual(amount.frame.minY, caps.frame.maxY, "the amount still shares the caps row")
        XCTAssertFalse(isClipped(caps), "«БАЛАНС» is clipped")
        XCTAssertFalse(isClipped(amount), "the amount is clipped")
        let title = try label(Localized.text("alarms.title"), in: grown)
        XCTAssertFalse(isClipped(title), "the title is truncated")
        XCTAssertGreaterThan(try drawnPointSize(of: title), AppTypography.h1.pointSize, "the title is drawn at 32pt")
        XCTAssertGreaterThan(grown.frame.height, regular.frame.height, "the header did not grow")
    }

    /// Geometry of the balance pill measured on main (0928c768) for a header
    /// whose balance is set before it reaches a window — the app's cold start.
    /// The amount and the hint used to share the pill's slack arbitrarily, and
    /// the amount drew 1.7pt low on a cold start.
    func testAColdHeaderInAWindowMatchesTodaysPill() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: wide, height: 400))
        window.traitOverrides.preferredContentSizeCategory = .large
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        hostWindows.append(window)
        let view = SPAlarmsListHeader()
        view.setBalance(1000, currency: .rub, hint: "Хватит на ~16 откладываний", isLow: false)
        view.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: window.topAnchor),
            view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])
        window.isHidden = false
        window.layoutIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .large)

        let amount = try XCTUnwrap(
            descendants(of: UILabel.self, in: view).first { $0.attributedText?.string.hasPrefix("1") == true }
        )
        let hint = try label("Хватит на ~16 откладываний", in: view)
        let amountFrame = amount.convert(amount.bounds, to: view)
        let hintFrame = hint.convert(hint.bounds, to: view)
        XCTAssertEqual(view.bounds.height, todaysHeaderHeight, accuracy: 0.01)
        XCTAssertEqual(amountFrame.minY, 73 + 2.0 / 3, accuracy: 0.01, "the amount moved")
        XCTAssertEqual(amountFrame.height, 19 + 1.0 / 3, accuracy: 0.01, "the amount took the pill's slack")
        XCTAssertEqual(hintFrame.minY, 95, accuracy: 0.01, "the hint moved")
        XCTAssertEqual(hintFrame.height, 21, accuracy: 0.01)
    }

    /// From XL the balance row stacks at both widths; at XL–XXXL on the
    /// narrowest phone the one-line hint used to need a 0.59–0.75 shrink
    /// (floor 0.8) and «БАЛАНС» + a five-digit amount overflowed its column.
    func testFromXLTheBalancePillStacksAndNothingIsClipped() throws {
        let hint = "Хватит на ~16 откладываний"
        let categories: [UIContentSizeCategory] = [.extraLarge, .extraExtraLarge, .extraExtraExtraLarge, Self.ax5]
        for category in categories {
            for width in [narrow, wide] {
                let view = header(category, width: width, balance: 12_840, hint: hint)
                let name = "\(category.rawValue) at \(width)"
                let caps = try label(Localized.text("common.caps.balance"), in: view)
                let amount = try XCTUnwrap(
                    descendants(of: UILabel.self, in: view).first { $0.attributedText?.string.hasPrefix("12") == true }
                )
                let hintLabel = try label(hint, in: view)
                let button = try XCTUnwrap(descendants(of: SPButton.self, in: view).first)
                let frame = { (sub: UIView) in sub.convert(sub.bounds, to: view) }
                XCTAssertGreaterThanOrEqual(frame(amount).minY, frame(caps).maxY, "\(name): amount beside the caps")
                XCTAssertGreaterThanOrEqual(
                    frame(hintLabel).minY, frame(button).maxY, "\(name): hint beside the button"
                )
                XCTAssertFalse(frame(amount).intersects(frame(button)), "\(name): amount under the button")
                XCTAssertEqual(caps.numberOfLines, 1)
                for text in [caps, amount, hintLabel] {
                    XCTAssertFalse(isClipped(text), "\(name): «\(text.attributedText?.string ?? "")» clipped")
                }
            }
        }
    }

    // MARK: - Empty state

    /// 620pt is generous: under a grown header the real list area is ~450pt.
    private func emptyState(_ category: UIContentSizeCategory) -> SPAlarmsListEmptyState {
        let view = SPAlarmsListEmptyState()
        override(view, to: category)
        view.frame = CGRect(x: 0, y: 0, width: wide, height: 620)
        view.layoutIfNeeded()
        return view
    }

    func testTheEmptyStateGrowsAtAX5AndIsUnchangedAtTheDefaultSize() throws {
        let title = Localized.text("alarms.empty.title")
        let body = Localized.text("alarms.empty.body")
        let regular = emptyState(.large)
        XCTAssertEqual(try attributedFont(of: label(title, in: regular)).pointSize, AppTypography.h2.pointSize)
        XCTAssertEqual(try label(body, in: regular).font.pointSize, AppTypography.bodyLg.pointSize)
        XCTAssertEqual(try label(body, in: regular).frame.height, todaysEmptyBodyHeight, accuracy: 0.01)

        let grown = emptyState(Self.ax5)
        XCTAssertGreaterThan(try attributedFont(of: label(title, in: grown)).pointSize, AppTypography.h2.pointSize)
        XCTAssertGreaterThan(try label(body, in: grown).font.pointSize, AppTypography.bodyLg.pointSize)
        for text in [title, body] {
            XCTAssertFalse(isClipped(try label(text, in: grown)), "«\(text)» is clipped")
        }
        // Taller than the overlay at AX5, so it scrolls, and the CTA stays
        // inside the scrollable content instead of running under the tab bar.
        let scroll = try XCTUnwrap(descendants(of: UIScrollView.self, in: grown).first)
        let button = try XCTUnwrap(descendants(of: SPButton.self, in: grown).first)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height, "the grown column cannot scroll")
        XCTAssertLessThanOrEqual(button.convert(button.bounds, to: scroll).maxY, scroll.contentSize.height)
        let regularScroll = try XCTUnwrap(descendants(of: UIScrollView.self, in: regular).first)
        XCTAssertEqual(regularScroll.contentSize.height, regularScroll.bounds.height, accuracy: 0.01)
        XCTAssertEqual(
            try label(body, in: regular).convert(CGPoint.zero, to: regular).y, todaysEmptyBodyMinY, accuracy: 0.01,
            "the column moved at the default size"
        )
        // Live: back to the default size restores today's body block.
        override(grown, to: .large)
        grown.layoutIfNeeded()
        XCTAssertEqual(try label(body, in: grown).font.pointSize, AppTypography.bodyLg.pointSize)
        XCTAssertEqual(try label(body, in: grown).frame.height, todaysEmptyBodyHeight, accuracy: 0.01)
        XCTAssertEqual(try attributedFont(of: label(title, in: grown)).pointSize, AppTypography.h2.pointSize)
    }

    // MARK: - Helpers

    private final class OneCardSource: NSObject, UITableViewDataSource {
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: AlarmCell.reuseID, for: indexPath)
            guard let card = cell as? AlarmCell else {
                XCTFail("dequeued \(type(of: cell)), not an AlarmCell")
                return cell
            }
            card.configure(
                time: "07:00", daysCaps: "БУДНИ · ПН–ПТ", priceText: "50 ₽", priceCurrency: .rub,
                multiplier: "×2", soundName: "Soft Dawn", enabled: true
            )
            return card
        }
    }

    private func host(_ view: UIView) -> UIWindow {
        let window = UIWindow(frame: view.frame)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.addSubview(view)
        window.isHidden = false
        hostWindows.append(window)
        return window
    }

    private func override(_ view: UIView, to category: UIContentSizeCategory) {
        view.traitOverrides.preferredContentSizeCategory = category
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, category, "override did not land")
    }

    private func fittedHeight(of cell: UITableViewCell) -> CGFloat {
        cell.layoutIfNeeded()
        return fitted(cell.contentView, width: cell.contentView.bounds.width)
    }

    private func fitted(_ view: UIView, width: CGFloat) -> CGFloat {
        view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func label(_ text: String, in root: UIView) throws -> UILabel {
        try XCTUnwrap(
            descendants(of: UILabel.self, in: root).first { ($0.attributedText?.string ?? $0.text) == text },
            "no label «\(text)»"
        )
    }

    /// The balance amount; `MoneyFormatter` joins it with a narrow no-break space.
    private func amountLabel(in root: UIView) throws -> UILabel {
        try XCTUnwrap(
            descendants(of: UILabel.self, in: root).first { $0.attributedText?.string.hasPrefix("840") == true },
            "no balance amount"
        )
    }

    /// The font the label actually draws — the attributed run's, where one is set.
    private func attributedFont(of label: UILabel) throws -> UIFont {
        let font = label.attributedText.flatMap { text in
            text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil
        }
        return try XCTUnwrap(font ?? label.font)
    }

    /// Measured against unlimited lines at the label's width, not against its
    /// own `numberOfLines` — a capped label would "fit" its truncated text.
    /// A one-line shrink-to-fit label (the clock, the title, the amount) is
    /// clipped only when even its minimum scale overflows the width.
    /// A wrapping label is clipped too when one of its words is wider than the
    /// label: UIKit then breaks it mid-word ("Размышл|ение"), which the height
    /// check alone cannot see.
    private func isClipped(_ label: UILabel) -> Bool {
        if label.numberOfLines == 1 && label.adjustsFontSizeToFitWidth {
            return naturalWidth(of: label) * label.minimumScaleFactor > label.bounds.width + 0.5
        }
        let unlimited = label.textRect(
            forBounds: CGRect(x: 0, y: 0, width: label.bounds.width, height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: 0
        )
        if unlimited.height > label.bounds.height + 0.5 { return true }
        return label.numberOfLines != 1 && widestWord(of: label) > label.bounds.width + 0.5
    }

    private func widestWord(of label: UILabel) -> CGFloat {
        guard let text = label.attributedText, text.length > 0 else { return 0 }
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        return text.string.split(whereSeparator: \.isWhitespace).map { word in
            NSAttributedString(string: String(word), attributes: attributes).size().width
        }.max() ?? 0
    }

    private func naturalWidth(of label: UILabel) -> CGFloat {
        let infinite = CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return label.textRect(forBounds: infinite, limitedToNumberOfLines: 1).width
    }

    /// The point size a shrink-to-fit label actually draws at.
    private func drawnPointSize(of label: UILabel) throws -> CGFloat {
        let scale = min(1, label.bounds.width / naturalWidth(of: label))
        return try attributedFont(of: label).pointSize * scale
    }

    private func assertNothingClipped(in cell: UITableViewCell, file: StaticString = #filePath, line: UInt = #line) {
        let labels = descendants(of: UILabel.self, in: cell.contentView)
            .filter { !$0.isHidden && !($0.attributedText?.string ?? "").isEmpty }
        XCTAssertGreaterThanOrEqual(labels.count, 5, "too few labels to say anything", file: file, line: line)
        for label in labels {
            XCTAssertFalse(
                isClipped(label), "«\(label.attributedText?.string ?? "")» is clipped: \(label.bounds)",
                file: file, line: line
            )
        }
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }
}
