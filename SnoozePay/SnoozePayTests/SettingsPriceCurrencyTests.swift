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
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertEqual(sut.walletCurrencyStore.freeze(usd), .frozen(usd))
        let before = defaults.dictionaryRepresentation() as NSDictionary
        sut.viewWillAppear(false)
        sut.tableView.layoutIfNeeded()
        let refreshed = try XCTUnwrap(sut.tableView.cellForRow(at: indexPath))
        XCTAssertTrue(labels(in: refreshed).contains { $0.text == MoneyFormatter.string(49.5, currency: usd) })
        XCTAssertFalse(labels(in: refreshed).contains { ($0.text ?? "").contains("₽") })
        XCTAssertEqual(sut.makeDefaultPricePicker().actions.first?.title, MoneyFormatter.string(20.0, currency: usd))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
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
