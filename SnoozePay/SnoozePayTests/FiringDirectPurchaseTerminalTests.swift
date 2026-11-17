import UIKit
import UserNotifications
import XCTest
@testable import SnoozePay

@MainActor
final class FiringDirectPurchaseTerminalTests: XCTestCase {
    func testActualButtonKeepsPendingBusyAcrossBalanceChangeThenCancellationAllowsRetry() throws {
        let fixture = Fixture()
        let controller = try XCTUnwrap(fixture.controller)
        let button = try XCTUnwrap(controller.applePayNoBalanceButton)
        let chooseAmount = try XCTUnwrap(controller.chooseAmountLink)
        XCTAssertTrue(chooseAmount.isEnabled)
        let initialUpdates = controller.updates
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertEqual(fixture.calls.ends, 0)
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested, [sku(499)])
        XCTAssertEqual(fixture.calls.begins, 1)
        fixture.post(StoreKitService.purchasePendingNotification)
        XCTAssertTrue(fixture.wallet.topUp(amount: 1))
        XCTAssertEqual(controller.updates, initialUpdates + 1)
        XCTAssertTrue(controller.noBalancePurchaseInFlight)
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(chooseAmount.isEnabled)
        chooseAmount.sendActions(for: .touchUpInside)
        controller.noBalanceChooseAmountTapped()
        controller.presentTopUpSheet()
        XCTAssertEqual(controller.sheetPresentations, 0)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested.count, 1)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(chooseAmount.isEnabled)
        chooseAmount.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.sheetPresentations, 1)
        XCTAssertFalse(controller.noBalancePurchaseInFlight)
        XCTAssertTrue(controller.alerts.isEmpty)
        XCTAssertEqual(controller.dismissals, 0)
        XCTAssertEqual(fixture.wallet.balance, 1)
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.center.removals, 3)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertEqual(fixture.calls.ends, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested.count, 2)
        XCTAssertEqual(fixture.calls.begins, 2)
        XCTAssertFalse(button.isEnabled)
    }

    func testFailureAndCompletionOnlyFinishActivePurchaseAndAllowMoreCreditWhenInsufficient() throws {
        let fixture = Fixture()
        let controller = try XCTUnwrap(fixture.controller)
        let button = try XCTUnwrap(controller.applePayNoBalanceButton)
        fixture.post(StoreKitService.purchaseFailedNotification)
        XCTAssertTrue(controller.alerts.isEmpty)
        button.sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchaseFailedNotification, message: "Failure fixture")
        XCTAssertEqual(controller.alerts.map(\.message), ["Failure fixture"])
        XCTAssertEqual(controller.alerts.first?.title, Localized.text("firing.alert.purchase_failed.title"))
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(controller.chooseAmountLink?.isEnabled == true)
        fixture.post(StoreKitService.purchaseFailedNotification)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        XCTAssertEqual(controller.alerts.count, 1)
        XCTAssertEqual(fixture.calls.ends, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(fixture.wallet.topUp(amount: 1))
        let updates = controller.updates
        fixture.post(StoreKitService.purchaseCompletedNotification)
        XCTAssertEqual(controller.updates, updates + 1)
        XCTAssertTrue(controller.noBalanceContainer?.isHidden == false)
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(controller.noBalancePurchaseInFlight)
        XCTAssertTrue(controller.chooseAmountLink?.isEnabled == true)
        XCTAssertEqual(fixture.wallet.balance, 1, "Feedback must not credit the wallet")
        XCTAssertEqual(controller.dismissals, 0)
        XCTAssertEqual(fixture.calls.ends, 2)
        XCTAssertEqual(fixture.center.removals, 6)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        XCTAssertEqual(controller.updates, updates + 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested.count, 3)
        XCTAssertEqual(fixture.calls.begins, 3)
        XCTAssertFalse(button.isEnabled)
    }

    func testGhostStopEndsPendingFeedbackBeforeSummaryAndRestoresStoreKitFallback() throws {
        let fixture = Fixture()
        let controller = try XCTUnwrap(fixture.controller)
        try XCTUnwrap(controller.applePayNoBalanceButton).sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchasePendingNotification)
        let stop = try XCTUnwrap(controller.noBalanceDismissButton)
        XCTAssertTrue(stop.isEnabled)
        XCTAssertTrue(fixture.store.hasPurchaseFeedbackSubscriber)
        var summaries = 0
        controller.onSummaryPresentation = { [calls = fixture.calls, store = fixture.store, center = fixture.center] in
            summaries += 1
            XCTAssertFalse(store.hasPurchaseFeedbackSubscriber)
            XCTAssertEqual(calls.ends, 1)
            XCTAssertEqual(center.removals, 3)
        }
        stop.sendActions(for: .touchUpInside)
        XCTAssertEqual(summaries, 1, "Exercise the real ghost Stop handler without mounting the summary")
        XCTAssertTrue(controller.isStoppedByUser)
        XCTAssertFalse(controller.noBalancePurchaseInFlight)
        fixture.store.postPurchaseFailed("Deferred failure after Stop")
        XCTAssertEqual(fixture.poster.requests.count, 1)
        XCTAssertEqual(fixture.poster.requests.first?.content.body, "Deferred failure after Stop")
        XCTAssertEqual(
            fixture.poster.requests.first?.content.title, Localized.text("deposit.notification.failed.title")
        )
        fixture.post(StoreKitService.purchaseFailedNotification)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertTrue(controller.alerts.isEmpty)
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.center.removals, 3)
        XCTAssertEqual(fixture.wallet.balance, 0)
        XCTAssertEqual(controller.dismissals, 0)
    }

    func testOwnerTeardownBalancesActiveFeedbackAndRemovesAllTokens() throws {
        weak var controller: PurchaseController?
        weak var owner: AlarmFiringNoBalancePurchase?
        let fixture = try autoreleasepool {
            let fixture = Fixture()
            controller = fixture.controller
            owner = fixture.controller?.noBalancePurchase
            try XCTUnwrap(fixture.controller?.applePayNoBalanceButton).sendActions(for: .touchUpInside)
            XCTAssertEqual(fixture.calls.begins, 1)
            fixture.controller = nil
            return fixture
        }
        XCTAssertNil(controller)
        XCTAssertNil(owner)
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.center.removals, 5)
        fixture.post(StoreKitService.purchaseFailedNotification)
        fixture.post(StoreKitService.purchaseCompletedNotification)
        fixture.post(StoreKitService.purchaseCancelledNotification)
        XCTAssertTrue(fixture.wallet.topUp(amount: 1))
        XCTAssertEqual(fixture.calls.ends, 1)
        XCTAssertEqual(fixture.calls.requested.count, 1)
        XCTAssertTrue(fixture.backend.scheduledIDs.isEmpty)
        XCTAssertTrue(fixture.backend.snoozedIDs.isEmpty)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
    }

    func testCatalogRefreshReplacesOnlyChangedPriceAndNeverReenablesBusyOrRemovedOffers() throws {
        let fixture = Fixture(available: false)
        let controller = try XCTUnwrap(fixture.controller)
        let empty = try XCTUnwrap(controller.applePayNoBalanceButton)
        XCTAssertFalse(empty.isEnabled)
        XCTAssertEqual(fixture.wallet.balance, 0)
        controller.noBalanceApplePayTapped()
        XCTAssertTrue(fixture.calls.requested.isEmpty)
        fixture.offer = TopUpOffer(productID: sku(499), price: 4.99,
                                   currencyCode: "USD", displayPrice: "$4.99")
        fixture.post(StoreKitService.productsLoadedNotification)
        let loaded = try XCTUnwrap(controller.applePayNoBalanceButton)
        XCTAssertFalse(empty === loaded)
        XCTAssertNil(empty.superview)
        XCTAssertTrue(loaded.isEnabled)
        fixture.post(StoreKitService.productsLoadedNotification)
        XCTAssertTrue(loaded === controller.applePayNoBalanceButton)
        loaded.sendActions(for: .touchUpInside)
        fixture.post(StoreKitService.purchasePendingNotification)
        fixture.offer = TopUpOffer(productID: sku(499), price: 4.99,
                                   currencyCode: "EUR", displayPrice: "4,99 €")
        fixture.post(StoreKitService.productsLoadedNotification)
        let changed = try XCTUnwrap(controller.applePayNoBalanceButton)
        XCTAssertFalse(changed === loaded)
        XCTAssertEqual(changed.accessibilityLabel, Localized.text("common.button.top_up") + ", 4,99 €")
        XCTAssertFalse(changed.isEnabled)
        XCTAssertTrue(controller.noBalancePurchaseInFlight)
        XCTAssertFalse(controller.chooseAmountLink?.isEnabled == true)
        for terminal in [StoreKitService.purchaseCancelledNotification, StoreKitService.purchaseFailedNotification,
                         StoreKitService.purchaseCompletedNotification] {
            fixture.offer = nil
            fixture.post(StoreKitService.productsLoadedNotification)
            XCTAssertTrue(controller.noBalancePurchaseInFlight)
            fixture.post(terminal)
            let unavailable = try XCTUnwrap(controller.applePayNoBalanceButton)
            XCTAssertFalse(unavailable.isEnabled)
            XCTAssertFalse(controller.noBalancePurchaseInFlight)
            let stack = try XCTUnwrap(controller.noBalanceContainer)
            XCTAssertTrue(stack.arrangedSubviews[1] === unavailable)
            XCTAssertEqual(stack.arrangedSubviews.filter {
                $0.accessibilityIdentifier == "firing.noBalance.topUpButton"
            }.count, 1)
            controller.noBalanceApplePayTapped()
            fixture.offer = TopUpOffer(productID: sku(499), price: 499.49,
                                       currencyCode: "RUB", displayPrice: "499,49 RUB")
            fixture.post(StoreKitService.productsLoadedNotification)
            controller.applePayNoBalanceButton?.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(fixture.calls.requested,
                       Array(repeating: sku(499), count: 4))
    }

    func testInjectedWalletAllowsFirstForeignPurchaseAndRefusesEstablishedRublesWithoutMutation() throws {
        for pristine in [true, false] {
            let fixture = Fixture()
            if !pristine { XCTAssertEqual(fixture.wallet.topUpFromPurchase(amount: 1, currency: .rub), .credited) }
            fixture.offer = TopUpOffer(productID: sku(499), price: 4.99,
                                       currencyCode: "USD", displayPrice: "$4.99")
            fixture.post(StoreKitService.productsLoadedNotification)
            let controller = try XCTUnwrap(fixture.controller)
            let before = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
            controller.applePayNoBalanceButton?.sendActions(for: .touchUpInside)
            XCTAssertEqual(fixture.calls.requested.count, pristine ? 1 : 0)
            XCTAssertEqual(controller.noBalancePurchaseInFlight, pristine)
            XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, before)
            if !pristine { XCTAssertEqual(controller.alerts.first?.title, ForeignCurrencyNotice.alertTitle) }
        }
    }

    /// #652: the direct CTA quotes and buys the pack the amount sheet opens on —
    /// never a fixed SKU — for the same wallet, next charge and actual catalogue.
    func testDirectCTABuysTheMinimalSufficientPackTheSheetPreselects() throws {
        let whole = [49, 149, 299, 499, 999]
        let cases = [
            PackCase("RUB", 0, 50, expected: 149), PackCase("RUB", 0, 149, expected: 149),
            PackCase("RUB", 0, 200, expected: 499), PackCase("RUB", 100, 200, expected: 149),
            PackCase("RUB", 0, 600, expected: 999),
            PackCase("RUB", 0, 5000, expected: 999),                 // nothing covers: the largest pack
            PackCase("RUB", 0, 5000, missing: 999, expected: 499),   // largest missing: largest offered
            PackCase("RUB", 0, 200, missing: 499, expected: 999),    // minimal one missing: next sufficient
            PackCase("USD", 1.50, 2.99, expected: 149), PackCase("USD", 0.50, 2.99, expected: 499),
            // #1109: a pristine wallet with a cached dollar scale reckons the dollar price in dollars.
            // Uncached when the ring locked: the price stays roubles, dollar packs have unknown
            // coverage and the cheapest one is quoted (PM default 4 of #1109).
            PackCase("USD", 0, 2.99, expected: 499), PackCase("USD", 0, 2.99, uncached: true, expected: 149),
            // #1112: with the whole catalogue the minimal pack is offered even off the default rows.
            PackCase("RUB", 0, 200, catalogue: whole, expected: 299),
            PackCase("RUB", 0, 30, catalogue: whole, expected: 49),
            PackCase("RUB", 100, 200, catalogue: whole, expected: 149),
            PackCase("RUB", 0, 5000, catalogue: whole, expected: 999)
        ]
        for testCase in cases {
            let currency = try XCTUnwrap(Currency(code: testCase.code))
            // The wallet is banked BEFORE the ring's price is locked (#1137), and a
            // foreign case, banked or pristine, gets the scale whose low tier is this charge.
            let fixture = Fixture(available: false, penalty: testCase.penalty) { wallet, defaults in
                let banked = testCase.banked > 0 ? wallet.topUpFromPurchase(amount: testCase.banked, currency: currency)
                    : .credited
                XCTAssertEqual(banked, .credited)
                guard currency != .rub, !testCase.uncached else { return }
                let low = Decimal(string: "\(testCase.penalty)")!
                let scale = SnoozePriceScale(currency: currency, tiers: [low, low + 1, low + 2])!
                XCTAssertTrue(SnoozePriceScaleStore(defaults: defaults).record(scale))
            }
            let scale = testCase.code == "RUB" ? 1 : 100
            for nominal in testCase.catalogue where nominal != testCase.missing {
                let price = Decimal(nominal) / Decimal(scale)
                fixture.catalog[sku(nominal)] = TopUpOffer(productID: sku(nominal), price: price,
                                                           currencyCode: testCase.code, displayPrice: "\(price) quote")
            }
            fixture.post(StoreKitService.productsLoadedNotification)
            let controller = try XCTUnwrap(fixture.controller), model = controller.viewModel
            let display = try XCTUnwrap(fixture.catalog[sku(testCase.expected)]?.displayPrice)
            let button = try XCTUnwrap(controller.applePayNoBalanceButton)
            XCTAssertEqual(button.accessibilityLabel, Localized.text("common.button.top_up") + ", " + display,
                           "\(testCase)")
            let sheet = FiringTopUpBottomSheetViewController(
                snoozePrice: model.currentPenalty, snoozePriceCurrency: model.priceCurrency, balance: fixture.wallet,
                notificationCenter: fixture.center, pauseLifecycle: { _ in }, preflightRefusal: { _ in nil },
                offerProvider: { [catalog = fixture.catalog] in catalog[$0] }
            )
            sheet.loadViewIfNeeded()
            XCTAssertEqual(descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
                .filter(\.isSelected).map(\.accessibilityIdentifier),
                           ["firingTopUp.preset." + sku(testCase.expected)], "\(testCase)")
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(fixture.calls.requested, [sku(testCase.expected)], "\(testCase)")
        }
    }

    func testDirectCTARequotesOnCatalogueChangesAndStaysHonestWithoutCatalogue() throws {
        let fixture = Fixture(available: false, penalty: 100)
        let controller = try XCTUnwrap(fixture.controller)
        controller.noBalanceApplePayTapped()
        XCTAssertTrue(fixture.calls.requested.isEmpty, "No catalogue: nothing to buy, no nominal fallback")
        XCTAssertFalse(try XCTUnwrap(controller.applePayNoBalanceButton).isEnabled)
        for nominal in [149, 499] {
            fixture.catalog[sku(nominal)] = TopUpOffer(productID: sku(nominal), price: Decimal(nominal),
                                                       currencyCode: "RUB", displayPrice: "\(nominal) RUB")
        }
        fixture.post(StoreKitService.productsLoadedNotification)
        XCTAssertEqual(controller.applePayNoBalanceButton?.accessibilityLabel,
                       Localized.text("common.button.top_up") + ", 149 RUB")
        fixture.catalog[sku(149)] = nil
        fixture.post(StoreKitService.productsLoadedNotification)
        XCTAssertEqual(controller.applePayNoBalanceButton?.accessibilityLabel,
                       Localized.text("common.button.top_up") + ", 499 RUB")
        controller.applePayNoBalanceButton?.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.calls.requested, [sku(499)])
    }

    #if DEBUG
    func testRealTourFactoryEnablesDemoOnlyExplicitlyAndCreditsItsBoundWallet() throws {
        for arguments in [[], ["-uitour", "firing-nobalance"], [StoreKitService.emptyCatalogArgument]] {
            let fixture = Fixture()
            let controller = UITourRoutes.makeNoBalanceFiringController(
                arguments: arguments, balance: fixture.wallet, controllerBuilder: PurchaseController.init(viewModel:)
            )
            XCTAssertEqual(controller.viewModel.balance, 0)
            let demo = StoreKitService.isCatalogForcedEmpty(arguments: arguments)
            XCTAssertEqual(controller.noBalancePurchase.dispatch != nil, demo)
            if demo {
                controller.loadViewIfNeeded()
                let button = try XCTUnwrap(controller.applePayNoBalanceButton)
                XCTAssertTrue(button.isEnabled)
                // 149 is the minimal demo pack covering the sample's 50 charge (#652).
                let quote = MoneyFormatter.string(149.0, currency: .rub)
                XCTAssertEqual(button.accessibilityLabel, Localized.text("common.button.top_up") + ", " + quote)
                button.sendActions(for: .touchUpInside)
                XCTAssertEqual(fixture.wallet.balance, 149)
                XCTAssertEqual(controller.viewModel.balance, 149)
                XCTAssertFalse(controller.noBalancePurchaseInFlight)
                XCTAssertTrue(controller.noBalanceContainer?.isHidden == true)
            } else { XCTAssertEqual(fixture.wallet.balance, 0) }
        }
    }
    #endif

    private final class Calls {
        var requested: [String] = []
        var begins = 0
        var ends = 0
    }

    @MainActor
    private final class Fixture {
        private let lease: IsolatedDefaultsLease<UserDefaults>
        var suite: String { lease.name }
        let center = TrackingCenter()
        let calls = Calls()
        let backend = TestAlarmKitBackend()
        let defaults: UserDefaults
        let wallet: BalanceService
        let poster = LocalNotificationPosterSpy()
        let store: StoreKitService
        var controller: PurchaseController?
        var offer: TopUpOffer?
        var catalog: [String: TopUpOffer] = [:]

        init(
            available: Bool = true, penalty: Double = 50,
            beforeRing: ((BalanceService, UserDefaults) -> Void)? = nil
        ) {
            lease = IsolatedDefaultsPool.checkOut()
            defaults = lease.defaults
            wallet = BalanceService(defaults: defaults, notificationCenter: center)
            beforeRing?(wallet, defaults)
            store = StoreKitService(notificationPoster: poster, defaults: defaults, startListener: false)
            if available { offer = TopUpOffer(productID: sku(499),
                                              price: 499, currencyCode: "RUB", displayPrice: "499 RUB") }
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
            let model = AlarmFiringViewModel(
                alarm: Alarm(penaltyAmount: penalty), balanceService: wallet,
                alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler), scheduler: scheduler,
                wakeStore: WakeEventStore(defaults: defaults), ledger: TransactionRepository(defaults: defaults)
            )
            let controller = PurchaseController(viewModel: model)
            self.controller = controller
            controller.noBalancePurchase = AlarmFiringNoBalancePurchase(
                controller: controller, center: center, dispatch: { [calls] in calls.requested.append($0) },
                offerProvider: { [weak self] in self?.catalog[$0] ?? self?.offer },
                beginFeedback: { [calls, store] in calls.begins += 1; store.beginObservingPurchaseFeedback() },
                endFeedback: { [calls, store] in calls.ends += 1; store.endObservingPurchaseFeedback() }
            )
            controller.loadViewIfNeeded()
            controller.observeBalanceForNoBalanceState()
            controller.observeBalanceForNoBalanceState()
        }

        isolated deinit { IsolatedDefaultsPool.checkIn(lease) }

        func post(_ name: Notification.Name, message: String? = nil) {
            center.post(name: name, object: nil, userInfo: message.map { [StoreKitService.messageUserInfoKey: $0] })
        }
    }
}

