import os
import UIKit
import XCTest
@testable import SnoozePay

/// #1168: the firing screen's direct no-balance CTA goes through the same
/// pre-purchase gate as both top-up sheets (#1163). An unreadable ledger
/// refuses every pack as a purchase failure naming the locked ledger, before
/// anything is dispatched; a readable wallet keeps its currency rules.
/// Every refusal leaves a line for support (#1184).
@MainActor
final class FiringNoBalancePurchaseGateTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)
    private static let refusalPrefix = "firing: top-up refused before purchase"
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

        assertRefusedAsForeign(fixture, wallet: .rub, storefront: usd, "rouble wallet, USD pack")
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
            XCTAssertFalse(fixture.logged.contains { $0.message.hasPrefix(Self.refusalPrefix) }, code)
        }
    }

    /// The catalogue empties while the CTA is on screen, enabled and quoting a
    /// price, and no reload notice redraws it — unreachable in production, so
    /// the line is an error. The tap redraws the CTA as «—», disabled, and buys
    /// nothing. No alert: the firing sheet's own `guard let offer` only
    /// refreshes too.
    func testTapWithNoOffer_logsTheDefect_redrawsTheCTA_andDispatchesNothing() throws {
        let fixture = try Fixture(test: self, pack: ("USD", "4.99")) { defaults in
            self.freezeUSD(defaults)
        }
        let topUp = Localized.text("common.button.top_up")
        XCTAssertEqual(fixture.controller.applePayNoBalanceButton?.accessibilityLabel, topUp + ", 4.99 USD")
        fixture.offers = []

        try fixture.tap()

        XCTAssertTrue(fixture.requested.isEmpty)
        XCTAssertEqual(fixture.begins, 0)
        XCTAssertFalse(fixture.controller.noBalancePurchaseInFlight)
        XCTAssertTrue(fixture.controller.alerts.isEmpty)
        XCTAssertEqual(fixture.controller.applePayNoBalanceButton?.isEnabled, false, "Redrawn without a price")
        XCTAssertEqual(fixture.controller.applePayNoBalanceButton?.accessibilityLabel, topUp + ", —")
        XCTAssertNil(fixture.controller.noBalancePurchase.renderedPrice)
        let lines = fixture.logged.filter { $0.message.hasPrefix("firing: no-balance tap found no offer") }
        XCTAssertEqual(lines.map(\.category), [.ui])
        XCTAssertEqual(lines.map(\.level), [.error])
        XCTAssertEqual(lines.first?.message, "firing: no-balance tap found no offer — CTA redrawn, nothing dispatched")
    }

    /// The fixture's `tap()` is a user's tap: a CTA that is disabled, or on
    /// screen under a hidden ancestor, is a test failure, and nothing is sent.
    func testTapHelper_refusesACTANoUserCanTap() throws {
        let cases: [(String, (GateController) -> Void)] = [
            ("disabled", { $0.applePayNoBalanceButton?.isEnabled = false }),
            ("hidden", { $0.noBalanceContainer?.isHidden = true })
        ]
        for (label, makeUnreachable) in cases {
            let fixture = try Fixture(test: self, pack: ("USD", "4.99")) { defaults in
                self.freezeUSD(defaults)
            }
            XCTAssertEqual(fixture.controller.noBalanceContainer?.isHidden, false, "Reachable first — \(label)")
            XCTAssertEqual(fixture.controller.applePayNoBalanceButton?.isEnabled, true, "Reachable first — \(label)")
            makeUnreachable(fixture.controller)

            try XCTExpectFailure("tap() has to refuse a \(label) CTA", strict: true) {
                try fixture.tap()
            } issueMatcher: { issue in
                issue.compactDescription.contains("Tapped a CTA no user can tap")
            }

            XCTAssertTrue(fixture.requested.isEmpty, label)
            XCTAssertEqual(fixture.begins, 0, label)
            XCTAssertTrue(fixture.logged.isEmpty, label)
            XCTAssertTrue(fixture.controller.alerts.isEmpty, label)
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
                assertRefusedAsForeign(fixture, wallet: frozen ? usd : .rub, storefront: storefront, label)
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
        var lines: [LoggedLine] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            XCTAssertTrue(controller.viewModel.isLockedPriceStranded)
            XCTAssertTrue(controller.viewModel.isLockedPriceStranded, "Asked twice, logged once")
        })
        // Nothing froze this wallet: the broken ledger is the cause (#1184).
        XCTAssertNil(fixture.wallet.storedWalletCurrency)
        let handle = String(controller.viewModel.alarm.id.uuidString.prefix(8))
        lines = lines.filter { $0.message.hasPrefix("firing: price locked") }
        XCTAssertEqual(lines.map(\.category), [.ui])
        XCTAssertEqual(lines.map(\.level), [.error])
        XCTAssertEqual(lines.first?.message,
                       "firing: price locked in USD, ledger unreadable alarm=\(handle) — snooze refused, no charge")
        try fixture.tap()
        assertRefusedAsLocked(fixture, "CTA still on screen after the ledger broke")

        controller.updateUI()
        XCTAssertEqual(controller.noBalanceContainer?.isHidden, true, "No top-up for a stranded price")
        XCTAssertFalse(controller.progressionUnavailableLabel.isHidden)
    }

    // MARK: - Helpers

    /// A dollar wallet that can price its snoozes. Without the cached scale its
    /// context is `.unavailable(USD)`: progression is off and the no-balance
    /// stack, CTA included, is hidden, so no user could tap it.
    private func freezeUSD(_ defaults: UserDefaults) {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
        cacheUSDScale(defaults)
    }

    /// The dollar storefront's snooze scale, so a dollar price resolves.
    private func cacheUSDScale(_ defaults: UserDefaults) {
        let scale = SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])
        let store = SnoozePriceScaleStore(defaults: defaults, notificationCenter: NotificationCenter())
        XCTAssertEqual(scale.map { store.record($0) }, true, "USD scale cached")
    }

    private func assertRefusedAsLocked(_ fixture: Fixture, _ label: String) {
        assertRefusalLogged(fixture, cause: "ledger unreadable", label)
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

    /// The currency notice, not a purchase: nothing begins, and the CTA is
    /// tappable again once the notice is up.
    private func assertRefusedAsForeign(_ fixture: Fixture, wallet: Currency, storefront: Currency, _ label: String) {
        assertRefusalLogged(fixture, cause: "wallet in \(wallet.code), pack in \(storefront.code)", label)
        XCTAssertTrue(fixture.requested.isEmpty, "A foreign pack must not be charged for — \(label)")
        XCTAssertEqual(fixture.begins, 0, label)
        XCTAssertFalse(fixture.controller.noBalancePurchaseInFlight, label)
        let alert = fixture.controller.alerts.first
        XCTAssertEqual(fixture.controller.alerts.count, 1, label)
        XCTAssertEqual(alert?.title, ForeignCurrencyNotice.alertTitle, label)
        XCTAssertEqual(alert?.message, ForeignCurrencyNotice.message(wallet: wallet, storefront: storefront), label)
        XCTAssertEqual(alert?.actions.map(\.title), [Localized.text("deposit.foreign_currency.dismiss")], label)
        XCTAssertTrue(fixture.controller.applePayNoBalanceButton?.isEnabled == true,
                      "The notice is not a stuck purchase — \(label)")
    }

    /// One notice-level line per refused tap, naming the pack the CTA quoted.
    private func assertRefusalLogged(_ fixture: Fixture, cause: String, _ label: String) {
        let lines = fixture.logged.filter { $0.message.hasPrefix(Self.refusalPrefix) }
        XCTAssertEqual(lines.map(\.category), [.ui], label)
        XCTAssertEqual(lines.map(\.level), [.default], label)
        let product = fixture.quotedProductID ?? "none"
        XCTAssertEqual(lines.first?.message, "\(Self.refusalPrefix) product=\(product) — \(cause)", label)
    }

    private final class Fixture {
        nonisolated static let sku = "io.mobilife.snoozepay.balance.499"
        let defaults: UserDefaults
        let wallet: BalanceService
        let controller: GateController
        /// The catalogue `offerProvider` reads, live.
        var offers: [TopUpOffer]
        var requested: [String] = []
        var begins = 0
        /// Lines logged during `tap()`.
        var logged: [LoggedLine] = []
        /// The pack the CTA quoted when it was last tapped.
        var quotedProductID: String?

        /// `skus`: the catalogue, every pack priced as `pack`.
        init(test: XCTestCase, pack: (code: String, price: String), skus: [String] = [Fixture.sku],
             prepare: (UserDefaults) -> Void) throws {
            defaults = test.makeIsolatedDefaults()
            prepare(defaults)
            let center = NotificationCenter()
            wallet = BalanceService(defaults: defaults, notificationCenter: center)
            let price = try XCTUnwrap(Decimal(string: pack.price))
            let catalogue = skus.compactMap {
                TopUpOffer(productID: $0, price: price, currencyCode: pack.code,
                           displayPrice: "\(pack.price) \(pack.code)")
            }
            XCTAssertEqual(catalogue.count, skus.count, "Every pack is a valid offer")
            offers = catalogue
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
                offerProvider: { [weak self] id in self?.offers.first { $0.productID == id } },
                beginFeedback: { [weak self] in self?.begins += 1 }, endFeedback: {}
            )
            controller.loadViewIfNeeded()
        }

        /// A user's tap. `sendActions` would also fire a control no finger can
        /// reach, so that is a failure here and nothing is sent.
        func tap(file: StaticString = #filePath, line: UInt = #line) throws {
            let button = try XCTUnwrap(controller.applePayNoBalanceButton, file: file, line: line)
            if let reason = unreachable(button) {
                return XCTFail("Tapped a CTA no user can tap: \(reason)", file: file, line: line)
            }
            quotedProductID = controller.noBalancePurchase.offer?.productID
            var lines: [LoggedLine] = []
            AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
                button.sendActions(for: .touchUpInside)
            })
            logged += lines
        }

        /// Why no finger reaches `button`, or `nil` when one does: disabled, or
        /// it or an ancestor up to the screen's view is hidden, transparent to
        /// hit-testing, or not interactive.
        private func unreachable(_ button: UIControl) -> String? {
            guard button.isEnabled else { return "disabled" }
            var view: UIView? = button
            while let current = view {
                let name = String(describing: type(of: current))
                if current.isHidden { return "\(name) is hidden" }
                if current.alpha < 0.01 { return "\(name) is transparent" }
                if !current.isUserInteractionEnabled { return "\(name) takes no touches" }
                if current === controller.view { return nil }
                view = current.superview
            }
            return "not on the screen's view"
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
