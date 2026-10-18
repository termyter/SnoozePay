import XCTest
import UIKit
@testable import SnoozePay

@MainActor
final class AlarmListPriceCurrencyTests: XCTestCase {
    private struct PriceCase {
        let code: String
        let amount: Double
        let digits: String
    }

    func testListPriceAndPenaltyPreserveWalletCurrencyAndFractions() {
        let cases = [
            PriceCase(code: "USD", amount: 2.99, digits: "2,99"),
            PriceCase(code: "EUR", amount: 1.25, digits: "1,25"),
            PriceCase(code: "JPY", amount: 299, digits: "299"),
            PriceCase(code: "KWD", amount: 0.001, digits: "0,001"),
            PriceCase(code: "RUB", amount: 1234.5, digits: "1\u{00A0}234,5")
        ]
        for item in cases {
            let (code, amount, digits) = (item.code, item.amount, item.digits)
            withPrice(amount, currency: Currency(code: code)!) { viewModel in
                let price = viewModel.alarmPriceText(at: 0)
                XCTAssertEqual(price, MoneyFormatter.string(amount, currency: viewModel.walletCurrency), code)
                XCTAssertTrue(price.contains(digits), price)
                XCTAssertEqual(viewModel.alarmPenaltyString(at: 0), Localized.format("alarms.penalty", price))
                XCTAssertEqual(viewModel.alarms[0].penaltyAmount, amount)
                if code != "RUB" { XCTAssertFalse(price.contains("₽"), price) }
            }
        }
    }

    func testPositiveUnderflowIsUnknownWhileActualZeroRemainsZero() {
        for (code, amount) in [("USD", 0.002), ("JPY", 0.2), ("RUB", 0.002)] {
            let currency = Currency(code: code)!
            withPrice(amount, currency: currency) { viewModel in
                XCTAssertEqual(viewModel.alarmPriceText(at: 0), "—", code)
                XCTAssertEqual(viewModel.alarmPenaltyString(at: 0), "—")
                XCTAssertEqual(viewModel.alarms[0].penaltyAmount, amount)
            }
            withPrice(0, currency: currency) { viewModel in
                XCTAssertEqual(viewModel.alarmPriceText(at: 0), MoneyFormatter.string(0.0, currency: currency))
            }
        }
    }

    func testRealCellReuseUpdatesPriceVoiceOverAndRubleIcon() {
        let cell = AlarmCell(style: .default, reuseIdentifier: AlarmCell.reuseID)
        for (code, amount, enabled) in [("RUB", 50.0, true), ("USD", 2.99, true),
                                        ("RUB", 50.0, false), ("RUB", 50.0, true)] {
            withPrice(amount, currency: Currency(code: code)!) { viewModel in
                cell.prepareForReuse()
                let price = viewModel.alarmPriceText(at: 0)
                cell.configure(
                    time: "7:00", daysCaps: "", priceText: price,
                    priceCurrency: viewModel.walletCurrency,
                    multiplier: nil, soundName: nil, enabled: enabled
                )
                let views = descendants(of: cell.contentView)
                XCTAssertTrue(views.compactMap { ($0 as? UILabel)?.attributedText?.string }.contains(price))
                XCTAssertTrue(views.contains { $0.accessibilityLabel == "Будильник 7:00, \(price)" })
                guard let pill = views.compactMap({ $0 as? SPPill }).first else {
                    XCTFail("Actual price pill is absent")
                    return
                }
                let icons = descendants(of: pill).compactMap { $0 as? UIImageView }.filter { !$0.isHidden }
                XCTAssertEqual(icons.count, enabled && code == "RUB" ? 1 : 0, code)
            }
        }
    }

    private final class HostedList: AlarmsListViewController {
        // Milestone presentation reads shared streak history; this fixture
        // isolates currency refresh and keeps the real appearance/binding.
        override func presentStreakModalIfNeeded(in viewController: UIViewController? = nil) {}
    }

    func testFirstForeignTopUpRebindsAlreadyVisibleRowsWithoutReappearance() async throws {
        let suite = "test.alarmListFirstPaid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let balance = BalanceService(defaults: defaults, notificationCenter: center)
        let repository = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
        repository.save(Alarm(penaltyAmount: 2.99))
        let monitor = AlarmBackendMonitor(
            probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
        )
        let viewModel = AlarmsListViewModel(
            alarmRepository: repository, balanceService: balance,
            transactionRepository: TransactionRepository(defaults: defaults), notificationCenter: center,
            alarmDefaults: AlarmDefaults(defaults: defaults), backendMonitor: monitor
        )
        let controller = HostedList(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        viewModel.loadData()
        controller.view.layoutIfNeeded()
        let table = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UITableView }.first)
        table.layoutIfNeeded()
        let first = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)) as? AlarmCell)
        let rubPrice = MoneyFormatter.string(2.99, currency: .rub)
        XCTAssertTrue(descendants(of: first).contains { $0.accessibilityLabel?.contains(rubPrice) == true })
        let usd = Currency(code: "USD")!
        guard case .credited = balance.topUpFromPurchase(amount: 10, currency: usd) else {
            return XCTFail("A pristine wallet must accept its first foreign paid top-up")
        }
        let price = MoneyFormatter.string(2.99, currency: usd)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            table.visibleCells.contains { cell in
                self.descendants(of: cell).contains { $0.accessibilityLabel?.contains(price) == true }
            }
        }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [updated], timeout: 5)
        XCTAssertEqual(result, .completed, "The actual balance observer must rebind visible cells")
        let refreshed = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)) as? AlarmCell)
        XCTAssertFalse(descendants(of: refreshed).contains { $0.accessibilityLabel?.contains(rubPrice) == true })
        let pill = try XCTUnwrap(descendants(of: refreshed).compactMap { $0 as? SPPill }.first)
        XCTAssertTrue(descendants(of: pill).compactMap { $0 as? UIImageView }.allSatisfy { $0.isHidden })
        XCTAssertEqual(viewModel.alarms[0].penaltyAmount, 2.99)
    }

    private func withPrice(_ amount: Double, currency: Currency, body: (AlarmsListViewModel) -> Void) {
        let suite = "test.alarmListPrice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let balance = BalanceService(defaults: defaults, notificationCenter: center)
        _ = balance.freezeCurrency(currency)
        let repository = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
        repository.save(Alarm(penaltyAmount: amount))
        let viewModel = AlarmsListViewModel(
            alarmRepository: repository, balanceService: balance,
            transactionRepository: TransactionRepository(defaults: defaults), notificationCenter: center
        )
        viewModel.loadData()
        body(viewModel)
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