@MainActor
private final class PurchaseController: AlarmFiringViewController {
    var updates = 0
    var alerts: [UIAlertController] = []
    var dismissals = 0
    var sheetPresentations = 0
    var onSummaryPresentation: (() -> Void)?
    override func viewDidLoad() { buildFiringLayout() }
    override func updateUI() { updates += 1; super.updateUI() }
    override func present(
        _ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil
    ) {
        if let alert = viewControllerToPresent as? UIAlertController { alerts.append(alert) }
        if viewControllerToPresent is FiringTopUpBottomSheetViewController { sheetPresentations += 1 }
        if viewControllerToPresent is WokeMorningViewController { onSummaryPresentation?() }
    }
    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) { dismissals += 1 }
}

private final class TrackingCenter: NotificationCenter, @unchecked Sendable {
    nonisolated(unsafe) private(set) var removals = 0
    override func removeObserver(_ observer: Any) {
        removals += 1
        super.removeObserver(observer)
    }
}

private struct PackCase {
    let code: String
    let banked: Double
    let penalty: Double
    let missing: Int?
    let uncached: Bool
    let catalogue: [Int]
    let expected: Int

    init(_ code: String, _ banked: Double, _ penalty: Double, missing: Int? = nil, uncached: Bool = false,
         catalogue: [Int] = [149, 499, 999], expected: Int) {
        self.code = code
        self.banked = banked
        self.penalty = penalty
        self.missing = missing
        self.uncached = uncached
        self.catalogue = catalogue
        self.expected = expected
    }
}

private func sku(_ nominal: Int) -> String { "io.mobilife.snoozepay.balance.\(nominal)" }
private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
