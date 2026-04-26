import XCTest
@testable import SnoozePay

/// Tests for the phase-1 Money-typed wrappers on `BalanceService` (issue #31).
/// The wrappers bridge through `toDouble()` to the legacy `Double` storage
/// until phase 2; these tests pin the input-validation contract and the
/// corruption-fallback semantics of `balanceMoney`.
final class BalanceServiceMoneyAPITests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeService(balance: Double = 0) -> BalanceService {
        testDefaults.set(balance, forKey: "user_balance")
        return BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())
    }

    // MARK: - balanceMoney

    func testBalanceMoney_freshServiceIsZero() {
        let service = makeService(balance: 0)
        XCTAssertEqual(service.balanceMoney, .zero)
    }

    func testBalanceMoney_reflectsPersistedDouble() {
        let service = makeService(balance: 250)
        XCTAssertEqual(service.balanceMoney, Money(250))
    }

    func testBalanceMoney_corruptNegativeFallsBackToZero() {
        // Documented contract: a corrupted negative balance (e.g. from a
        // hypothetical migration bug) must NOT crash. The typed view falls
        // back to `.zero` instead of trapping on `Money(negative) -> nil`.
        let service = makeService(balance: -100)
        XCTAssertEqual(service.balanceMoney, .zero)
    }

    // MARK: - charge(_ Money, alarmID:)

    func testCharge_money_succeedsWhenFundsAvailable() {
        let service = makeService(balance: 100)
        let didCharge = service.charge(Money(50)!, alarmID: nil)
        XCTAssertTrue(didCharge)
        XCTAssertEqual(service.balanceMoney, Money(50))
    }

    func testCharge_money_failsAndLeavesBalanceWhenInsufficient() {
        let service = makeService(balance: 30)
        let didCharge = service.charge(Money(50)!, alarmID: nil)
        XCTAssertFalse(didCharge)
        XCTAssertEqual(service.balanceMoney, Money(30))
    }

    // MARK: - topUp(_ Money)

    func testTopUp_money_increasesBalanceByExactAmount() {
        let service = makeService(balance: 100)
        service.topUp(Money(50)!)
        XCTAssertEqual(service.balanceMoney, Money(150))
    }

    // MARK: - canAfford(_ Money)

    func testCanAfford_money_trueAtExactEquality() {
        let service = makeService(balance: 50)
        XCTAssertTrue(service.canAfford(Money(50)!))
    }

    func testCanAfford_money_falseWhenAboveBalance() {
        let service = makeService(balance: 50)
        XCTAssertFalse(service.canAfford(Money(50.01)!))
    }
}
