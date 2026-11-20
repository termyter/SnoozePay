import UIKit
import XCTest
@testable import SnoozePay

/// #1168: the firing screen's direct no-balance CTA goes through the same
/// pre-purchase gate as both top-up sheets (#1163). An unreadable ledger
/// refuses every pack as a purchase failure naming the locked ledger, before
/// anything is dispatched; a readable wallet keeps its currency rules.
@MainActor
final class FiringNoBalancePurchaseGateTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private let unreadable = Data("unreadable ledger".utf8)
    private let ledgerKey = "stored_transactions"

    // MARK: - Unreadable ledger

    func testUnreadableLedger_foreignPack_showsTheLockedLedgerNotTheCurrencyNotice() throws {
        let fixture = try Fixture(test: self, pack: ("USD", "4.99")) { defaults in
            defaults.set(self.unreadable, forKey: self.ledgerKey)
        }

        try fixture.tap()

        assertRefusedAsLocked(fixture, "legacy wallet, USD pack")
    }

    /// Accepted currencies on a locked ledger: Apple would charge and the
    /// credit would be refused, so neither pack is dispatched.
    func testUnreadableLedger_acceptedPack_isNotDispatched() throws {
        for (frozen, code, price) in [(true, "USD", "4.99"), (false, "RUB", "499")] {
            let fixture = try Fixture(test: self, pack: (code, price)) { defaults in
                if frozen { self.freezeUSD(defaults) }
                defaults.set(self.unreadable, forKey: self.ledgerKey)
            }

            try fixture.tap()

            assertRefusedAsLocked(fixture, frozen ? "USD wallet, USD pack" : "legacy wallet, RUB pack")
        }
    }

    /// The ledger is damaged after the service, view model and screen were
    /// built: only a read at tap time sees it.
    func testLedgerDamagedAfterTheScreenWasBuilt_ownCurrency_isRefusedAtTheTap() throws {
        let fixture = try Fixture(test: self, pack: ("USD", "4.99")) { defaults in
            self.freezeUSD(defaults)
        }
        XCTAssertEqual(fixture.wallet.balance, 0)
        XCTAssertNil(fixture.wallet.prePurchaseRefusal(in: usd), "Readable when the screen was built")

        fixture.defaults.set(unreadable, forKey: ledgerKey)
        try fixture.tap()

        assertRefusedAsLocked(fixture, "damaged after launch")
    }

    // MARK: - Readable ledger

    func testReadableLedger_foreignPack_showsTheCurrencyNoticeUnchanged() throws {
        let fixture = try Fixture(test: self, pack: ("USD", "4.99")) { defaults in
            let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
            XCTAssertEqual(wallet.topUpFromPurchase(amount: 10, currency: .rub), .credited)
        }

        try fixture.tap()

        XCTAssertTrue(fixture.requested.isEmpty)
        XCTAssertFalse(fixture.controller.noBalancePurchaseInFlight)
        XCTAssertEqual(fixture.controller.alerts.count, 1)
        let alert = try XCTUnwrap(fixture.controller.alerts.first)
        XCTAssertEqual(alert.title, ForeignCurrencyNotice.alertTitle)
        XCTAssertEqual(alert.message, ForeignCurrencyNotice.message(wallet: .rub, storefront: usd))
        XCTAssertEqual(alert.actions.map(\.title), [Localized.text("deposit.foreign_currency.dismiss")])
    }

    func testReadableLedger_acceptedPack_isDispatched() throws {
        for (frozen, code, price) in [(true, "USD", "4.99"), (false, "RUB", "499")] {
            let fixture = try Fixture(test: self, pack: (code, price)) { defaults in
                if frozen { self.freezeUSD(defaults) }
            }

            try fixture.tap()

            XCTAssertEqual(fixture.requested, [Fixture.sku], code)
            XCTAssertTrue(fixture.controller.alerts.isEmpty, code)
            XCTAssertTrue(fixture.controller.noBalancePurchaseInFlight, code)
            XCTAssertEqual(fixture.controller.applePayNoBalanceButton?.isEnabled, false, "In flight — \(code)")
            XCTAssertEqual(fixture.begins, 1, code)
        }
    }

    // MARK: - Foreign storefront (#1174)

    /// The catalogue filter ranks packs by `acceptsPurchase`, but a wallet that
    /// refuses the whole storefront still gets a refused pack quoted: the CTA is
    /// visible and enabled, and the tap names the refusal — the lock on an
    /// unreadable ledger, the currency on a readable one. Never a tap that only
    /// refreshes the catalogue.
    func testForeignStorefront_ctaStaysTappable_andTheTapNamesTheRefusal() throws {
        let eur = try XCTUnwrap(Currency(code: "EUR"))
        for (frozen, storefront) in [(false, usd), (true, eur)] {
            for readable in [true, false] {
                let label = "\(frozen ? "USD" : "RUB") wallet, \(storefront.code) store, readable \(readable)"
                let fixture = try Fixture(test: self, pack: (storefront.code, "4.99"),
                                          skus: StoreKitService.productIDs) { defaults in
                    if frozen {
                        self.freezeUSD(defaults)
                        self.cacheUSDScale(defaults)
                    } else if readable {
                        // History: the rouble wallet is no longer free to adopt dollars.
                        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
                        XCTAssertEqual(wallet.topUpFromPurchase(amount: 10, currency: .rub), .credited)
                    }
                    if !readable { defaults.set(self.unreadable, forKey: self.ledgerKey) }
                }
                let controller = fixture.controller
                XCTAssertEqual(controller.noBalanceContainer?.isHidden, false, label)
                XCTAssertEqual(controller.noBalancePurchase.offer?.currency, storefront, label)
                XCTAssertEqual(controller.applePayNoBalanceButton?.isEnabled, true, label)

                try fixture.tap()

                guard readable else {
                    assertRefusedAsLocked(fixture, label)
                    continue
                }
                XCTAssertTrue(fixture.requested.isEmpty, label)
                XCTAssertEqual(controller.alerts.count, 1, label)
                XCTAssertEqual(controller.alerts.first?.title, ForeignCurrencyNotice.alertTitle, label)
                let notice = ForeignCurrencyNotice.message(wallet: frozen ? usd : .rub, storefront: storefront)
                XCTAssertEqual(controller.alerts.first?.message, notice, label)
            }
        }
    }

    /// A pristine wallet locked this ring's price in dollars, then the ledger
    /// broke: the wallet can no longer adopt dollars, so the price is stranded.
    /// A tap on the CTA still on screen names the lock; the next pass replaces
    /// the CTA with the progression-unavailable text — not a silent screen.
    func testLedgerDamagedMidRing_strandedDollarPrice_isExplainedNotSilent() throws {
        let fixture = try Fixture(test: self, pack: ("USD", "4.99")) { defaults in
            self.cacheUSDScale(defaults)
        }
        let controller = fixture.controller
        XCTAssertEqual(controller.viewModel.priceCurrency, usd)
        XCTAssertFalse(controller.viewModel.isLockedPriceStranded, "Pristine: a dollar top-up can pay it")
        XCTAssertEqual(controller.noBalanceContainer?.isHidden, false)

        fixture.defaults.set(unreadable, forKey: ledgerKey)
        XCTAssertTrue(controller.viewModel.isLockedPriceStranded)
        try fixture.tap()
        assertRefusedAsLocked(fixture, "CTA still on screen after the ledger broke")

        controller.updateUI()
        XCTAssertEqual(controller.noBalanceContainer?.isHidden, true, "No top-up for a stranded price")
        XCTAssertFalse(controller.progressionUnavailableLabel.isHidden)
    }

    // MARK: - Helpers

    private func freezeUSD(_ defaults: UserDefaults) {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
    }

    /// The dollar storefront's snooze scale, so a dollar price resolves.
    private func cacheUSDScale(_ defaults: UserDefaults) {
        let scale = SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])
        let store = SnoozePriceScaleStore(defaults: defaults, notificationCenter: NotificationCenter())
        XCTAssertEqual(scale.map { store.record($0) }, true, "USD scale cached")
    }

    private func assertRefusedAsLocked(_ fixture: Fixture, _ label: String) {
        XCTAssertTrue(fixture.requested.isEmpty, "A locked ledger must not be charged for — \(label)")
        XCTAssertEqual(fixture.begins, 0, label)
        XCTAssertFalse(fixture.controller.noBalancePurchaseInFlight, label)
        // No XCTUnwrap: a throw would end a caller's loop before its next case.
        let alert = fixture.controller.alerts.first
        XCTAssertEqual(fixture.controller.alerts.count, 1, label)
        XCTAssertEqual(alert?.message, ForeignCurrencyNotice.ledgerUnreadableMessage, label)
        XCTAssertNotEqual(alert?.message, StoreKitService.ledgerLockedFailureMessage, "Nothing was charged — \(label)")
        XCTAssertEqual(alert?.title, Localized.text("firing.alert.purchase_failed.title"), label)
        XCTAssertNotEqual(alert?.title, ForeignCurrencyNotice.alertTitle, label)
        XCTAssertTrue(fixture.controller.applePayNoBalanceButton?.isEnabled == true,
                      "The refusal is not a stuck purchase — \(label)")
    }

    private final class Fixture {
        static let sku = "io.mobilife.snoozepay.balance.499"
        let defaults: UserDefaults
        let wallet: BalanceService
        let controller: GateController
        var requested: [String] = []
        var begins = 0

        /// `skus`: the catalogue, every pack priced as `pack`.
        init(test: XCTestCase, pack: (code: String, price: String), skus: [String] = [Fixture.sku],
             prepare: (UserDefaults) -> Void) throws {
            defaults = test.makeIsolatedDefaults()
            prepare(defaults)
            let center = NotificationCenter()
            wallet = BalanceService(defaults: defaults, notificationCenter: center)
            let price = try XCTUnwrap(Decimal(string: pack.price))
            let offers = skus.compactMap {
                TopUpOffer(productID: $0, price: price, currencyCode: pack.code,
                           displayPrice: "\(pack.price) \(pack.code)")
            }
            XCTAssertEqual(offers.count, skus.count, "Every pack is a valid offer")
            let backend = TestAlarmKitBackend()
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
            let model = AlarmFiringViewModel(
                alarm: Alarm(penaltyAmount: 50), balanceService: wallet,
                alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler), scheduler: scheduler,
                wakeStore: WakeEventStore(defaults: defaults), ledger: TransactionRepository(defaults: defaults)
            )
            controller = GateController(viewModel: model)
            controller.noBalancePurchase = AlarmFiringNoBalancePurchase(
                controller: controller, center: center,
                dispatch: { [weak self] in self?.requested.append($0) },
                offerProvider: { id in offers.first { $0.productID == id } },
                beginFeedback: { [weak self] in self?.begins += 1 }, endFeedback: {}
            )
            controller.loadViewIfNeeded()
        }

        func tap() throws {
            try XCTUnwrap(controller.applePayNoBalanceButton).sendActions(for: .touchUpInside)
        }
    }
}

@MainActor
private final class GateController: AlarmFiringViewController {
    var alerts: [UIAlertController] = []
    override func viewDidLoad() { buildFiringLayout() }
    override func present(
        _ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil
    ) {
        if let alert = viewControllerToPresent as? UIAlertController { alerts.append(alert) }
    }
}
