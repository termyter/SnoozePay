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
        view.subviews.flatMap { ($0 as? UILabel).map { [$0] } ?? [] } + view.subviews.flatMap { labels(in: $0) }
    }
}
