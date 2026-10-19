import XCTest
import UIKit
@testable import SnoozePay

@MainActor
final class AlarmListPriceCurrencyTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() {
        cleanups.reversed().forEach { $0() }
        cleanups.removeAll()
        super.tearDown()
    }

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
        private(set) var appearanceCount = 0

        override func viewWillAppear(_ animated: Bool) {
            appearanceCount += 1
            super.viewWillAppear(animated)
        }

        // Milestone presentation reads shared streak history; this fixture
        // isolates currency refresh and keeps the real appearance/binding.
        override func presentStreakModalIfNeeded(in viewController: UIViewController? = nil) {}
    }

    func testFirstForeignTopUpRefreshesVisibleRowsAndStreakBannerWithoutReappearance() async throws {
        let fixture = try hostedList()
        let (table, controller, balance) = (fixture.table, fixture.controller, fixture.balance)
        let first = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)) as? AlarmCell)
        let rubPrice = MoneyFormatter.string(2.99, currency: .rub)
        XCTAssertTrue(descendants(of: first).contains { $0.accessibilityLabel?.contains(rubPrice) == true })
        let banner = try XCTUnwrap(table.tableHeaderView as? AlarmsStreakBannerView)
        XCTAssertTrue(banner.window === fixture.window, "Read the actual mounted banner")
        let saved = Decimal(string: "14.95")!
        let rubCaption = Localized.format("alarms.streak.saved", MoneyFormatter.string(saved, currency: .rub))
        let caption = try XCTUnwrap(descendants(of: banner).compactMap { $0 as? UILabel }.first {
            $0.text == rubCaption
        })
        XCTAssertEqual(caption.text, rubCaption)
        XCTAssertEqual(balance.walletCurrency, .rub)
        XCTAssertNil(fixture.defaults.object(forKey: WalletCurrencyStore.storageKey), "The wallet must be pristine")
        let appearances = controller.appearanceCount
        XCTAssertGreaterThan(appearances, 0)
        let readsBeforeCurrencyChange = fixture.streakReads.count
        let usd = Currency(code: "USD")!
        guard case .credited = balance.topUpFromPurchase(amount: 10, currency: usd) else {
            return XCTFail("A pristine wallet must accept its first foreign paid top-up")
        }
        // Main-thread paid credit delivers the real balance notification synchronously.
        // Read the retained label now, before a deferred layout can repair stale copy.
        let usdCaption = Localized.format("alarms.streak.saved", MoneyFormatter.string(saved, currency: usd))
        XCTAssertTrue(table.tableHeaderView === banner)
        XCTAssertEqual(caption.text, usdCaption)
        XCTAssertFalse(caption.text?.contains("₽") == true)
        XCTAssertGreaterThan(fixture.streakReads.count, readsBeforeCurrencyChange)
        XCTAssertEqual(controller.appearanceCount, appearances)
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
        XCTAssertEqual(fixture.viewModel.alarms[0].penaltyAmount, 2.99)
        XCTAssertEqual(controller.appearanceCount, appearances)
    }

    func testSameCurrencyCreditRefreshesHeaderWithoutRebuildingRowsOrStreakBanner() throws {
        let usd = Currency(code: "USD")!
        let fixture = try hostedList(initialPaidCurrency: usd)
        let banner = try XCTUnwrap(fixture.table.tableHeaderView as? AlarmsStreakBannerView)
        let caption = try XCTUnwrap(descendants(of: banner).compactMap { $0 as? UILabel }.first {
            $0.text?.hasPrefix("Сэкономили ") == true
        })
        let oldCaption = caption.text
        let row = try XCTUnwrap(fixture.table.cellForRow(at: IndexPath(row: 0, section: 0)))
        let readsBeforeCredit = fixture.streakReads.count
        let appearances = fixture.controller.appearanceCount
        guard case .credited = fixture.balance.topUpFromPurchase(amount: 5, currency: usd) else {
            return XCTFail("A same-currency paid top-up must still credit the wallet")
        }
        let header = try XCTUnwrap(descendants(of: fixture.controller.view).compactMap {
            $0 as? SPAlarmsListHeader
        }.first)
        let newBalance = MoneyFormatter.string(15.0, currency: usd)
        XCTAssertTrue(descendants(of: header).compactMap {
            ($0 as? UILabel)?.attributedText?.string
        }.contains(newBalance), "Ordinary balance refresh must still reach the real header")
        XCTAssertEqual(fixture.streakReads.count, readsBeforeCredit, "Same-currency credit must not rebuild the banner")
        XCTAssertEqual(caption.text, oldCaption)
        XCTAssertTrue(fixture.table.cellForRow(at: IndexPath(row: 0, section: 0)) === row)
        XCTAssertEqual(fixture.controller.appearanceCount, appearances)
        XCTAssertEqual(fixture.viewModel.alarms[0].penaltyAmount, 2.99)
    }

    private final class StreakReads { var count = 0 }

    @MainActor
    private struct HostedCurrencyList {
        let defaults: UserDefaults
        let balance: BalanceService
        let viewModel: AlarmsListViewModel
        let controller: HostedList
        let window: UIWindow
        let table: UITableView
        let streakReads: StreakReads

    }

    private func hostedList(initialPaidCurrency: Currency? = nil) throws -> HostedCurrencyList {
        let suite = "test.alarmListFirstPaid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        cleanups.append { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let balance = BalanceService(defaults: defaults, notificationCenter: center)
        if let initialPaidCurrency {
            let credit = balance.topUpFromPurchase(amount: 10, currency: initialPaidCurrency)
            guard case .credited = credit else {
                XCTFail("Unable to establish the isolated fixture's initial paid currency")
                throw NSError(domain: "AlarmListPriceCurrencyTests.fixture", code: 1)
            }
        }
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
        let reads = StreakReads()
        let controller = HostedList(viewModel: viewModel, bannerStreakCount: { reads.count += 1; return 5 })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cleanups.append { window.isHidden = true; window.rootViewController = nil }
        window.rootViewController = controller
        window.isHidden = false
        viewModel.loadData()
        controller.view.layoutIfNeeded()
        let table = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UITableView }.first)
        table.layoutIfNeeded()
        return HostedCurrencyList(defaults: defaults, balance: balance, viewModel: viewModel,
                                  controller: controller, window: window, table: table, streakReads: reads)
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
