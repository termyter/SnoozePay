import UIKit
import XCTest
@testable import SnoozePay

/// #1163: with an unreadable ledger the pre-purchase gate names the locked
/// ledger, not a foreign storefront. An unreadable ledger is also what makes
/// the wallet non-pristine, so the currency check alone refused a first
/// foreign purchase with the currency notice and the user went after the wrong
/// problem. A readable wallet keeps its currency rules; roubles are untouched.
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
        window?.isHidden = true
        window = nil
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
                       StoreKitService.ledgerLockedFailureMessage)
    }

    /// An established wallet refuses other currencies without looking at the
    /// ledger; the seam still names the ledger first.
    func testUnreadableLedger_establishedWallet_otherCurrency_isALockedLedger() {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        XCTAssertEqual(service.purchaseRefusal(in: eur), .ledgerUnreadable)
        XCTAssertNil(service.purchaseRefusal(in: usd), "Its own currency still reaches the ledger write")
    }

    func testReadableWallet_foreignPack_isStillTheCurrencyNotice() {
        let service = makeService()
        XCTAssertTrue(service.topUp(amount: 149))

        XCTAssertEqual(service.purchaseRefusal(in: usd), .foreignCurrency(wallet: .rub, purchase: usd))
        XCTAssertEqual(ForeignCurrencyNotice.blockingMessage(for: service.purchaseRefusal(in: usd)),
                       ForeignCurrencyNotice.message(wallet: .rub, storefront: usd))
    }

    /// A rouble pack on a legacy wallet was accepted before and still is: the
    /// gate does not move, the ledger write refuses it as it always did.
    func testRoublePack_onLegacyWallet_passesTheGateWhateverTheLedger() {
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        XCTAssertNil(service.purchaseRefusal(in: .rub))
        XCTAssertNil(ForeignCurrencyNotice.blockingMessage(for: nil))
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
        XCTAssertEqual(alerts.first?.message, StoreKitService.ledgerLockedFailureMessage)
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
        XCTAssertEqual(alert.message, StoreKitService.ledgerLockedFailureMessage)
        XCTAssertEqual(alert.title, Localized.text("common.purchase_failed.title"))
        XCTAssertTrue(try button(in: sheet, id: "deposit.purchaseButton").isEnabled,
                      "The refusal is not a stuck purchase")
    }

    func testDepositSheet_unreadableLedger_roublePack_isStillDispatched() throws {
        defaults.set(unreadable, forKey: "stored_transactions")
        var requested: [String] = []
        let sheet = try makeDepositSheet(code: "RUB", display: "149 ₽", price: "149") { requested.append($0) }

        try button(in: sheet, id: "deposit.purchaseButton").sendActions(for: .touchUpInside)

        XCTAssertEqual(requested, [Self.sku(149)])
        XCTAssertNil(sheet.presentedViewController)
    }

    // MARK: - Helpers

    private func makeDepositSheet(
        code: String, display: String, price: String = "1.79", purchase: @escaping (String) -> Void
    ) throws -> DepositBottomSheetViewController {
        let offers = [Self.sku(149): try XCTUnwrap(offer(149, price: price, code: code, display: display))]
        let sheet = DepositBottomSheetViewController(
            balance: makeService(), notificationCenter: center, scheduleSuccessDismissal: { _, _ in },
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

    private func button(in sheet: UIViewController, id: String) throws -> SPButton {
        try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? SPButton }.first { $0.accessibilityIdentifier == id })
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
