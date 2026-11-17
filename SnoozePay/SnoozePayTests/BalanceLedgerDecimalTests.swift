import XCTest
@testable import SnoozePay

/// Ledger sums and affordability are decimal money, not binary fractions
/// (#1119). In `Double`, ordinary store prices drift: 1.99 + 1.99 − 2.99 − 0.99
/// is −2.2e-16, which latched a healthy wallet as corrupt, and 3.98 − 2.99 is
/// 0.9899999999999998, which could not afford a 0.99 snooze.
final class BalanceLedgerDecimalTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.balanceLedgerDecimal.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeService(balance: Double = 0) -> BalanceService {
        testDefaults.set(balance, forKey: "user_balance")
        return BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())
    }

    private let usd = Currency(code: "USD")!

    // MARK: - Pure sum

    func testNet_storePricesThatCancel_sumToExactlyZero() {
        let entries = [
            Transaction(type: .topup, amount: 1.99, currency: usd),
            Transaction(type: .topup, amount: 1.99, currency: usd),
            Transaction(type: .charge, amount: 2.99, currency: usd),
            Transaction(type: .charge, amount: 0.99, currency: usd)
        ]

        let net = BalanceLedger.net(of: entries, in: usd)

        XCTAssertEqual(net.bitPattern, (0.0).bitPattern,
                       "1.99 + 1.99 − 2.99 − 0.99 is zero, not \(net)")
    }

    func testNet_storePrices_landOnTheDisplayedCents() {
        let entries = [
            Transaction(type: .topup, amount: 1.99, currency: usd),
            Transaction(type: .topup, amount: 1.99, currency: usd),
            Transaction(type: .charge, amount: 2.99, currency: usd)
        ]

        XCTAssertEqual(BalanceLedger.net(of: entries, in: usd), 0.99,
                       "The wallet holds the 0.99 the user sees, not 0.9899999999999998")
    }

    /// Roubles are integers, which `Double` already sums exactly; the decimal
    /// path must hand back the very same bits.
    func testNet_roubleIntegerLedger_isBitIdenticalToTheDoubleSum() {
        let amounts: [(TransactionType, Double)] = [
            (.topup, 999), (.charge, 50), (.charge, 100), (.promotion, 200),
            (.charge, 200), (.refund, 100), (.topup, 149), (.charge, 20),
            (.topup, 1_000_000_000), (.charge, 500), (.topup, 49)
        ]
        let entries = amounts.map { Transaction(type: $0.0, amount: $0.1) }
        let expected = amounts.reduce(0.0) { total, row in
            row.0 == .charge ? total - row.1 : total + row.1
        }

        XCTAssertEqual(BalanceLedger.net(of: entries, in: .legacyDefault).bitPattern, expected.bitPattern)
    }

    func testNet_fractionalRows_stillSkipDuplicatesForeignAndInvalid() {
        let replayed = Transaction(type: .topup, amount: 1.99, currency: usd)
        let entries = [
            replayed, replayed, replayed,
            Transaction(type: .topup, amount: 0.99, currency: .legacyDefault),
            Transaction(type: .topup, amount: .nan, currency: usd),
            Transaction(type: .topup, amount: .infinity, currency: usd),
            Transaction(type: .charge, amount: -0.99, currency: usd),
            Transaction(type: .charge, amount: 0, currency: usd),
            Transaction(type: .unknown("voucher"), amount: 0.99, currency: usd)
        ]

        XCTAssertEqual(BalanceLedger.net(of: entries, in: usd), 1.99,
                       "Only the one copy of the replayed 1.99 counts")
    }

    // MARK: - Wallet

    func testBalance_ledgerOfCancellingStorePrices_isZeroAndNotCorrupt() {
        let service = makeService(balance: 0)
        XCTAssertEqual(service.balance, 0)
        let ledger = TransactionRepository(defaults: testDefaults)
        for (type, amount) in [(TransactionType.topup, 1.99), (.topup, 1.99), (.charge, 2.99), (.charge, 0.99)] {
            XCTAssertTrue(ledger.record(Transaction(type: type, amount: amount)))
        }

        XCTAssertEqual(service.balance.bitPattern, (0.0).bitPattern)
        XCTAssertFalse(service.balanceCorrupted,
                       "Rounding noise in a sum of store prices is not a corrupt wallet")
    }

    func testCharge_balanceShownAs099_affordsA099Snooze() {
        let service = makeService(balance: 0)
        XCTAssertTrue(service.topUp(amount: 1.99))
        XCTAssertTrue(service.topUp(amount: 1.99))
        XCTAssertTrue(service.charge(amount: 2.99, alarmID: nil))
        XCTAssertEqual(service.balance, 0.99)

        XCTAssertTrue(service.canAfford(0.99), "A balance of 0.99 affords a 0.99 snooze")
        XCTAssertTrue(service.charge(amount: 0.99, alarmID: nil))

        XCTAssertEqual(service.balance.bitPattern, (0.0).bitPattern)
        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertFalse(service.canAfford(0.01), "…and nothing more once it is spent")
    }
}
