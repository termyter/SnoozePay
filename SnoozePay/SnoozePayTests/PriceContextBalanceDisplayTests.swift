import UIKit
import XCTest
@testable import SnoozePay

/// The alarm list row, the list balance, the wallet card and the firing balance
/// pill follow the wallet's price context (#1147): a pristine wallet on a dollar
/// storefront reads "$0.99" / "$0.00", a wallet with history keeps its ledger
/// currency, an unavailable context quotes no number, and rouble contexts render
/// what they rendered before.
///
/// Every wallet lives in an isolated suite (`makeIsolatedDefaults`) with its own
/// `NotificationCenter`: `.shared` follows the scale the host app cached.
@MainActor
final class PriceContextBalanceDisplayTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private var usdScale: SnoozePriceScale { SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])! }

    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var scaleStore: SnoozePriceScaleStore!
    private var ledger: TransactionRepository!
    private var wallet: BalanceService!
    private var alarms: AlarmRepository!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        center = NotificationCenter()
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        ledger = TransactionRepository(defaults: defaults)
        wallet = BalanceService(
            defaults: defaults, transactionRepository: ledger,
            notificationCenter: center, priceScaleStore: scaleStore
        )
        alarms = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
    }

    override func tearDown() {
        // The pool empties the suite itself; never write to it from here.
        alarms = nil
        wallet = nil
        ledger = nil
        scaleStore = nil
        center = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func money(_ text: String, _ currency: Currency) -> String {
        MoneyFormatter.string(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!, currency: currency)
    }

    private func makeListViewModel(_ saved: [Alarm]) -> AlarmsListViewModel {
        saved.forEach { alarms.save($0) }
        let viewModel = AlarmsListViewModel(
            alarmRepository: alarms, balanceService: wallet, transactionRepository: ledger,
            notificationCenter: center, alarmDefaults: AlarmDefaults(defaults: defaults),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
            )
        )
        viewModel.loadData()
        return viewModel
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func texts(in view: UIView) -> [String] {
        descendants(of: view).compactMap { ($0 as? UILabel)?.attributedText?.string ?? ($0 as? UILabel)?.text }
    }

    // MARK: - List row and balance

    func testPristineWalletOnDollarStorefront_quotesTiersAndShowsDollarZero() {
        XCTAssertTrue(scaleStore.record(usdScale))
        let viewModel = makeListViewModel([
            Alarm(penaltyAmount: 50),
            Alarm(penaltyAmount: 100, penaltyTier: .high),
            Alarm(penaltyAmount: 50, progressiveScale: true)
        ])

        XCTAssertEqual(viewModel.alarmPriceText(at: 0), money("0.99", usd), "legacy 50 → lowest tier")
        XCTAssertEqual(viewModel.alarmPriceText(at: 1), money("2.99", usd))
        XCTAssertEqual(viewModel.alarmPriceText(at: 2), money("0.99", usd), "the row quotes the first snooze")
        XCTAssertEqual(viewModel.alarmPenaltyString(at: 0), Localized.format("alarms.penalty", money("0.99", usd)))
        XCTAssertEqual(viewModel.priceCurrency, usd)
        XCTAssertEqual(viewModel.balanceCurrency, usd)
        XCTAssertEqual(viewModel.formattedBalance, MoneyFormatter.string(0.0, currency: usd))
        XCTAssertEqual(viewModel.walletCurrency, .rub, "display only: nothing is frozen before a purchase")
        XCTAssertNil(wallet.storedWalletCurrency)
        for text in [viewModel.alarmPriceText(at: 0), viewModel.formattedBalance] {
            XCTAssertFalse(text.contains("₽"), text)
        }
    }

    func testRoubleContexts_renderExactlyAsBefore() {
        let viewModel = makeListViewModel([Alarm(penaltyAmount: 50), Alarm(penaltyAmount: 1234.5)])
        XCTAssertEqual(viewModel.alarmPriceText(at: 0), MoneyFormatter.string(50.0, currency: .rub))
        XCTAssertEqual(viewModel.alarmPriceText(at: 0), "50\u{202F}₽")
        XCTAssertEqual(viewModel.alarmPriceText(at: 1), MoneyFormatter.string(1234.5, currency: .rub))
        XCTAssertEqual(viewModel.formattedBalance, "0\u{202F}₽")
        XCTAssertEqual(viewModel.balanceCurrency, .rub)
    }

    /// A wallet with history keeps its ledger currency even when a dollar
    /// storefront scale is cached: a legacy rouble wallet (no stored currency).
    func testLegacyRoubleWalletWithHistory_ignoresTheCachedStorefrontScale() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 100, currency: nil), .credited)
        let viewModel = makeListViewModel([Alarm(penaltyAmount: 50)])

        XCTAssertEqual(viewModel.alarmPriceText(at: 0), "50\u{202F}₽")
        XCTAssertEqual(viewModel.formattedBalance, MoneyFormatter.string(100.0, currency: .rub))
    }

    func testDollarWalletWithoutScale_isUnpricedAndNeverRoubles() {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1.99, currency: usd), .credited)
        let viewModel = makeListViewModel([Alarm(penaltyAmount: 50)])

        XCTAssertEqual(viewModel.alarmPriceText(at: 0), "—")
        XCTAssertEqual(viewModel.alarmPenaltyString(at: 0), "—")
        XCTAssertEqual(viewModel.formattedBalance, MoneyFormatter.string(1.99, currency: usd))
    }

    // MARK: - Refresh

    func testScaleChangeAndWalletCurrencyChange_refreshTheViewModel() {
        let viewModel = makeListViewModel([Alarm(penaltyAmount: 50)])
        var updates = 0
        viewModel.onBalanceUpdated = { _ in updates += 1 }
        XCTAssertEqual(viewModel.alarmPriceText(at: 0), "50\u{202F}₽")

        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(updates, 1, "a recorded scale must reach the bound screen")
        XCTAssertEqual(viewModel.alarmPriceText(at: 0), money("0.99", usd))
        XCTAssertEqual(viewModel.formattedBalance, MoneyFormatter.string(0.0, currency: usd))

        let eur = Currency(code: "EUR")!
        XCTAssertEqual(wallet.freezeCurrency(eur), .frozen(eur))
        XCTAssertGreaterThanOrEqual(updates, 2, "a wallet-currency change must reach the bound screen")
        XCTAssertEqual(viewModel.alarmPriceText(at: 0), "—", "EUR has no cached scale")
        XCTAssertEqual(viewModel.balanceCurrency, eur)
    }

    private final class HostedList: AlarmsListViewController {
        override func presentStreakModalIfNeeded(in viewController: UIViewController? = nil) {}
    }

    func testHostedList_rebindsRowsAndHeaderOnScaleChangeWithoutReappearance() throws {
        let viewModel = makeListViewModel([Alarm(penaltyAmount: 50)])
        let controller = HostedList(viewModel: viewModel, bannerStreakCount: { 0 })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        viewModel.loadData()
        controller.view.layoutIfNeeded()
        let table = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UITableView }.first)
        table.layoutIfNeeded()
        let header = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? SPAlarmsListHeader }.first)
        XCTAssertTrue(texts(in: header).contains("0\u{202F}₽"))

        XCTAssertTrue(scaleStore.record(usdScale))
        table.layoutIfNeeded()

        let price = money("0.99", usd)
        let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)) as? AlarmCell)
        XCTAssertTrue(texts(in: cell).contains(price), "row still reads \(texts(in: cell))")
        let pill = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? SPPill }.first)
        XCTAssertTrue(descendants(of: pill).compactMap { $0 as? UIImageView }.allSatisfy(\.isHidden),
                      "no rouble glyph next to a dollar price")
        XCTAssertTrue(texts(in: header).contains(MoneyFormatter.string(0.0, currency: usd)),
                      "header still reads \(texts(in: header))")
        XCTAssertFalse(texts(in: header).contains { $0.contains("₽") })
    }

    // MARK: - Wallet card

    func testWalletCard_pristineShowsStorefrontZero_heldMoneyShowsLedgerCurrency() throws {
        XCTAssertTrue(scaleStore.record(usdScale))
        let controller = WalletViewController(balanceService: wallet, transactionRepository: ledger)
        controller.loadViewIfNeeded()
        let hero = try XCTUnwrap(descendants(of: controller.view).first { $0 is SPGradientTextLabel } as? UILabel)
        let initial = hero.attributedText?.string ?? ""
        XCTAssertTrue(initial.contains("$"), "first render: \(initial)")
        XCTAssertFalse(initial.contains("₽"), initial)
        // `refresh()` runs on every appearance and must keep the storefront zero.
        controller.viewWillAppear(false)
        let pristine = hero.attributedText?.string ?? ""
        XCTAssertTrue(pristine.contains("$"), "after refresh: \(pristine)")
        XCTAssertFalse(pristine.contains("₽"), pristine)

        XCTAssertEqual(wallet.topUpFromPurchase(amount: 50, currency: nil), .credited)
        controller.viewWillAppear(false)
        let held = hero.attributedText?.string ?? ""
        XCTAssertTrue(held.contains("₽"), "a wallet with history shows its ledger currency: \(held)")
    }

    // MARK: - Firing balance pill

    private func makeFiringViewModel() -> AlarmFiringViewModel {
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())
        let alarm = Alarm(penaltyAmount: 50)
        let repository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        repository.save(alarm)
        return AlarmFiringViewModel(
            alarm: alarm, snoozeCount: 0, balanceService: wallet, alarmRepository: repository,
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults), ledger: ledger
        )
    }

    func testFiringBalancePill_pristineZeroInLockedCurrency_heldMoneyInWalletCurrency() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(makeFiringViewModel().balanceCurrency, usd)

        XCTAssertEqual(wallet.topUpFromPurchase(amount: 50, currency: nil), .credited)
        XCTAssertEqual(makeFiringViewModel().balanceCurrency, .rub)
    }

    func testFiringBalancePill_roubleWithoutScaleUnchanged() {
        XCTAssertEqual(makeFiringViewModel().balanceCurrency, .rub)
    }

    /// The pill follows the price locked at ring start, not the live display
    /// currency: a scale recorded mid-ring must not put "$" next to "₽" prices.
    func testFiringBalancePill_scaleArrivingMidRing_keepsTheLockedCurrency() {
        let viewModel = makeFiringViewModel()
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(wallet.displayCurrency, usd, "precondition: the live display currency moved")
        XCTAssertEqual(viewModel.balanceCurrency, .rub)
    }

    /// An empty wallet that froze another currency mid-ring can no longer take
    /// the locked one: the pill shows the wallet's own currency.
    func testFiringBalancePill_walletFrozenAwayFromLockedCurrency_showsWalletCurrency() {
        XCTAssertTrue(scaleStore.record(usdScale))
        let viewModel = makeFiringViewModel()
        XCTAssertEqual(viewModel.lockedPriceContext?.currency, usd, "precondition: locked in dollars")
        XCTAssertEqual(wallet.freezeCurrency(.rub), .frozen(.rub))
        XCTAssertEqual(wallet.balance, 0)
        XCTAssertEqual(viewModel.balanceCurrency, .rub)
    }

    private final class PillLayoutController: AlarmFiringViewController {
        // The real layout only: no audio, observers, ticker or breathing.
        override func viewDidLoad() { buildFiringLayout() }
    }

    func testFiringBalancePill_pristineDollarStorefront_rendersDollarZero() throws {
        XCTAssertTrue(scaleStore.record(usdScale))
        let controller = PillLayoutController(viewModel: makeFiringViewModel())
        controller.loadViewIfNeeded()
        let pill = try XCTUnwrap(controller.balancePill)
        let text = texts(in: pill).joined(separator: " ")
        XCTAssertTrue(text.contains("$"), text)
        XCTAssertFalse(text.contains("₽"), text)
        controller.updateUI()
        let refreshed = texts(in: try XCTUnwrap(controller.balancePill)).joined(separator: " ")
        XCTAssertTrue(refreshed.contains("$"), refreshed)
    }
}
