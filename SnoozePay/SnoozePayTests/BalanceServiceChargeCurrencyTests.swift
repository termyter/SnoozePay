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

    private var defaults: UserDefaults!
    private var repository: TransactionRepository!
    private var wallet: BalanceService!

    private let usd = Currency(code: "USD")!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        repository = TransactionRepository(defaults: defaults)
        wallet = BalanceService(defaults: defaults, transactionRepository: repository, notificationCenter: NotificationCenter())
    }

    override func tearDown() {
        wallet = nil
        repository = nil
        defaults = nil
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

    /// #1136: every priced debit entry point refuses a rouble amount on a dollar
    /// wallet THROUGH `debit` — its `.error` line is the proof. A caller-side
    /// comparison (what `charge(_: Money)` did) refuses without that line.
    func testEveryPricedEntryPoint_refusesAForeignCurrencyInsideDebit() throws {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 100, currency: usd), .credited)
        let rowsBefore = rows.map(\.id)
        let roubles = try XCTUnwrap(Money(50, currency: .rub))
        let entryPoints: [(String, () -> Bool)] = [
            ("charge(_: Money)", { self.wallet.charge(roubles, alarmID: nil) }),
            ("chargeWithReceipt(expecting:)", {
                self.wallet.chargeWithReceipt(amount: 50, expecting: .rub, alarmID: nil) != nil
            }),
            ("debit", { (try? self.wallet.debit(amount: 50, expecting: .rub, alarmID: nil).get()) != nil })
        ]

        for (name, charge) in entryPoints {
            var errors: [String] = []
            let charged = AppLogger.withTestSink({ category, level, message in
                if category == .balance, level == .error { errors.append(message) }
            }, perform: charge)

            XCTAssertFalse(charged, name)
            XCTAssertEqual(errors, ["charge refused: priced in RUB, wallet in USD"], name)
            XCTAssertEqual(rows.map(\.id), rowsBefore, "\(name): no ledger row")
            XCTAssertEqual(wallet.balance, 100, name)
        }
    }

    func testMoneyCharge_inTheWalletsCurrency_debitsStampedInIt() throws {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 10, currency: usd), .credited)

        XCTAssertTrue(wallet.charge(try XCTUnwrap(Money(Decimal(string: "1.99")!, currency: usd)), alarmID: nil))

        XCTAssertEqual(rows.filter { $0.type == .charge }.map(\.currency), [usd])
        XCTAssertEqual(wallet.balance, 8.01)
    }

    /// The reason comes from `debit`, decided under the queue (#1136).
    func testDebit_namesItsRefusal() {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1, currency: usd), .credited)

        XCTAssertEqual(refusal(amount: 1, .rub), .currencyMismatch(price: .rub, wallet: usd))
        XCTAssertEqual(refusal(amount: 1.01, usd), .insufficientFunds)
        XCTAssertEqual(refusal(amount: .nan, usd), .invalidAmount)
        XCTAssertEqual(refusal(amount: 0, usd), .invalidAmount)
        XCTAssertNil(refusal(amount: 1, usd), "a covered charge in the wallet's currency lands")
        XCTAssertEqual(wallet.balance, 0)
    }

    /// Order inside `debit`: currency mismatch, then corruption, then funds,
    /// then the ledger write. A mismatch is named even on a corrupt wallet.
    func testDebit_currencyMismatchOutranksCorruption_corruptionOutranksFunds() {
        defaults.set(-5.0, forKey: "user_balance")

        XCTAssertEqual(refusal(amount: 1, usd), .currencyMismatch(price: usd, wallet: .rub))
        XCTAssertEqual(refusal(amount: 1, .rub), .balanceCorrupted)
        XCTAssertTrue(rows.isEmpty)
    }

    func testDebit_lockedLedger_isNotRecorded_balanceUnchanged() {
        XCTAssertTrue(wallet.topUp(amount: 100))
        defaults.set(Data("not json".utf8), forKey: "stored_transactions")

        XCTAssertEqual(refusal(amount: 10, .rub), .notRecorded)
        XCTAssertEqual(wallet.balance, 100)
    }

    /// A pristine wallet on a foreign storefront is a new user outside Russia:
    /// the mismatch is expected there and logged at `.default`, not `.error`.
    func testPristineWallet_currencyMismatch_isLoggedAsExpectedState() {
        var levels: [OSLogType] = []
        let outcome = AppLogger.withTestSink({ category, level, _ in
            if category == .balance { levels.append(level) }
        }, perform: { refusal(amount: 1, usd) })

        XCTAssertEqual(outcome, .currencyMismatch(price: usd, wallet: .rub))
        XCTAssertEqual(levels, [.default])
    }

    private func refusal(amount: Double, _ currency: Currency) -> BalanceService.DebitRefusal? {
        if case .failure(let refusal) = wallet.debit(amount: amount, expecting: currency, alarmID: nil) {
            return refusal
        }
        return nil
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
