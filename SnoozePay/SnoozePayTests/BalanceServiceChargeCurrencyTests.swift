import os
import XCTest
@testable import SnoozePay

/// `chargeWithReceipt(amount:expecting:alarmID:)` (#1143): the currency a price
/// was resolved in is compared with the wallet's inside the wallet queue.
///
/// The refusal test funds the wallet on purpose. On a pristine wallet a
/// mismatched charge is refused by the zero balance alone, so deleting the
/// comparison would leave such a test green (the gap #1136 item 1 names).
final class BalanceServiceChargeCurrencyTests: XCTestCase {

    private var repository: TransactionRepository!
    private var wallet: BalanceService!

    private let usd = Currency(code: "USD")!

    override func setUp() {
        super.setUp()
        let defaults = makeIsolatedDefaults()
        repository = TransactionRepository(defaults: defaults)
        wallet = BalanceService(defaults: defaults, transactionRepository: repository, notificationCenter: NotificationCenter())
    }

    override func tearDown() {
        wallet = nil
        repository = nil
        super.tearDown()
    }

    private var rows: [Transaction] { (try? repository.fetchAllChecked()) ?? [] }

    func testDollarWallet_refusesAnAmountPricedInRoubles_noRowBalanceUnchanged() {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 100, currency: usd), .credited)
        let rowsBefore = rows.map(\.id)

        var lines: [(level: OSLogType, message: String)] = []
        let receipt = AppLogger.withTestSink({ category, level, message in
            if category == .balance { lines.append((level, message)) }
        }, perform: {
            wallet.chargeWithReceipt(amount: 50, expecting: .rub, alarmID: UUID())
        })

        XCTAssertNil(receipt, "50 roubles must never be debited as 50 dollars")
        XCTAssertEqual(rows.map(\.id), rowsBefore, "no ledger row")
        XCTAssertEqual(wallet.balance, 100)
        XCTAssertEqual(lines.map(\.level), [.error], "\(lines)")
        XCTAssertTrue(lines.first?.message.contains("RUB") == true, "\(lines)")
    }

    func testDollarWallet_chargesAnAmountPricedInDollars_stampedDollars() throws {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 10, currency: usd), .credited)
        let alarmID = UUID()

        let receipt = try XCTUnwrap(wallet.chargeWithReceipt(amount: 1.98, expecting: usd, alarmID: alarmID))

        XCTAssertEqual(receipt.amount, 1.98)
        XCTAssertEqual(receipt.currency, usd)
        XCTAssertEqual(receipt.alarmID, alarmID.uuidString)
        XCTAssertEqual(rows.filter { $0.type == .charge }.map(\.id), [receipt.id])
        XCTAssertEqual(wallet.balance, 8.02)
    }

    func testRoubleWallet_expectingRoubles_chargesLikeTheUncheckedCall() throws {
        XCTAssertTrue(wallet.topUp(amount: 100))

        let checked = try XCTUnwrap(wallet.chargeWithReceipt(amount: 49.5, expecting: .rub, alarmID: nil))
        let unchecked = try XCTUnwrap(wallet.chargeWithReceipt(amount: 49.5, alarmID: nil))

        XCTAssertEqual(checked.currency, .rub)
        XCTAssertEqual(unchecked.currency, .rub)
        XCTAssertEqual(wallet.balance, 1)
    }

    /// The checked call keeps every refusal of the unchecked one.
    func testExpectedCurrency_stillRefusesInsufficientAndInvalidAmounts() {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1, currency: usd), .credited)

        XCTAssertNil(wallet.chargeWithReceipt(amount: 1.01, expecting: usd, alarmID: nil))
        XCTAssertNil(wallet.chargeWithReceipt(amount: .nan, expecting: usd, alarmID: nil))
        XCTAssertNil(wallet.chargeWithReceipt(amount: -1, expecting: usd, alarmID: nil))
        XCTAssertEqual(wallet.balance, 1)
        XCTAssertTrue(rows.allSatisfy { $0.type == .topup })
    }
}
