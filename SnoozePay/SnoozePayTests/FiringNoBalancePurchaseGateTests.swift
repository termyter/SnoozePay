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
            XCTAssertEqual(fixture.begins, 1, code)
        }
    }

    // MARK: - Helpers

    private func freezeUSD(_ defaults: UserDefaults) {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
    }

    private func assertRefusedAsLocked(_ fixture: Fixture, _ label: String) {
        XCTAssertTrue(fixture.requested.isEmpty, "A locked ledger must not be charged for — \(label)")
        XCTAssertEqual(fixture.begins, 0, label)
        XCTAssertFalse(fixture.controller.noBalancePurchaseInFlight, label)
        // No XCTUnwrap: a throw would end a caller's loop before its next case.
        let alert = fixture.controller.alerts.first
        XCTAssertEqual(fixture.controller.alerts.count, 1, label)
        XCTAssertEqual(alert?.message, StoreKitService.ledgerLockedFailureMessage, label)
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

        init(test: XCTestCase, pack: (code: String, price: String), prepare: (UserDefaults) -> Void) throws {
            defaults = test.makeIsolatedDefaults()
            prepare(defaults)
            let center = NotificationCenter()
            wallet = BalanceService(defaults: defaults, notificationCenter: center)
            let offer = try XCTUnwrap(TopUpOffer(productID: Self.sku, price: Decimal(string: pack.price)!,
                                                 currencyCode: pack.code, displayPrice: "\(pack.price) \(pack.code)"))
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
                offerProvider: { $0 == Self.sku ? offer : nil },
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
