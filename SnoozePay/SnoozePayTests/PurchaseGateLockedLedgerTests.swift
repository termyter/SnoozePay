import UIKit
import XCTest
@testable import SnoozePay

/// #1163: with an unreadable ledger the pre-purchase gate names the locked
/// ledger, not a foreign storefront. An unreadable ledger is also what makes
/// the wallet non-pristine, so the currency check alone refused a first
/// foreign purchase with the currency notice and the user went after the wrong
/// problem. A readable wallet keeps its currency rules; roubles are untouched.
///
/// #1182: the gate runs before StoreKit, so its copy says nothing was charged.
/// The post-charge "couldn't credit" copy stays with the credit path.
@MainActor
final class PurchaseGateLockedLedgerTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!
    private let unreadable = Data("unreadable ledger".utf8)
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var window: UIWindow?

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        center = NotificationCenter()
    }

    override func tearDown() {
        unmount()
        center = nil
        defaults = nil
        super.tearDown()
    }

    private func makeService() -> BalanceService {
        BalanceService(defaults: defaults, notificationCenter: center)
    }

    private static func sku(_ nominal: Int) -> String { "io.mobilife.snoozepay.balance.\(nominal)" }

    private func offer(_ nominal: Int, price: String, code: String, display: String) -> TopUpOffer? {
        TopUpOffer(productID: Self.sku(nominal), price: Decimal(string: price)!,
                   currencyCode: code, displayPrice: display)
    }

    // MARK: - The seam

    func testUnreadableLedger_untouchedWallet_foreignPack_isALockedLedger() {
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        XCTAssertEqual(service.purchaseRefusal(in: usd), .ledgerUnreadable)
        XCTAssertEqual(ForeignCurrencyNotice.blockingMessage(for: service.purchaseRefusal(in: usd)),
                       ForeignCurrencyNotice.ledgerUnreadableMessage)
    }

    /// The refusal reads its own entry, in both shipped languages, and is not
    /// the post-charge credit failure — which keeps its own words.
    func testLockedLedgerRefusal_saysNothingWasCharged_notThatTheCreditFailed() throws {
        let refusal = ForeignCurrencyNotice.blockingMessage(for: .ledgerUnreadable)
        XCTAssertEqual(refusal, Localized.text("deposit.error.ledger_unreadable"))
        XCTAssertNotEqual(refusal, StoreKitService.ledgerLockedFailureMessage)
        XCTAssertEqual(StoreKitService.ledgerLockedFailureMessage, Localized.text("deposit.error.credit_failed"),
                       "The post-charge copy is unchanged")

        let copy = [
            ("ru", "Пополнение приостановлено: не удалось прочитать данные баланса. "
                + "За эту покупку деньги не списаны. Свяжитесь с поддержкой."),
            ("en", "Top-ups are paused: your balance data couldn’t be read. "
                + "You weren’t charged for this purchase. Contact support.")
        ]
        for (language, expected) in copy {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path), language)
            XCTAssertEqual(Localized.text("deposit.error.ledger_unreadable", in: bundle), expected, language)
        }
    }

    /// An established wallet refuses other currencies without looking at the
    /// ledger; the seam still names the ledger first.
    func testUnreadableLedger_establishedWallet_otherCurrency_isALockedLedger() {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        XCTAssertEqual(service.purchaseRefusal(in: eur), .ledgerUnreadable)
        XCTAssertNil(service.purchaseRefusal(in: usd), "The credit seam still lets its own currency reach the write")
        XCTAssertEqual(service.prePurchaseRefusal(in: usd), .ledgerUnreadable,
                       "The gate refuses before Apple charges for a credit that cannot land")
    }

    /// The ledger is damaged after the service was created and read: the latch
    /// is stale, so only a checked read at the gate sees it.
    func testLedgerDamagedAfterLaunch_establishedWallet_ownCurrency_isRefusedAtTheGate() {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
        let service = makeService()
        XCTAssertEqual(service.balance, 0)
        XCTAssertNil(service.prePurchaseRefusal(in: usd), "Readable: the gate is open")

        defaults.set(unreadable, forKey: "stored_transactions")

        XCTAssertEqual(service.prePurchaseRefusal(in: usd), .ledgerUnreadable)
    }

    func testReadableWallet_foreignPack_isStillTheCurrencyNotice() {
        let service = makeService()
        XCTAssertTrue(service.topUp(amount: 149))

        XCTAssertEqual(service.purchaseRefusal(in: usd), .foreignCurrency(wallet: .rub, purchase: usd))
        XCTAssertEqual(ForeignCurrencyNotice.blockingMessage(for: service.purchaseRefusal(in: usd)),
                       ForeignCurrencyNotice.message(wallet: .rub, storefront: usd))
    }

    /// A rouble pack on a legacy wallet passes the gate while the ledger reads,
    /// and is refused there once it does not: dispatching it would charge for
    /// a credit the ledger write refuses.
    func testRoublePack_onLegacyWallet_passesTheGateOnlyWhileTheLedgerReads() {
        let service = makeService()
        XCTAssertTrue(service.topUp(amount: 149))
        XCTAssertNil(service.prePurchaseRefusal(in: .rub))
        XCTAssertNil(ForeignCurrencyNotice.blockingMessage(for: nil))

        defaults.set(unreadable, forKey: "stored_transactions")

        XCTAssertNil(service.purchaseRefusal(in: .rub), "The credit seam is unchanged")
        XCTAssertEqual(service.prePurchaseRefusal(in: .rub), .ledgerUnreadable)
    }

    /// Digits are cached per code; the warm answer is the cold one.
    func testMinorUnitDigits_sameOnColdAndWarmCall() {
        for (code, digits) in [("JPY", 0), ("KWD", 3), ("USD", 2)] {
            let currency = Currency(code: code)!
            XCTAssertEqual(currency.minorUnitDigits, digits, code)
            XCTAssertEqual(currency.minorUnitDigits, digits, "\(code) from the cache")
        }
    }

    // MARK: - Firing sheet

    func testFiringSheet_unreadableLedger_showsTheLockedLedgerAndDispatchesNothing() throws {
        defaults.set(unreadable, forKey: "stored_transactions")
        var requested: [String] = []
        var alerts: [UIAlertController] = []
        let offers = [Self.sku(499): try XCTUnwrap(offer(499, price: "4.99", code: "USD", display: "$4.99"))]
        let sheet = FiringTopUpBottomSheetViewController(
            snoozePrice: 200, balance: makeService(), notificationCenter: center,
            scheduleSuccessDismissal: { _, _ in },
            purchaseProduct: { requested.append($0) },
            presentPurchaseFailure: { alerts.append($0) }, pauseLifecycle: { _ in },
            preflightRefusal: { _ in nil },
            offerProvider: { offers[$0] }, arguments: []
        )
        sheet.loadViewIfNeeded()

        try button(in: sheet, id: "firingTopUp.purchaseButton").sendActions(for: .touchUpInside)

        XCTAssertTrue(requested.isEmpty)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.message, ForeignCurrencyNotice.ledgerUnreadableMessage)
        XCTAssertNotEqual(alerts.first?.message, StoreKitService.ledgerLockedFailureMessage, "Nothing was charged")
        XCTAssertEqual(alerts.first?.title, Localized.text("firing.alert.purchase_failed.title"))
        XCTAssertNotEqual(alerts.first?.title, ForeignCurrencyNotice.alertTitle)
    }

    // MARK: - Deposit sheet

    func testDepositSheet_unreadableLedger_showsTheLockedLedgerAndDispatchesNothing() throws {
        defaults.set(unreadable, forKey: "stored_transactions")
        var requested: [String] = []
        let sheet = try makeDepositSheet(code: "USD", display: "$1.79") { requested.append($0) }

        try button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside)

        XCTAssertTrue(requested.isEmpty)
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController,
                                  presentationDiagnostics(rootedAt: sheet))
        XCTAssertEqual(alert.message, ForeignCurrencyNotice.ledgerUnreadableMessage)
        XCTAssertNotEqual(alert.message, StoreKitService.ledgerLockedFailureMessage, "Nothing was charged")
        XCTAssertEqual(alert.title, Localized.text("common.purchase_failed.title"))
        XCTAssertTrue(try button(in: sheet, id: "deposit.purchaseButton").isEnabled,
                      "The refusal is not a stuck purchase")
    }

    func testDepositSheet_roublePack_isDispatchedOnlyWhileTheLedgerReads() throws {
        for ledgerReads in [true, false] {
            if !ledgerReads { defaults.set(unreadable, forKey: "stored_transactions") }
            var requested: [String] = []
            let sheet = try makeDepositSheet(code: "RUB", display: "149 ₽", price: "149") { requested.append($0) }

            try button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside)

            if ledgerReads {
                XCTAssertEqual(requested, [Self.sku(149)])
                XCTAssertNil(sheet.presentedViewController)
            } else {
                XCTAssertTrue(requested.isEmpty, "A locked ledger must not be charged for")
                let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController,
                                          presentationDiagnostics(rootedAt: sheet))
                XCTAssertEqual(alert.message, ForeignCurrencyNotice.ledgerUnreadableMessage)
            }
            unmount()
        }
    }

    /// Readable ledger, rouble wallet with history, USD pack: the
    /// foreign-currency alert, not the purchase-failed one.
    func testDepositSheet_readableLedger_foreignPack_showsTheCurrencyNotice() throws {
        let service = makeService()
        XCTAssertTrue(service.topUp(amount: 149))
        var requested: [String] = []
        let sheet = try makeDepositSheet(code: "USD", display: "$1.79", balance: service) { requested.append($0) }

        try button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside)

        XCTAssertTrue(requested.isEmpty)
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController,
                                  presentationDiagnostics(rootedAt: sheet))
        XCTAssertEqual(alert.title, ForeignCurrencyNotice.alertTitle)
        XCTAssertEqual(alert.message, ForeignCurrencyNotice.message(wallet: .rub, storefront: usd))
        XCTAssertEqual(alert.actions.map(\.title), [Localized.text("deposit.foreign_currency.dismiss")])
    }

    /// Accepted currencies on a locked ledger: a USD pack on a USD wallet and a
    /// RUB pack on a legacy rouble wallet are both refused before dispatch.
    func testFiringSheet_unreadableLedger_acceptedPack_isNotDispatched() throws {
        for (code, price, display) in [("USD", "4.99", "$4.99"), ("RUB", "499", "499 ₽")] {
            try assertFiringSheetRefusesAsLocked(code: code, price: price, display: display)
        }
    }

    private func assertFiringSheetRefusesAsLocked(code: String, price: String, display: String) throws {
        defaults = makeIsolatedDefaults()
        if code == "USD" { XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd)) }
        defaults.set(unreadable, forKey: "stored_transactions")
        var requested: [String] = []
        var alerts: [UIAlertController] = []
        let offers = [Self.sku(499): try XCTUnwrap(offer(499, price: price, code: code, display: display))]
        let sheet = FiringTopUpBottomSheetViewController(
            snoozePrice: 200, balance: makeService(), notificationCenter: center,
            scheduleSuccessDismissal: { _, _ in },
            purchaseProduct: { requested.append($0) },
            presentPurchaseFailure: { alerts.append($0) }, pauseLifecycle: { _ in },
            preflightRefusal: { _ in nil },
            offerProvider: { offers[$0] }, arguments: []
        )
        sheet.loadViewIfNeeded()

        try button(in: sheet, id: "firingTopUp.purchaseButton").sendActions(for: .touchUpInside)

        XCTAssertTrue(requested.isEmpty, code)
        XCTAssertEqual(alerts.first?.message, ForeignCurrencyNotice.ledgerUnreadableMessage, code)
    }

    // MARK: - Helpers

    private func makeDepositSheet(
        code: String, display: String, price: String = "1.79", balance: BalanceService? = nil,
        purchase: @escaping (String) -> Void
    ) throws -> DepositBottomSheetViewController {
        let offers = [Self.sku(149): try XCTUnwrap(offer(149, price: price, code: code, display: display))]
        let sheet = DepositBottomSheetViewController(
            balance: balance ?? makeService(), notificationCenter: center, scheduleSuccessDismissal: { _, _ in },
            purchaseProduct: purchase, offerProvider: { offers[$0] }
        )
        let host = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        host.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        host.rootViewController = sheet
        host.makeKeyAndVisible()
        window = host
        sheet.loadViewIfNeeded()
        host.layoutIfNeeded()
        return sheet
    }

    /// Balances the appearance the window gave the sheet, so its StoreKit
    /// feedback observers do not outlive the test.
    private func unmount() {
        if let sheet = window?.rootViewController {
            sheet.beginAppearanceTransition(false, animated: false)
            sheet.endAppearanceTransition()
        }
        window?.isHidden = true
        window = nil
    }

    private func button(in sheet: UIViewController, id: String) throws -> SPButton {
        try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? SPButton }.first { $0.accessibilityIdentifier == id })
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
