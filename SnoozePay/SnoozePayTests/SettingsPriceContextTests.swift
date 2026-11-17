import UIKit
import XCTest
@testable import SnoozePay

/// Settings quotes the default snooze price in the wallet's price context
/// (#1147): roubles exactly as before, a cached scale as the legacy amount's
/// tier, an unavailable scale as "—". Every screen here is fed a fixed context
/// through the injected source — never the app's wallet.
@MainActor
final class SettingsPriceContextTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private var usdScale: SnoozePriceScale {
        SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])!
    }

    func testRoubleContextRendersRowAndLadderLikeTheLegacyFormatter() throws {
        let ladders: [(amount: Double, steps: [Double])] = [
            (50, [50, 100, 200, 400]), (100, [100, 200, 400, 800]),
            (137, [137, 274, 548, 1096]), (500, [500, 1000, 2000, 4000])
        ]
        for item in ladders {
            let sut = makeSUT(amount: item.amount) { .scale(.rouble) }
            let row = sut.makeFinanceCell(at: priceIndexPath(in: sut))
            XCTAssertTrue(labels(in: row).contains { $0.text == MoneyFormatter.string(item.amount, currency: .rub) })
            let rules = sut.makeRulesCell(at: rulesIndexPath(in: sut))
            let chain = item.steps.map { MoneyFormatter.string($0, currency: .rub) }.joined(separator: " → ")
            XCTAssertTrue(labels(in: rules).contains { $0.text == chain }, "\(item.amount)")
        }
    }

    func testUSDScaleQuotesTheTierTheLegacyAmountMapsTo() throws {
        for (amount, tier) in [(50.0, "0.99"), (100, "1.99"), (137, "2.99"), (500, "2.99")] {
            let sut = makeSUT(amount: amount) { .scale(self.usdScale) }
            let row = sut.makeFinanceCell(at: priceIndexPath(in: sut))
            let text = MoneyFormatter.string(decimal(tier), currency: usd)
            XCTAssertTrue(labels(in: row).contains { $0.text == text }, "\(amount) → \(text)")
            XCTAssertFalse(labels(in: row).contains { ($0.text ?? "").contains("₽") })
            // The fixture's wallet store says roubles; the icon follows the
            // context, not the store.
            XCTAssertEqual(sut.walletCurrencyStore.currency, .rub)
            let icon = try XCTUnwrap(descendants(in: row).compactMap { $0 as? UIImageView }.first)
            let banknote = try XCTUnwrap(UIImage(systemName: "banknote")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)))
            XCTAssertEqual(icon.image?.pngData(), banknote.pngData(), "\(amount)")
        }
        let sut = makeSUT(amount: 50) { .scale(self.usdScale) }
        let rules = sut.makeRulesCell(at: rulesIndexPath(in: sut))
        let chain = ["0.99", "1.98", "3.96", "7.92"]
            .map { MoneyFormatter.string(decimal($0), currency: usd) }.joined(separator: " → ")
        XCTAssertTrue(labels(in: rules).contains { $0.text == chain })
    }

    func testUnavailableContextShowsNoNumber() throws {
        let sut = makeSUT(amount: 50) { .unavailable(self.usd) }
        let row = sut.makeFinanceCell(at: priceIndexPath(in: sut))
        XCTAssertTrue(labels(in: row).contains { $0.text == "—" })
        XCTAssertFalse(labels(in: row).contains { $0.text?.rangeOfCharacter(from: .decimalDigits) != nil })
        let rules = sut.makeRulesCell(at: rulesIndexPath(in: sut))
        XCTAssertTrue(labels(in: rules).contains { $0.text == "—" })
        XCTAssertFalse(labels(in: rules).contains { $0.text?.rangeOfCharacter(from: .decimalDigits) != nil })
    }

    func testMountedRowReQuotesOnScaleAndWalletCurrencyNotifications() throws {
        var context = SnoozePriceContext.scale(.rouble)
        let center = NotificationCenter()
        let sut = makeSUT(amount: 50, center: center) { context }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        XCTAssertTrue(rowShows(MoneyFormatter.string(50.0, currency: .rub), in: sut))

        context = .scale(usdScale)
        center.post(name: SnoozePriceScaleStore.snoozePriceScaleChangedNotification, object: nil)
        waitForRow(MoneyFormatter.string(decimal("0.99"), currency: usd), in: sut)

        context = .unavailable(usd)
        center.post(name: BalanceService.walletCurrencyChangedNotification, object: nil)
        waitForRow("—", in: sut)

        // A first balance move ends a pristine wallet's storefront context.
        context = .scale(.rouble)
        center.post(name: BalanceService.balanceChangedNotification, object: nil)
        waitForRow(MoneyFormatter.string(50.0, currency: .rub), in: sut)
    }

    // MARK: - Default-price picker

    func testUSDPickerOffersTheScaleTiersAndChecksTheStoredOne() throws {
        let titles = ["0.99", "1.99", "2.99"].map { MoneyFormatter.string(decimal($0), currency: usd) }
        for (amount, checked) in [(20.0, 0), (50, 0), (100, 1), (137, 2), (500, 2)] {
            let sut = makeSUT(amount: amount) { .scale(self.usdScale) }
            // Pristine wallet: the store still says roubles, the labels follow the context.
            XCTAssertEqual(sut.walletCurrencyStore.currency, .rub)
            let picker = sut.makeDefaultPricePicker()
            XCTAssertEqual(picker.actions.count, 4, "\(amount)")
            XCTAssertEqual(picker.actions.dropLast().map(\.title), titles, "\(amount)")
            XCTAssertTrue(picker.actions.dropLast().allSatisfy { $0.style == .default && $0.isEnabled })
            XCTAssertEqual(picker.actions.last?.style, .cancel)
            XCTAssertTrue(picker.preferredAction === picker.actions[checked], "\(amount) → tier \(checked)")
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, amount)
        }
    }

    func testRoubleContextPickerKeepsThePresetsAndChecksNothing() {
        let sut = makeSUT(amount: 137) { .scale(.rouble) }
        let picker = sut.makeDefaultPricePicker()
        XCTAssertEqual(picker.actions.dropLast().map(\.title), [20, 50, 100, 200, 500].map {
            MoneyFormatter.string(Double($0), currency: .rub)
        })
        XCTAssertNil(picker.preferredAction)
        tap(3, in: sut)
        XCTAssertEqual(sut.alarmDefaults.penaltyAmount, 200)
    }

    func testChoosingATierStoresItsRoubleEquivalent() {
        for (amount, choice, stored) in [(50.0, 1, 100.0), (50, 2, 200), (137, 0, 50), (500, 1, 100)] {
            let sut = makeSUT(amount: amount) { .scale(self.usdScale) }
            tap(choice, in: sut)
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, stored, "\(amount) → tier \(choice)")
            let reopened = sut.makeDefaultPricePicker()
            XCTAssertTrue(reopened.preferredAction === reopened.actions[choice], "\(amount) → tier \(choice)")
        }
    }

    func testReChoosingTheCheckedTierKeepsTheStoredAmount() {
        for (amount, checked) in [(137.0, 2), (20, 0), (73, 1)] {
            let sut = makeSUT(amount: amount) { .scale(self.usdScale) }
            let picker = sut.makeDefaultPricePicker()
            XCTAssertTrue(picker.preferredAction === picker.actions[checked])
            tap(checked, in: sut)
            XCTAssertEqual(sut.alarmDefaults.penaltyAmount, amount)
        }
    }

    func testChoosingATierReloadsBothMountedRows() throws {
        let sut = makeSUT(amount: 50) { .scale(self.usdScale) }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        XCTAssertTrue(rowShows(MoneyFormatter.string(decimal("0.99"), currency: usd), in: sut))

        tap(2, in: sut)
        XCTAssertTrue(rowShows(MoneyFormatter.string(decimal("2.99"), currency: usd), in: sut))
        let rules = try XCTUnwrap(sut.tableView.cellForRow(at: rulesIndexPath(in: sut)))
        let chain = ["2.99", "5.98", "11.96", "23.92"]
            .map { MoneyFormatter.string(decimal($0), currency: usd) }.joined(separator: " → ")
        XCTAssertTrue(labels(in: rules).contains { $0.text == chain })
    }

    func testUnavailableContextDisablesThePicker() throws {
        let sut = makeSUT(amount: 50) { .unavailable(self.usd) }
        XCTAssertFalse(sut.isDefaultPricePickerEnabled)
        let row = sut.makeFinanceCell(at: priceIndexPath(in: sut))
        XCTAssertEqual(row.accessoryType, .none)
        XCTAssertEqual(row.selectionStyle, .none)
        let picker = sut.makeDefaultPricePicker()
        XCTAssertEqual(picker.actions.map(\.style), [.cancel])
        XCTAssertNil(picker.preferredAction)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        sut.tableView(sut.tableView, didSelectRowAt: priceIndexPath(in: sut))
        XCTAssertNil(sut.presentedViewController)
        XCTAssertEqual(sut.alarmDefaults.penaltyAmount, 50)

        for context in [SnoozePriceContext.scale(.rouble), .scale(usdScale)] {
            let enabled = makeSUT(amount: 50) { context }
            XCTAssertTrue(enabled.isDefaultPricePickerEnabled)
            XCTAssertEqual(enabled.makeFinanceCell(at: priceIndexPath(in: enabled)).accessoryType,
                           .disclosureIndicator)
        }
    }

    /// Taps option `index` of the sheet: commits the choice behind that action,
    /// after checking the sheet shows exactly the choices, in order.
    private func tap(_ index: Int, in sut: SettingsViewController) {
        let choices = sut.defaultPriceChoices()
        XCTAssertEqual(sut.makeDefaultPricePicker().actions.dropLast().map(\.title), choices.map(\.title))
        choices[index].commit()
    }

    // MARK: - Fixture

    private func makeSUT(
        amount: Double,
        center: NotificationCenter = NotificationCenter(),
        context: @escaping () -> SnoozePriceContext
    ) -> SettingsViewController {
        let defaults = makeIsolatedDefaults()
        let alarmDefaults = AlarmDefaults(defaults: defaults)
        alarmDefaults.penaltyAmount = amount
        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        let sut = SettingsViewController(
            themeService: ThemeService(defaults: defaults),
            alarmDefaults: alarmDefaults,
            referralService: ReferralService(defaults: defaults, balanceService: wallet),
            walletCurrencyStore: WalletCurrencyStore(defaults: defaults),
            priceContextSource: context,
            notificationCenter: center
        )
        sut.loadViewIfNeeded()
        return sut
    }

    private func rowShows(_ text: String, in sut: SettingsViewController) -> Bool {
        sut.tableView.layoutIfNeeded()
        guard let cell = sut.tableView.cellForRow(at: priceIndexPath(in: sut)) else { return false }
        return labels(in: cell).contains { $0.text == text }
    }

    private func waitForRow(_ text: String, in sut: SettingsViewController) {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in MainActor.assumeIsolated { self.rowShows(text, in: sut) } },
            object: nil
        )
        wait(for: [shown], timeout: 5)
    }

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func priceIndexPath(in sut: SettingsViewController) -> IndexPath {
        IndexPath(row: SettingsViewController.FinanceRow.defaultPrice.rawValue,
                  section: sut.visibleSections.firstIndex(of: .finance)!)
    }

    private func rulesIndexPath(in sut: SettingsViewController) -> IndexPath {
        IndexPath(row: 0, section: sut.visibleSections.firstIndex(of: .rules)!)
    }

    private func labels(in view: UIView) -> [UILabel] {
        descendants(in: view).compactMap { $0 as? UILabel }
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
