import XCTest
@testable import SnoozePay

/// #1133: a verified purchase on an unreadable ledger is refused as a locked
/// ledger (`.notRecorded`) whatever it was paid in. An unreadable ledger is
/// also what makes the wallet non-pristine, so a currency check run first named
/// it a currency mismatch. A readable wallet keeps its currency rules.
final class BalanceServiceLockedLedgerPurchaseTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!
    private let unreadable = Data("unreadable ledger".utf8)
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    private func makeService() -> BalanceService {
        BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
    }

    // MARK: - Unreadable ledger

    func testUnreadableLedger_foreignPurchase_isRefusedAsLockedAndTouchesNothing() {
        defaults.set(12.0, forKey: "user_balance")
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        let outcome = service.topUpFromPurchase(amount: 2.99, currency: usd)

        XCTAssertEqual(outcome, .notRecorded, "The ledger is the reason, not the currency")
        XCTAssertNil(service.storedWalletCurrency, "Nothing is frozen")
        XCTAssertEqual(defaults.data(forKey: "stored_transactions"), unreadable)
        XCTAssertEqual(service.balance, 12)
        XCTAssertNil(defaults.object(forKey: LocalBalanceLedgerStore.openingBalanceKey))
    }

    func testUnreadableLedger_establishedWallet_otherCurrency_isRefusedAsLocked() {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        XCTAssertEqual(service.topUpFromPurchase(amount: 2.99, currency: eur), .notRecorded)
        XCTAssertEqual(service.storedWalletCurrency, usd)
        XCTAssertEqual(defaults.data(forKey: "stored_transactions"), unreadable)
    }

    /// Roubles reached the ledger write before and are refused there, as before.
    func testUnreadableLedger_roublePurchase_isStillRefusedAsLocked() {
        defaults.set(5.0, forKey: "user_balance")
        defaults.set(unreadable, forKey: "stored_transactions")
        let service = makeService()

        XCTAssertEqual(service.topUpFromPurchase(amount: 149, currency: .rub), .notRecorded)
        XCTAssertEqual(defaults.data(forKey: "stored_transactions"), unreadable)
        XCTAssertEqual(service.balance, 5)
    }

    // MARK: - Readable wallets keep the currency rules

    func testReadableRoubleWalletWithHistory_foreignPurchase_isStillACurrencyRefusal() {
        let service = makeService()
        XCTAssertTrue(service.topUp(amount: 149))

        let outcome = service.topUpFromPurchase(amount: 2.99, currency: usd)

        XCTAssertEqual(outcome, .refusedCurrency(wallet: .rub, purchase: usd))
        XCTAssertNil(service.storedWalletCurrency)
        XCTAssertEqual(service.balance, 149)
    }

    func testPristineWallet_foreignPurchase_isCreditedAndFreezesTheCurrency() {
        let service = makeService()

        XCTAssertEqual(service.topUpFromPurchase(amount: 2.99, currency: usd), .credited)
        XCTAssertEqual(service.storedWalletCurrency, usd)
        XCTAssertEqual(service.balance, 2.99)
    }
}
