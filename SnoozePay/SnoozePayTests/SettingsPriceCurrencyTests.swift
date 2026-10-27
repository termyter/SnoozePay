import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class SettingsPriceCurrencyTests: XCTestCase {
    func testActualDefaultPriceRowAndNativePickerUseWalletCurrency() throws {
        for code in ["RUB", "USD", "EUR", "KWD"] {
            let currency = try XCTUnwrap(Currency(code: code))
            let (sut, defaults) = makeSUT(currency: currency)
            let before = defaults.dictionaryRepresentation() as NSDictionary
            let cell = sut.makeFinanceCell(at: priceIndexPath(in: sut))
            let text = MoneyFormatter.string(49.5, currency: currency)
            XCTAssertTrue(labels(in: cell).contains { $0.text == text }, code)
            XCTAssertTrue(text.contains("49,5"), text)
            if currency != .rub { XCTAssertFalse(text.contains("₽"), text) }
            let icon = try XCTUnwrap(descendants(in: cell).compactMap { $0 as? UIImageView }.first)
            let expectedIcon = UIImage(systemName: currency == .rub ? "rublesign.circle" : "banknote")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
            XCTAssertEqual(icon.image?.pngData(), try XCTUnwrap(expectedIcon).pngData(), code)
            XCTAssertEqual(cell.accessoryType, .disclosureIndicator)

            let picker = sut.makeDefaultPricePicker()
            XCTAssertEqual(picker.preferredStyle, .actionSheet)
            XCTAssertEqual(picker.actions.count, 6)
            XCTAssertEqual(picker.actions.prefix(5).map(\.title), [20, 50, 100, 200, 500].map {
                MoneyFormatter.string(Double($0), currency: currency)
            })
            XCTAssertTrue(picker.actions.prefix(5).allSatisfy { $0.style == .default })
            XCTAssertEqual(picker.actions.last?.style, .cancel)
            XCTAssertEqual(picker.message, Localized.text("settings.picker.applies_to_new_alarms"))
            if let popover = picker.popoverPresentationController {
                XCTAssertTrue(popover.sourceView === sut.tableView)
                XCTAssertEqual(popover.sourceRect, sut.tableView.rectForRow(at: priceIndexPath(in: sut)))
            }
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, 49.5)
        }
    }

    private struct PriceCase {
        let code: String
        let amount: Double
        let digits: String
    }

    func testRowPreservesThreeMinorUnitsAndExactLargeIntegerWithoutWritingDefaults() {
        let cases = [
            PriceCase(code: "KWD", amount: 1.001, digits: "1,001"),
            PriceCase(code: "USD", amount: 18_446_744_073_709_551_616,
                      digits: "18\u{00A0}446\u{00A0}744\u{00A0}073\u{00A0}709\u{00A0}551\u{00A0}616")
        ]
        for item in cases {
            let (code, amount, digits) = (item.code, item.amount, item.digits)
            let (sut, defaults) = makeSUT(currency: Currency(code: code)!, amount: amount)
            let before = defaults.dictionaryRepresentation() as NSDictionary
            let cell = sut.makeFinanceCell(at: priceIndexPath(in: sut))
            let text = MoneyFormatter.string(amount, currency: sut.walletCurrencyStore.currency)
            XCTAssertTrue(labels(in: cell).contains { $0.text == text }, code)
            XCTAssertTrue(text.contains(digits), text)
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, amount)
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
    }

    func testViewWillAppearReloadsMountedPriceAfterCurrencyIsEstablished() throws {
        let (sut, defaults) = makeSUT(currency: nil)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        sut.tableView.layoutIfNeeded()
        let indexPath = priceIndexPath(in: sut)
        let initial = try XCTUnwrap(sut.tableView.cellForRow(at: indexPath))
        XCTAssertTrue(labels(in: initial).contains { $0.text == MoneyFormatter.string(49.5, currency: .rub) })
        let initialRules = try XCTUnwrap(sut.tableView.cellForRow(at: rulesIndexPath(in: sut)))
        XCTAssertEqual(try previewLabel(in: initialRules).text,
                       formattedChain([49.5, 99, 198, 396], currency: .rub))
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertEqual(sut.walletCurrencyStore.freeze(usd), .frozen(usd))
        let before = defaults.dictionaryRepresentation() as NSDictionary
        sut.viewWillAppear(false)
        sut.tableView.layoutIfNeeded()
        let refreshed = try XCTUnwrap(sut.tableView.cellForRow(at: indexPath))
        XCTAssertTrue(labels(in: refreshed).contains { $0.text == MoneyFormatter.string(49.5, currency: usd) })
        XCTAssertFalse(labels(in: refreshed).contains { ($0.text ?? "").contains("₽") })
        let refreshedRules = try XCTUnwrap(sut.tableView.cellForRow(at: rulesIndexPath(in: sut)))
        XCTAssertEqual(try previewLabel(in: refreshedRules).text,
                       formattedChain([49.5, 99, 198, 396], currency: usd))
        XCTAssertEqual(sut.makeDefaultPricePicker().actions.first?.title, MoneyFormatter.string(20.0, currency: usd))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }

    private let progressiveCases: [(base: Double, steps: [Double])] = [
        (20, [20, 40, 80, 160]),
        (50, [50, 100, 200, 400]),
        (100, [100, 200, 400, 800]),
        (200, [200, 400, 800, 1600]),
        (500, [500, 1000, 2000, 4000])
    ]

    func testRulesPreviewUsesSelectedBaseAndWalletCurrencyWithoutWritingDefaults() throws {
        for code in ["RUB", "USD", "KWD"] {
            let currency = try XCTUnwrap(Currency(code: code))
            for item in progressiveCases {
                let (sut, defaults) = makeSUT(currency: currency, amount: item.base)
                sut.alarmDefaults.progressiveScale = true
                let before = defaults.dictionaryRepresentation() as NSDictionary
                let cell = sut.makeRulesCell(at: rulesIndexPath(in: sut))
                XCTAssertEqual(try previewLabel(in: cell).text, formattedChain(item.steps, currency: currency))
                XCTAssertEqual(try previewLabel(in: cell).text?.components(separatedBy: " → ").count, 4)
                XCTAssertEqual(sut.alarmDefaults.penaltyAmount, item.base)
                XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            }
        }
    }

    func testRulesPreviewPreservesThreeMinorUnits() throws {
        let currency = try XCTUnwrap(Currency(code: "KWD"))
        let (sut, _) = makeSUT(currency: currency, amount: 1.001)
        let cell = sut.makeRulesCell(at: rulesIndexPath(in: sut))
        XCTAssertEqual(try previewLabel(in: cell).text,
                       formattedChain([1.001, 2.002, 4.004, 8.008], currency: currency))
        XCTAssertTrue(try XCTUnwrap(previewLabel(in: cell).text).contains("1,001"))
    }

    func testSelectingDefaultPriceImmediatelyReloadsBothMountedRows() throws {
        let currency = try XCTUnwrap(Currency(code: "USD"))
        let (sut, _) = makeSUT(currency: currency, amount: 50)
        sut.alarmDefaults.progressiveScale = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        sut.tableView.layoutIfNeeded()
        let initial = try XCTUnwrap(sut.tableView.cellForRow(at: rulesIndexPath(in: sut)))
        XCTAssertEqual(try previewLabel(in: initial).text, formattedChain([50, 100, 200, 400], currency: currency))

        for item in progressiveCases {
            // This is the production picker action's commit, not a test-only
            // defaults write followed by a reload supplied by the test.
            sut.applyDefaultPrice(item.base)
            sut.tableView.layoutIfNeeded()
            let price = try XCTUnwrap(sut.tableView.cellForRow(at: priceIndexPath(in: sut)))
            XCTAssertTrue(labels(in: price).contains {
                $0.text == MoneyFormatter.string(item.base, currency: currency)
            })
            let rules = try XCTUnwrap(sut.tableView.cellForRow(at: rulesIndexPath(in: sut)))
            XCTAssertEqual(try previewLabel(in: rules).text, formattedChain(item.steps, currency: currency))
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, item.base)
            XCTAssertTrue(sut.alarmDefaults.progressiveScale)
        }
    }

    func testDisabledProgressiveRuleStillExplainsTheLadderAndToggleOnlyChangesItsFlag() throws {
        let (sut, _) = makeSUT(currency: .rub, amount: 200)
        let cell = sut.makeRulesCell(at: rulesIndexPath(in: sut))
        let toggle = try XCTUnwrap(descendants(in: cell).compactMap { $0 as? SPSwitch }.first)
        XCTAssertFalse(toggle.isOn)
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertFalse(try previewLabel(in: cell).isHidden)
        let expected = formattedChain([200, 400, 800, 1600], currency: .rub)
        XCTAssertEqual(try previewLabel(in: cell).text, expected)

        for enabled in [true, false] {
            toggle.isOn = enabled
            toggle.sendActions(for: .valueChanged)
            XCTAssertEqual(sut.alarmDefaults.progressiveScale, enabled)
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, 200)
            XCTAssertEqual(try previewLabel(in: cell).text, expected)
            XCTAssertFalse(try previewLabel(in: cell).isHidden)
        }
    }

    func testLongCurrencyPreviewFitsTheSelfSizingRowInBothThemes() throws {
        for code in ["RUB", "USD", "KWD"] {
            let currency = try XCTUnwrap(Currency(code: code))
            for style in [UIUserInterfaceStyle.light, .dark] {
                let (sut, _) = makeSUT(currency: currency, amount: 500)
                let indexPath = rulesIndexPath(in: sut)
                XCTAssertEqual(sut.tableView(sut.tableView, heightForRowAt: indexPath), UITableView.automaticDimension)
                let cell = sut.makeRulesCell(at: indexPath)
                cell.overrideUserInterfaceStyle = style
                cell.frame = CGRect(x: 0, y: 0, width: 320, height: SettingsIconRowCell.minimumRowHeight)
                cell.layoutIfNeeded()
                cell.frame.size.height = cell.contentView.systemLayoutSizeFitting(
                    CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                ).height
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                let preview = try previewLabel(in: cell)
                let needed = preview.sizeThatFits(CGSize(width: preview.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertGreaterThan(preview.bounds.width, 0)
                XCTAssertGreaterThanOrEqual(preview.bounds.height, needed.height - 0.5)
                XCTAssertLessThanOrEqual(preview.convert(preview.bounds, to: cell.contentView).maxY,
                                         cell.contentView.bounds.height + 0.5)
                XCTAssertFalse(preview.isHidden)
                XCTAssertEqual(preview.textColor.resolvedColor(with: preview.traitCollection),
                               AppColors.fg3.resolvedColor(with: preview.traitCollection))
            }
        }
    }

    private func formattedChain(_ amounts: [Double], currency: Currency) -> String {
        amounts.map { MoneyFormatter.string($0, currency: currency) }.joined(separator: " → ")
    }

    private func rulesIndexPath(in sut: SettingsViewController) -> IndexPath {
        IndexPath(row: 0, section: sut.visibleSections.firstIndex(of: .rules)!)
    }

    private func previewLabel(in view: UIView) throws -> UILabel {
        try XCTUnwrap(labels(in: view).first { $0.text?.contains(" → ") == true })
    }

    private func makeSUT(
        currency: Currency?, amount: Double = 49.5
    ) -> (SettingsViewController, UserDefaults) {
        let suite = "test.settings.priceCurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let currencyStore = WalletCurrencyStore(defaults: defaults)
        if let currency { XCTAssertEqual(currencyStore.freeze(currency), .frozen(currency)) }
        let alarmDefaults = AlarmDefaults(defaults: defaults)
        alarmDefaults.penaltyAmount = amount
        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        let sut = SettingsViewController(
            themeService: ThemeService(defaults: defaults),
            alarmDefaults: alarmDefaults,
            referralService: ReferralService(defaults: defaults, balanceService: wallet),
            walletCurrencyStore: currencyStore
        )
        sut.loadViewIfNeeded()
        return (sut, defaults)
    }

    private func priceIndexPath(in sut: SettingsViewController) -> IndexPath {
        IndexPath(row: SettingsViewController.FinanceRow.defaultPrice.rawValue,
                  section: sut.visibleSections.firstIndex(of: .finance)!)
    }

    private func labels(in view: UIView) -> [UILabel] {
        descendants(in: view).compactMap { $0 as? UILabel }
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
