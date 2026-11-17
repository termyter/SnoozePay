import XCTest
@testable import SnoozePay

/// #1122: the derived balance is judged and shown at the wallet currency's
/// minor unit. An opening balance adopted by a pre-#1119 build was
/// `cached − Σ` computed in `Double`, so it can carry binary noise
/// (−20.950000000000003); the exact `Decimal` sum over it is then −3e-15 and
/// used to latch a healthy wallet as corrupt.
final class BalanceServiceMinorUnitRoundingTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private let kwd = Currency(code: "KWD")!
    private let jpy = Currency(code: "JPY")!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// The on-disk state a launch finds: wallet currency (nil = legacy rouble
    /// wallet), credit rows, an already adopted opening and the cached balance.
    private func launch(
        currency: Currency?,
        credits: [Double] = [],
        charges: [Double] = [],
        opening: Double,
        cached: Double = 0
    ) -> BalanceService {
        if let currency {
            XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(currency), .frozen(currency))
        }
        let rowCurrency = currency ?? .legacyDefault
        let ledger = TransactionRepository(defaults: defaults)
        for amount in credits {
            XCTAssertTrue(ledger.record(Transaction(type: .topup, amount: amount, currency: rowCurrency)))
        }
        for amount in charges {
            XCTAssertTrue(ledger.record(Transaction(type: .charge, amount: amount, currency: rowCurrency)))
        }
        defaults.set(opening, forKey: LocalBalanceLedgerStore.openingBalanceKey)
        defaults.set(cached, forKey: "user_balance")
        return BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
    }

    // MARK: - Noise is not corruption

    /// The exact case from the issue: 4 × 4.99 + 0.99 = 20.95 over a noisy
    /// opening of −20.950000000000003 sums to −3e-15.
    func testNoisyOpening_summingToZero_isAnEmptyHealthyWallet() {
        let service = launch(currency: usd, credits: [4.99, 4.99, 4.99, 4.99, 0.99], opening: -20.950000000000003)

        XCTAssertFalse(service.balanceCorrupted, "−3e-15 is Double noise, not a wallet below zero")
        XCTAssertNil(service.corruptedRawValue)
        XCTAssertEqual(service.balance.bitPattern, (0.0).bitPattern)
    }

    /// Same opening, one more 2.99: the wallet shows exactly 2.99, not
    /// 2.989999999999999997, and affords a 2.99 charge.
    func testNoisyOpening_showsTheExactCents() {
        let service = launch(currency: usd, credits: [4.99, 4.99, 4.99, 4.99, 0.99, 2.99],
                             opening: -20.950000000000003)

        XCTAssertEqual(service.balance.bitPattern, (2.99).bitPattern)
        XCTAssertEqual(defaults.double(forKey: "user_balance").bitPattern, (2.99).bitPattern,
                       "The cache is repaired to the shown figure")
        XCTAssertTrue(service.canAfford(2.99))
    }

    /// Store prices that already cancel exactly (#1119) still do, with
    /// charges in the mix: 1.99 + 1.99 − 2.99 − 0.99 over a zero opening.
    func testStorePricesThatCancel_stayZeroAndHealthy() {
        let service = launch(currency: usd, credits: [1.99, 1.99], charges: [2.99, 0.99], opening: 0)

        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertEqual(service.balance.bitPattern, (0.0).bitPattern)
    }

    /// Three fraction digits are kept, not cut to cents: 1.235 KWD stays 1.235.
    func testThreeDigitCurrency_keepsItsThirdDigitAndDropsTheNoise() {
        let service = launch(currency: kwd, credits: [1.105, 2.205, 3.305, 1.235], opening: -(6.615.nextUp))

        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertEqual(service.balance.bitPattern, (1.235).bitPattern)
    }

    func testZeroDigitCurrency_roundsToWholeYen() {
        let service = launch(currency: jpy, credits: [150, 1000], opening: -(150.0.nextUp))

        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertEqual(service.balance.bitPattern, (1000.0).bitPattern)
    }

    // MARK: - Real corruption still latches

    func testGenuinelyNegativeLedger_stillLatches() {
        let service = launch(currency: usd, credits: [1.99], opening: -5)

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertEqual(service.corruptedRawValue, -3.01)
        XCTAssertEqual(service.balance, 0)
    }

    /// One cent below zero is a cent the wallet does not have.
    func testOneMinorUnitBelowZero_stillLatches() {
        let service = launch(currency: usd, credits: [0.99], opening: -1)

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertEqual(service.corruptedRawValue, -0.01)
    }

    func testNaNCachedBalance_stillLatches() {
        let service = launch(currency: usd, credits: [1.99], opening: 0, cached: .nan)

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertEqual(service.balance, 0)
    }

    // MARK: - Roubles unchanged

    func testRoubleIntegerLedger_isTheSameSumAsBefore() {
        let service = launch(currency: nil, credits: [999, 149, 49], charges: [50, 100, 200], opening: 300)

        XCTAssertFalse(service.balanceCorrupted)
        XCTAssertEqual(service.balance.bitPattern, (1147.0).bitPattern)
    }

    /// No rounding in roubles at all: a fractional legacy figure is handed back
    /// to the last bit, exactly as before #1122.
    func testRoubleFractionalOpening_isNotRounded() {
        let service = launch(currency: nil, credits: [50], opening: 10.555)

        XCTAssertEqual(service.balance.bitPattern, MoneyDecimal.adding(10.555, 50).bitPattern)
        XCTAssertEqual(service.balance, 60.555)
    }

    func testRoubleNegativeLedger_stillLatches() {
        let service = launch(currency: nil, credits: [50], charges: [100], opening: 0)

        XCTAssertTrue(service.balanceCorrupted)
        XCTAssertEqual(service.corruptedRawValue, -50)
    }

    // MARK: - Helper

    func testRounded_keepsUnbridgeableValuesAsTheyAre() {
        XCTAssertEqual(MoneyDecimal.rounded(-3e-15, toDigits: 2).bitPattern, (0.0).bitPattern)
        XCTAssertEqual(MoneyDecimal.rounded(-0.005, toDigits: 2), -0.01, "Half rounds away from zero")
        XCTAssertEqual(MoneyDecimal.rounded(1e300, toDigits: 2), 1e300, "No Decimal form: unchanged")
        XCTAssertTrue(MoneyDecimal.rounded(.nan, toDigits: 2).isNaN)
    }
}
