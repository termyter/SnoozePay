import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class WalletBalanceCurrencyTests: XCTestCase {
    private func labels(in view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }

    private func strings(in view: UIView) -> [String] {
        labels(in: view).filter { !$0.isHidden }.compactMap { $0.attributedText?.string ?? $0.text }
    }

    func testRubCardAndPillKeepCanonicalNarrowGap() {
        let card = SPBalanceCard(balance: 1234, currency: .rub)
        let header = SPAlarmsListHeader()
        header.setBalance(1234, currency: .rub, hint: nil)
        for view in [card as UIView, header] {
            XCTAssertTrue(strings(in: view).contains("1\u{00A0}234\u{202F}₽"))
        }
    }

    func testRealCardAndPillKeepFractionsCurrencyAndDeltaAcrossUpdatesAndTheme() throws {
        let usd = try XCTUnwrap(Currency(code: "USD"))
        let eur = try XCTUnwrap(Currency(code: "EUR"))
        for (currency, symbol, next, nextSymbol) in [(usd, "$", eur, "€"), (eur, "€", usd, "$")] {
            let card = SPBalanceCard(balance: 0.49, currency: currency, delta: -0.49)
            let header = SPAlarmsListHeader()
            header.setBalance(0.49, currency: currency, hint: nil)
            let stack = UIStackView(arrangedSubviews: [card, header])
            stack.axis = .vertical
            let host = UIViewController()
            host.view.addSubview(stack)
            stack.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            window.layoutIfNeeded()
            for view in [card as UIView, header] {
                XCTAssertTrue(strings(in: view).contains { $0.contains("0,49") && $0.contains(symbol) })
                XCTAssertFalse(strings(in: view).contains { $0.contains("₽") })
            }
            XCTAssertTrue(strings(in: card).contains { $0.hasPrefix("↓") && $0.contains(symbol) })
            let pill = try XCTUnwrap(header.subviews.compactMap { $0 as? UIControl }
                .first { $0.layer.cornerRadius == 14 })
            let lightBorder = pill.layer.borderColor?.components
            window.overrideUserInterfaceStyle = .dark
            window.layoutIfNeeded()
            XCTAssertNotEqual(pill.layer.borderColor?.components, lightBorder, "Theme callback must have run")
            for view in [card as UIView, header] {
                XCTAssertTrue(strings(in: view).contains { $0.contains("0,49") && $0.contains(symbol) })
            }
            XCTAssertEqual(card.currency, currency)
            card.update(balance: 1.79, currency: next, delta: nil)
            header.setBalance(1.79, currency: next, hint: nil)
            for view in [card as UIView, header] {
                XCTAssertTrue(strings(in: view).contains { $0.contains("1,79") && $0.contains(nextSymbol) })
            }
            XCTAssertFalse(strings(in: card).contains { $0.hasPrefix("↓") || $0.hasPrefix("↑") })
        }
    }

    func testWalletControllerFirstRenderAndRefreshUseActualWalletCurrencyWithoutFilteringPreview() throws {
        let suite = "WalletBalanceCurrencyTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repository,
                                     notificationCenter: NotificationCenter())
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertEqual(balance.topUpFromPurchase(amount: 0.49, currency: usd), .credited)
        let controller = WalletViewController(balanceService: balance, transactionRepository: repository)
        controller.loadViewIfNeeded()
        XCTAssertTrue(strings(in: controller.view).contains { $0.contains("0,49") && $0.contains("$") })
        XCTAssertTrue(repository.record(Transaction(type: .charge, amount: 500, currency: .rub)))
        XCTAssertTrue(repository.record(Transaction(type: .charge, amount: 20,
                                                   currency: try XCTUnwrap(Currency(code: "EUR")))))
        controller.viewWillAppear(false)
        for symbol in ["₽", "€"] {
            XCTAssertTrue(strings(in: controller.view).contains { $0.contains(symbol) },
                          "Foreign-currency rows must remain visible in the preview")
        }
        XCTAssertEqual(balance.topUpFromPurchase(amount: 0.50, currency: usd), .credited)
        controller.viewWillAppear(false)
        let hero = try XCTUnwrap(labels(in: controller.view).first { $0 is SPGradientTextLabel })
        XCTAssertTrue((hero.attributedText?.string ?? "").contains("0,99"))
        XCTAssertTrue((hero.attributedText?.string ?? "").contains("$"))
    }

    func testAlarmsViewModelReadsWalletCurrencyAndFiltersFinancialDeltaBeforeRefundPairing() throws {
        let suite = "AlarmsBalanceCurrencyTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let repository = TransactionRepository(defaults: defaults)
        let balance = BalanceService(defaults: defaults, transactionRepository: repository, notificationCenter: center)
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertEqual(balance.topUpFromPurchase(amount: 2.99, currency: usd), .credited)
        let charge = Transaction(type: .charge, amount: 0.49, currency: usd)
        XCTAssertTrue(repository.record(charge))
        XCTAssertTrue(repository.record(Transaction(type: .refund, amount: 0.49, currency: .rub,
                                                   refundsTransactionID: charge.id)))
        let model = AlarmsListViewModel(
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler()),
            balanceService: balance, transactionRepository: repository, notificationCenter: center
        )
        model.loadData()
        XCTAssertEqual(model.walletCurrency, usd)
        XCTAssertTrue(model.formattedBalance.contains("$"))
        XCTAssertTrue(model.formattedBalance.contains("2,50"))
        let delta = try XCTUnwrap(model.weeklyDelta)
        XCTAssertEqual(NSDecimalNumber(decimal: delta).doubleValue, -0.49, accuracy: 0.000000001)
    }
}
