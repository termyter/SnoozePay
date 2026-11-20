import UIKit
import XCTest
@testable import SnoozePay

/// Dynamic Type, wallet slice 1: the Wallet tab — page header, balance card,
/// the 7-day chart's text, the history header and footer (#1111). The
/// transaction rows are `SPRow`, a design-system control, and keep their size.
///
/// Same harness as `AlarmsListDynamicTypeTests`: every measurement sets the
/// category explicitly, so nothing depends on what the simulator is set to.
/// Wallets live on leased suites (`makeIsolatedDefaults`), never `.standard`.
@MainActor
final class WalletDynamicTypeTests: XCTestCase {

    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
    private static let grownCategories: [UIContentSizeCategory] = [.extraLarge, .extraExtraExtraLarge, ax5]
    private let narrow: CGFloat = 375
    private let wide: CGFloat = 402

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true; $0.rootViewController = nil }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Today's geometry

    /// One wallet's screen at `.large`, measured on main (65cd789e) with this
    /// harness at 375 and 402pt; identical at both widths. `y` is in the
    /// scroll content (or the card, for the card's labels), so the device's
    /// safe area does not enter it.
    private struct Today {
        let content: CGFloat
        let card: CGFloat
        let valueHeight: CGFloat
        let deltaY: CGFloat
        let hintY: CGFloat?
        let chartCapsY: CGFloat
        let historyCapsY: CGFloat
        let linkY: CGFloat
        let previewY: CGFloat
        let footerY: CGFloat
    }

    /// 12 840 ₽ credited, 50 ₽ charged: the hint line is shown.
    private let todayRUB = Today(
        content: 685 + 2.0 / 3, card: 212, valueHeight: 76 + 2.0 / 3, deltaY: 133 + 1.0 / 3, hintY: 166,
        chartCapsY: 252, historyCapsY: 384 + 2.0 / 3, linkY: 376, previewY: 420, footerY: 618
    )
    /// $128.50 credited, $1 charged: no price resolves in USD, so no hint.
    private let todayUSD = Today(
        content: 651, card: 177 + 1.0 / 3, valueHeight: 74, deltaY: 130 + 2.0 / 3, hintY: nil,
        chartCapsY: 217 + 1.0 / 3, historyCapsY: 350, linkY: 341 + 1.0 / 3, previewY: 385 + 1.0 / 3,
        footerY: 583 + 1.0 / 3
    )

    // MARK: - Seam

    func testTheWalletRolesAreTheFixedFontsAtTheDefaultSizeAndCappedAtAX5() {
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let grown = UITraitCollection(preferredContentSizeCategory: Self.ax5)
        let roles: [(fixed: UIFont, style: UIFont.TextStyle)] = [
            (AppTypography.moneyXl, .largeTitle), (AppTypography.moneySm, .subheadline),
            (AppTypography.buttonSm, .subheadline), (AppTypography.meta, .footnote)
        ]
        for (fixed, style) in roles {
            let name = "\(fixed.fontName) \(fixed.pointSize)"
            let atLarge = AppTypography.scaled(fixed, as: style, compatibleWith: large)
            XCTAssertEqual(atLarge.pointSize, fixed.pointSize, "\(name) moved at the default size")
            XCTAssertEqual(atLarge.fontName, fixed.fontName, "\(name) changed face")
            XCTAssertEqual(atLarge.lineHeight, fixed.lineHeight, "\(name) changed its line")
            let atAX5 = AppTypography.scaled(fixed, as: style, compatibleWith: grown).pointSize
            XCTAssertGreaterThan(atAX5, fixed.pointSize, "\(name) ignores Dynamic Type")
            XCTAssertLessThanOrEqual(atAX5, fixed.pointSize * AppTypography.maximumScale)
        }
    }

    // MARK: - Screen at the default size

    func testAColdScreenAtTheDefaultSizeMatchesToday() throws {
        let dollar = try usd()
        for width in [narrow, wide] {
            try assertToday(try screen(.rub, width: width, category: .large), today: todayRUB, width: width)
            try assertToday(try screen(dollar, width: width, category: .large), today: todayUSD, width: width)
        }
    }

    // MARK: - Screen at grown sizes

    /// XL, XXXL and AX5 at both widths, for a rouble wallet, a dollar wallet
    /// and an empty one: the text grows (capped), nothing is clipped or broken
    /// mid-word, the history link drops under its caps, the hero number stays
    /// one line at or above today's 42pt floor.
    func testAtGrownSizesTheScreenTextGrowsAndNothingIsClipped() throws {
        let dollar = try usd()
        for category in Self.grownCategories {
            for width in [narrow, wide] {
                for currency in [Currency.rub, dollar] {
                    let name = "\(category.rawValue) \(currency.code) at \(width)"
                    let controller = try screen(currency, width: width, category: category)
                    try assertGrown(controller, name: name)
                }
                let empty = try screen(.rub, width: width, category: category, funded: false)
                try assertGrown(empty, name: "\(category.rawValue) empty at \(width)")
            }
        }
    }

    /// The header's one word shrinks beside the button rather than truncating
    /// or pushing it: the button keeps today's width at every size.
    func testAtAX5TheTitleShrinksBesideAnIntactTopUpButton() throws {
        for width in [narrow, wide] {
            let controller = try screen(.rub, width: width, category: Self.ax5)
            let title = try label(Localized.text("wallet.title"), in: controller.view)
            let button = try XCTUnwrap(descendants(of: SPButton.self, in: controller.view).first)
            let header = try XCTUnwrap(title.superview)
            XCTAssertEqual(title.numberOfLines, 1)
            XCTAssertGreaterThan(try drawnPointSize(of: title), AppTypography.h1.pointSize, "\(width): drawn at 32pt")
            XCTAssertFalse(isClipped(title), "\(width): the title is clipped")
            XCTAssertFalse(title.frame.intersects(button.frame), "\(width): title under the button")
            XCTAssertEqual(button.frame.width, 125 + 1.0 / 3, accuracy: 0.01, "\(width): the button was squeezed")
            XCTAssertEqual(button.frame.maxX, header.bounds.maxX - AppSpacing.screenInset, accuracy: 0.01)
        }
    }

    /// The unreadable-ledger card (#419) replaces the preview; its copy grows
    /// with the rest of the screen and wraps whole words.
    func testTheLedgerErrorCardGrowsWithTheScreen() throws {
        for category in [UIContentSizeCategory.large, Self.ax5] {
            let controller = try screen(.rub, width: narrow, category: category, funded: false)
            let card = controller.makeTxPreviewErrorCard()
            let content = try contentStack(of: controller.view)
            content.addArrangedSubview(card)
            controller.view.window?.layoutIfNeeded()
            let message = try label(Localized.text("wallet.history.load_failed"), in: card)
            if category == .large {
                XCTAssertEqual(message.font.pointSize, AppTypography.body.pointSize)
                XCTAssertEqual(message.font.fontName, AppTypography.body.fontName)
            } else {
                XCTAssertGreaterThan(message.font.pointSize, AppTypography.body.pointSize)
                XCTAssertLessThanOrEqual(message.font.pointSize, AppTypography.body.pointSize * AppTypography.maximumScale)
            }
            XCTAssertFalse(isClipped(message), "\(category.rawValue): the error copy is clipped")
        }
    }

    // MARK: - Live changes and cold starts

    /// `.large` → AX5 → `.large`, with a balance refresh while grown: the
    /// refresh keeps the grown, tinted text and the screen returns to today's
    /// geometry exactly.
    func testTheScreenFollowsALiveCategoryChangeBothWays() throws {
        let controller = try screen(.rub, width: narrow, category: .large)
        let window = try XCTUnwrap(controller.view.window)
        override(window, to: Self.ax5)
        window.layoutIfNeeded()
        try assertGrown(controller, name: "live AX5")
        controller.viewWillAppear(false)
        window.layoutIfNeeded()
        try assertGrown(controller, name: "AX5 after a refresh")
        let delta = try XCTUnwrap(descendants(of: UILabel.self, in: controller.view).first {
            $0.attributedText?.string.hasPrefix("↑") == true
        })
        XCTAssertEqual(
            delta.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
            AppColors.money400, "the refreshed delta lost its tint"
        )
        override(window, to: .large)
        window.layoutIfNeeded()
        try assertToday(controller, today: todayRUB, width: narrow)
    }

    /// Launched at AX5: grown from the first layout, then back to today.
    func testAColdScreenAtAX5IsGrownAndReturnsToTodayLive() throws {
        let dollar = try usd()
        for currency in [Currency.rub, dollar] {
            let controller = try screen(currency, width: wide, category: Self.ax5)
            try assertGrown(controller, name: "cold AX5 \(currency.code)")
            let window = try XCTUnwrap(controller.view.window)
            override(window, to: .large)
            window.layoutIfNeeded()
            try assertToday(controller, today: currency == .rub ? todayRUB : todayUSD, width: wide)
        }
    }

    // MARK: - Balance card

    /// The widest amounts per currency, formatted by `MoneyFormatter`, at every
    /// grown size: one line, never drawn below 42pt, never clipped.
    func testTheHeroNumberStaysOneLineAtOrAboveTodaysFloor() throws {
        let eur = try XCTUnwrap(Currency(code: "EUR"))
        let dollar = try usd()
        let amounts: [(Decimal, Currency)] = [
            (1_234_567, .rub), (12_840, .rub), (128.5, dollar), (1_234.56, eur), (0, .rub)
        ]
        for category in [UIContentSizeCategory.large] + Self.grownCategories {
            for width in [narrow, wide] {
                for (amount, currency) in amounts {
                    let card = balanceCard(amount, currency, category: category, width: width)
                    let value = try XCTUnwrap(descendants(of: SPGradientTextLabel.self, in: card).first)
                    let name = "\(MoneyFormatter.string(amount, currency: currency)) \(category.rawValue) at \(width)"
                    XCTAssertEqual(value.attributedText?.string, MoneyFormatter.string(amount, currency: currency))
                    XCTAssertEqual(value.numberOfLines, 1, name)
                    XCTAssertEqual(
                        value.minimumScaleFactor * value.font.pointSize, SPBalanceCard.valueFloorPointSize,
                        accuracy: 0.001, "\(name): the floor moved"
                    )
                    XCTAssertFalse(isClipped(value), "\(name) is clipped")
                    if category != .large {
                        XCTAssertGreaterThan(value.font.pointSize, AppTypography.moneyXl.pointSize, name)
                    }
                }
            }
        }
    }

    /// From XL the delta and hint wrap between words; the amount inside the
    /// delta is one unbreakable run, and the delta keeps its tint.
    func testFromXLTheDeltaAndHintWrapWithoutSplittingTheAmount() throws {
        let hint = "Хватит на ~16 откладываний при текущей цене"
        for category in Self.grownCategories {
            for (delta, ink) in [(Decimal(1_234_567), AppColors.money400), (Decimal(-12_840), AppColors.pain400)] {
                let card = SPBalanceCard(balance: 12_840, currency: .rub, delta: delta, hint: hint)
                lay(card, category: category, width: narrow)
                let name = "\(category.rawValue) \(delta)"
                let amount = MoneyFormatter.string(abs(delta), currency: .rub)
                let arrow = delta < 0 ? "↓" : "↑"
                let deltaLabel = try XCTUnwrap(descendants(of: UILabel.self, in: card).first {
                    $0.attributedText?.string.hasPrefix(arrow) == true
                }, name)
                XCTAssertTrue(deltaLabel.attributedText?.string.contains(amount) == true, name)
                let hintLabel = try label(hint, in: card)
                XCTAssertEqual(deltaLabel.numberOfLines, 0, name)
                XCTAssertEqual(hintLabel.numberOfLines, 0, name)
                XCTAssertGreaterThan(try attributedFont(of: deltaLabel).pointSize, AppTypography.moneySm.pointSize)
                XCTAssertGreaterThan(hintLabel.font.pointSize, AppTypography.meta.pointSize)
                // `isClipped` splits only at U+0020: the amount's U+00A0/U+202F
                // keep it one word, which must fit the width.
                XCTAssertFalse(isClipped(deltaLabel), "\(name): the delta is clipped or split mid-number")
                XCTAssertFalse(isClipped(hintLabel), "\(name): the hint is clipped")
                XCTAssertEqual(
                    deltaLabel.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, ink
                )
            }
        }
    }

    /// AX5 → `.large` and back on one card, with an `update` in between: the
    /// update renders at the current size, and `.large` is today's card.
    func testTheCardFollowsALiveChangeAndAnUpdateKeepsItsSize() throws {
        let card = balanceCard(12_840, .rub, category: Self.ax5, width: narrow)
        card.update(balance: 12_790, currency: .rub, delta: 1_200, hint: "Хватит на ~16 откладываний")
        lay(card, category: Self.ax5, width: narrow)
        let caps = try label(Localized.text("common.caps.balance"), in: card)
        let capsText = try XCTUnwrap(caps.attributedText)
        let capsFont = try attributedFont(of: caps)
        let kern = try XCTUnwrap(capsText.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        XCTAssertGreaterThan(capsFont.pointSize, AppTypography.caps.pointSize)
        XCTAssertEqual(
            kern / capsFont.pointSize, AppTypography.capsKerning / AppTypography.caps.pointSize, accuracy: 0.0001
        )
        let value = try XCTUnwrap(descendants(of: SPGradientTextLabel.self, in: card).first)
        XCTAssertGreaterThan(value.font.pointSize, AppTypography.moneyXl.pointSize, "update reset the hero font")

        lay(card, category: .large, width: narrow)
        XCTAssertEqual(card.bounds.height, todayRUB.card, accuracy: 0.01, "not today's card after AX5")
        XCTAssertEqual(try attributedFont(of: caps).pointSize, AppTypography.caps.pointSize)
        XCTAssertEqual(
            caps.attributedText?.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat, AppTypography.capsKerning
        )
        XCTAssertEqual(value.font.pointSize, AppTypography.moneyXl.pointSize)
        XCTAssertEqual(value.minimumScaleFactor, 0.75)
    }

    // MARK: - Chart

    /// The day initials grow and their row grows with them; the bars keep
    /// today's heights. The chart stays 80pt until a 2× row needs 2pt more.
    func testTheChartInitialsGrowAndTheBarsKeepTheirGeometry() throws {
        let values: [Decimal] = [0, 50, 0, 650, 0, 0, 100]
        // Bar (minY, height) and the initial's row, measured on main (65cd789e).
        let todaysBars: [(CGFloat, CGFloat)] = [(56, 4), (50, 10), (56, 4), (20, 40), (56, 4), (56, 4), (50, 10)]
        let regular = chart(values, category: .large)
        let regularColumns = columns(of: regular)
        XCTAssertEqual(regularColumns.count, 7)
        XCTAssertEqual(regular.bounds.height, 80)
        for (column, today) in zip(regularColumns, todaysBars) {
            XCTAssertEqual(column.bar.minY, today.0, accuracy: 0.01)
            XCTAssertEqual(column.bar.height, today.1, accuracy: 0.01)
            XCTAssertEqual(column.initial.frame.minY, 66, accuracy: 0.01)
            XCTAssertEqual(column.initial.frame.height, 14, accuracy: 0.01)
            XCTAssertEqual(column.initial.font.pointSize, AppTypography.meta.pointSize)
        }

        for category in Self.grownCategories {
            let grown = chart(values, category: category)
            let rowHeight = ceil(try XCTUnwrap(columns(of: grown).first).initial.font.lineHeight)
            XCTAssertEqual(grown.bounds.height, max(80, 40 + 6 + rowHeight), accuracy: 0.01, category.rawValue)
            for (column, today) in zip(columns(of: grown), todaysBars) {
                let font = column.initial.font!
                XCTAssertGreaterThan(font.pointSize, AppTypography.meta.pointSize, category.rawValue)
                XCTAssertLessThanOrEqual(font.pointSize, AppTypography.meta.pointSize * AppTypography.maximumScale)
                XCTAssertEqual(column.initial.frame.height, ceil(font.lineHeight), accuracy: 0.01, "row ≠ its line")
                XCTAssertEqual(column.bar.height, today.1, accuracy: 0.01, "\(category.rawValue): a bar changed")
                XCTAssertGreaterThanOrEqual(column.bar.minY, 0, "\(category.rawValue): a bar left the chart")
                XCTAssertEqual(column.initial.frame.maxY, grown.bounds.maxY, accuracy: 0.01)
            }
        }
    }

    // MARK: - Fixtures

    private func usd() throws -> Currency { try XCTUnwrap(Currency(code: "USD")) }

    /// A wallet whose currency is frozen by its first payment (12 840 ₽ or
    /// $128.50), with one small charge — or an untouched, empty wallet.
    private func screen(
        _ currency: Currency, width: CGFloat, category: UIContentSizeCategory, funded: Bool = true
    ) throws -> WalletViewController {
        let defaults = makeIsolatedDefaults()
        let center = NotificationCenter()
        let ledger = TransactionRepository(defaults: defaults)
        let wallet = BalanceService(
            defaults: defaults, transactionRepository: ledger, notificationCenter: center,
            priceScaleStore: SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        )
        if funded {
            let amount = currency == .rub ? 12_840 : 128.5
            XCTAssertEqual(wallet.topUpFromPurchase(amount: amount, currency: currency), .credited)
            XCTAssertTrue(wallet.charge(amount: currency == .rub ? 50 : 1, alarmID: nil))
        }
        let controller = WalletViewController(
            balanceService: wallet, transactionRepository: ledger,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler()),
            alarmDefaults: AlarmDefaults(defaults: defaults)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1400))
        window.traitOverrides.preferredContentSizeCategory = category
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        hostWindows.append(window)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        XCTAssertEqual(controller.view.traitCollection.preferredContentSizeCategory, category)
        return controller
    }

    private func balanceCard(
        _ balance: Decimal, _ currency: Currency, category: UIContentSizeCategory, width: CGFloat
    ) -> SPBalanceCard {
        let card = SPBalanceCard(balance: balance, currency: currency, delta: 1_200, hint: "Хватит на ~16 откладываний")
        lay(card, category: category, width: width)
        return card
    }

    /// The card at a phone's width inside the screen's 16pt margins.
    private func lay(_ card: SPBalanceCard, category: UIContentSizeCategory, width: CGFloat) {
        override(card, to: category)
        let cardWidth = width - 2 * AppSpacing.screenInset
        card.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 300)
        card.frame.size.height = fitted(card, width: cardWidth)
        card.layoutIfNeeded()
    }

    /// The chart as the screen sizes it: 80pt, or taller if its text needs it.
    private func chart(_ values: [Decimal], category: UIContentSizeCategory) -> WalletWeeklyChartView {
        let chart = WalletWeeklyChartView()
        chart.update(values: values)
        override(chart, to: category)
        let width = narrow - 2 * AppSpacing.screenInset
        chart.frame = CGRect(x: 0, y: 0, width: width, height: max(80, fitted(chart, width: width)))
        chart.layoutIfNeeded()
        return chart
    }

    /// Each day: its bar (in chart coordinates) and its initial.
    private func columns(of chart: WalletWeeklyChartView) -> [(bar: CGRect, initial: UILabel)] {
        let stack = chart.subviews.compactMap { $0 as? UIStackView }.first
        return (stack?.arrangedSubviews ?? []).compactMap { column in
            guard let initial = column.subviews.compactMap({ $0 as? UILabel }).first,
                  let bar = column.subviews.first(where: { !($0 is UILabel) }) else { return nil }
            return (bar.convert(bar.bounds, to: chart), initial)
        }
    }

    // MARK: - Assertions

    private func assertToday(
        _ controller: WalletViewController, today: Today, width: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let view = controller.view!
        let name = "\(width)"
        let check = { (actual: CGFloat, expected: CGFloat, what: String) in
            XCTAssertEqual(actual, expected, accuracy: 0.01, "\(name): \(what) moved", file: file, line: line)
        }
        let title = try label(Localized.text("wallet.title"), in: view)
        let header = try XCTUnwrap(title.superview)
        let button = try XCTUnwrap(descendants(of: SPButton.self, in: header).first)
        check(header.bounds.height, 68, "header height")
        check(title.frame.minX, 16, "title x")
        check(title.frame.minY, 8, "title y")
        check(title.frame.width, 140, "title width")
        check(title.frame.height, 44, "title height")
        check(button.frame.minY, 12, "button y")
        check(button.frame.width, 125 + 1.0 / 3, "button width")
        check(button.frame.maxX, width - 16, "button trailing")
        XCTAssertEqual(try attributedFont(of: title).pointSize, AppTypography.h1.pointSize, file: file, line: line)

        let content = try contentStack(of: view)
        let inContent = { (sub: UIView) in sub.convert(sub.bounds, to: content) }
        check(content.bounds.height, today.content, "content height")
        let card = try XCTUnwrap(descendants(of: SPBalanceCard.self, in: content).first)
        check(inContent(card).minY, 16, "card y")
        check(card.bounds.height, today.card, "card height")
        let inCard = { (sub: UIView) in sub.convert(sub.bounds, to: card) }
        let caps = try label(Localized.text("common.caps.balance"), in: card)
        check(inCard(caps).minY, 28, "«БАЛАНС» y")
        check(inCard(caps).height, 16 + 2.0 / 3, "«БАЛАНС» height")
        let value = try XCTUnwrap(descendants(of: SPGradientTextLabel.self, in: card).first)
        check(inCard(value).minY, 52 + 2.0 / 3, "value y")
        check(inCard(value).height, today.valueHeight, "value height")
        XCTAssertEqual(value.font.pointSize, AppTypography.moneyXl.pointSize, file: file, line: line)
        let delta = try XCTUnwrap(visibleLabels(in: card).first { $0.attributedText?.string.hasPrefix("↑") == true })
        check(inCard(delta).minY, today.deltaY, "delta y")
        check(inCard(delta).height, 18 + 2.0 / 3, "delta height")
        let hint = visibleLabels(in: card).filter { $0 !== caps && $0 !== value && $0 !== delta }
        if let hintY = today.hintY {
            XCTAssertEqual(hint.count, 1, "\(name): no hint line", file: file, line: line)
            check(hint.first.map { inCard($0).minY } ?? -1, hintY, "hint y")
            check(hint.first?.bounds.height ?? -1, 18, "hint height")
        } else {
            XCTAssertTrue(hint.isEmpty, "\(name): unexpected hint", file: file, line: line)
        }

        let chartCaps = try label(Localized.text("wallet.chart.caps"), in: content)
        check(inContent(chartCaps).minY, today.chartCapsY, "chart caps y")
        check(chartCaps.bounds.height, 16 + 2.0 / 3, "chart caps height")
        let chart = try XCTUnwrap(descendants(of: WalletWeeklyChartView.self, in: content).first)
        check(inContent(chart).minY, today.chartCapsY + 28 + 2.0 / 3, "chart y")
        check(chart.bounds.height, 80, "chart height")
        for column in columns(of: chart) {
            check(column.initial.frame.minY, 66, "day initial y")
            check(column.initial.frame.height, 14, "day initial height")
        }

        let historyCaps = try label(Localized.text("wallet.history.caps"), in: content)
        check(inContent(historyCaps).minY, today.historyCapsY, "history caps y")
        check(historyCaps.bounds.width, 149 + 2.0 / 3, "history caps width")
        check(historyCaps.bounds.height, 16 + 2.0 / 3, "history caps height")
        let link = try XCTUnwrap(descendants(of: UIButton.self, in: content).first)
        check(inContent(link).minY, today.linkY, "link y")
        check(inContent(link).maxX, width - 16, "link trailing")
        check(link.bounds.width, 114, "link width")
        check(link.bounds.height, 32, "link height")
        let preview = try XCTUnwrap(descendants(of: SPCard.self, in: content).first)
        check(inContent(preview).minY, today.previewY, "preview card y")
        check(preview.bounds.height, 174, "preview card height")
        let footer = try label(Localized.text("wallet.footer.disclaimer"), in: content)
        check(inContent(footer).minY, today.footerY, "footer y")
        check(footer.bounds.height, 35 + 2.0 / 3, "footer height")
        XCTAssertEqual(footer.font.pointSize, AppTypography.meta.pointSize, file: file, line: line)
    }

    private func assertGrown(
        _ controller: WalletViewController, name: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let view = controller.view!
        let content = try contentStack(of: view)
        let grownTexts = [
            Localized.text("wallet.title"), Localized.text("common.caps.balance"), Localized.text("wallet.chart.caps"),
            Localized.text("wallet.history.caps"), Localized.text("wallet.history.link_all"),
            Localized.text("wallet.footer.disclaimer")
        ]
        let fixedSizes = [
            AppTypography.h1, AppTypography.caps, AppTypography.caps, AppTypography.caps, AppTypography.buttonSm,
            AppTypography.meta
        ].map(\.pointSize)
        for (text, fixed) in zip(grownTexts, fixedSizes) {
            let size = try attributedFont(of: label(text, in: view)).pointSize
            XCTAssertGreaterThan(size, fixed, "\(name): «\(text)» did not grow", file: file, line: line)
            XCTAssertLessThanOrEqual(size, fixed * AppTypography.maximumScale, "\(name): «\(text)»", file: file, line: line)
        }
        let card = try XCTUnwrap(descendants(of: SPBalanceCard.self, in: content).first)
        let value = try XCTUnwrap(descendants(of: SPGradientTextLabel.self, in: card).first)
        XCTAssertGreaterThan(value.font.pointSize, AppTypography.moneyXl.pointSize, name, file: file, line: line)
        XCTAssertEqual(value.numberOfLines, 1, name, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            value.minimumScaleFactor * value.font.pointSize + 0.001, SPBalanceCard.valueFloorPointSize,
            "\(name): the hero may shrink below today's floor", file: file, line: line
        )
        for card in [card as UIView] + descendants(of: SPCard.self, in: content) {
            XCTAssertLessThanOrEqual(
                card.convert(card.bounds, to: content).maxX, content.bounds.maxX - AppSpacing.screenInset + 0.5,
                "\(name): a card left the screen", file: file, line: line
            )
        }
        for day in columns(of: try XCTUnwrap(descendants(of: WalletWeeklyChartView.self, in: content).first)) {
            XCTAssertGreaterThan(day.initial.font.pointSize, AppTypography.meta.pointSize, name, file: file, line: line)
            XCTAssertGreaterThanOrEqual(day.bar.minY, 0, "\(name): a bar left the chart", file: file, line: line)
        }

        let historyCaps = try label(Localized.text("wallet.history.caps"), in: content)
        let link = try XCTUnwrap(descendants(of: UIButton.self, in: content).first)
        let inContent = { (sub: UIView) in sub.convert(sub.bounds, to: content) }
        XCTAssertGreaterThanOrEqual(
            inContent(link).minY + 0.01, inContent(historyCaps).maxY, "\(name): the link still shares the caps row",
            file: file, line: line
        )
        XCTAssertEqual(inContent(link).minX, AppSpacing.screenInset, accuracy: 0.01, name, file: file, line: line)

        let title = try label(Localized.text("wallet.title"), in: view)
        let button = try XCTUnwrap(descendants(of: SPButton.self, in: view).first)
        XCTAssertFalse(title.frame.intersects(button.frame), "\(name): title under the button", file: file, line: line)

        let labels = visibleLabels(in: view)
        XCTAssertGreaterThanOrEqual(labels.count, 15, "\(name): too few labels to say anything", file: file, line: line)
        for label in labels {
            XCTAssertFalse(
                isClipped(label), "\(name): «\(label.attributedText?.string ?? "")» is clipped: \(label.bounds)",
                file: file, line: line
            )
        }
    }

    // MARK: - Harness (as in `AlarmsListDynamicTypeTests`)

    private func override(_ view: UIView, to category: UIContentSizeCategory) {
        view.traitOverrides.preferredContentSizeCategory = category
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, category, "override did not land")
    }

    private func fitted(_ view: UIView, width: CGFloat) -> CGFloat {
        view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func contentStack(of view: UIView) throws -> UIStackView {
        let scroll = try XCTUnwrap(descendants(of: UIScrollView.self, in: view).first)
        return try XCTUnwrap(scroll.subviews.compactMap { $0 as? UIStackView }.first)
    }

    private func label(_ text: String, in root: UIView) throws -> UILabel {
        try XCTUnwrap(
            descendants(of: UILabel.self, in: root).first { ($0.attributedText?.string ?? $0.text) == text },
            "no label «\(text)»"
        )
    }

    private func visibleLabels(in root: UIView) -> [UILabel] {
        descendants(of: UILabel.self, in: root).filter { label in
            !label.isHidden && !(label.attributedText?.string ?? "").isEmpty
                && sequence(first: label as UIView, next: \.superview).allSatisfy { !$0.isHidden }
        }
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
    /// A one-line shrink-to-fit label (the title, the hero number) is clipped
    /// only when even its minimum scale overflows the width. A wrapping label
    /// is clipped too when one of its words is wider than the label: UIKit
    /// then breaks it mid-word, which the height check alone cannot see.
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
        // Only where UIKit may break a line: the amount's U+202F and U+00A0
        // keep "12 840 ₽" one unbreakable word.
        return text.string.split(whereSeparator: { $0 == " " || $0.isNewline }).map { word in
            NSAttributedString(string: String(word), attributes: attributes).size().width
        }.max() ?? 0
    }

    private func naturalWidth(of label: UILabel) -> CGFloat {
        let infinite = CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return label.textRect(forBounds: infinite, limitedToNumberOfLines: 1).width
    }

    /// The point size a shrink-to-fit label actually draws at.
    private func drawnPointSize(of label: UILabel) throws -> CGFloat {
        let scale = max(label.minimumScaleFactor, min(1, label.bounds.width / naturalWidth(of: label)))
        return try attributedFont(of: label).pointSize * scale
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }
}
