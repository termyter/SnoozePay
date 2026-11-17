import XCTest
@testable import SnoozePay

/// The notification-action snooze charges through `BalanceService.priceContext`
/// and `SnoozePriceResolver` (#1130): exactly today's number in roubles, the
/// resolved tier price elsewhere, nothing at all when the scale is unknown.
final class AlarmFiringCoordinatorPriceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var repository: TransactionRepository!
    private var alarmRepo: AlarmRepository!
    private var scaleStore: SnoozePriceScaleStore!
    private var balance: BalanceService!
    private var coordinator: AlarmFiringCoordinator!

    private let usd = Currency(code: "USD")!
    private var usdScale: SnoozePriceScale { SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])! }

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        let center = NotificationCenter()
        repository = TransactionRepository(defaults: defaults)
        alarmRepo = AlarmRepository(defaults: defaults)
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        balance = BalanceService(
            defaults: defaults,
            transactionRepository: repository,
            notificationCenter: center,
            priceScaleStore: scaleStore
        )
        coordinator = AlarmFiringCoordinator(
            alarmRepository: alarmRepo,
            balanceService: balance,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())
        )
    }

    override func tearDown() {
        coordinator = nil
        balance = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func save(_ alarm: Alarm) -> Alarm {
        alarmRepo.save(alarm)
        return alarm
    }

    private func snooze(
        _ alarm: Alarm, toCount count: Int, file: StaticString = #filePath, line: UInt = #line
    ) -> AlarmFiringCoordinator.SnoozeOutcome? {
        let done = expectation(description: "handleSnooze completion")
        var captured: AlarmFiringCoordinator.SnoozeOutcome?
        let userInfo = AlarmNotificationPayload(alarm: alarm, snoozeCount: count - 1).asUserInfo()
        coordinator.handleSnooze(userInfo: userInfo) { outcome in
            captured = outcome
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        if captured == nil { XCTFail("handleSnooze never resolved", file: file, line: line) }
        return captured
    }

    private var rows: [Transaction] { (try? repository.fetchAllChecked()) ?? [] }
    private var charges: [Transaction] { rows.filter { $0.type == .charge } }

    // MARK: - Rouble parity

    func testRoubleWallet_chargesExactlyAlarmPenalty_forEveryPresetCountAndMode() {
        XCTAssertTrue(balance.topUp(amount: 100_000))
        assertChargesEqualAlarmPenalty()
    }

    /// #1136 item 4: a wallet whose rouble currency is stored (frozen by a paid
    /// purchase) resolves through branch 1 of `priceContext`, not the legacy one.
    func testStoredRoubleWallet_chargesExactlyAlarmPenalty_forEveryPresetCountAndMode() {
        XCTAssertEqual(balance.topUpFromPurchase(amount: 100_000, currency: .rub), .credited)
        XCTAssertEqual(balance.storedWalletCurrency, .rub)
        assertChargesEqualAlarmPenalty()
    }

    /// Presets plus fractional legacy amounts (49.5, 0.1) a free-entry field
    /// may have stored. The balance delta is taken in `Decimal`, as the ledger
    /// sums it: in `Double`, 100000 − 99999.9 is not 0.1.
    private func assertChargesEqualAlarmPenalty() {
        for amount in [20.0, 50, 100, 200, 500, 49.5, 0.1] {
            for progressive in [false, true] {
                let alarm = save(Alarm(penaltyAmount: amount, progressiveScale: progressive))
                for count in 1...6 {
                    let expected = alarm.penalty(forSnoozeCount: count)
                    let before = balance.balance
                    let earlier = Set(charges.map(\.id))
                    let label = "amount=\(amount) progressive=\(progressive) count=\(count)"

                    XCTAssertEqual(
                        snooze(alarm, toCount: count), .scheduled(newSnoozeCount: count, charged: expected), label
                    )
                    XCTAssertEqual(MoneyDecimal.subtracting(before, balance.balance), expected, label)
                    let new = charges.filter { !earlier.contains($0.id) }
                    XCTAssertEqual(new.map(\.amount), [expected], label)
                    XCTAssertEqual(new.map(\.currency), [.rub], label)
                }
            }
        }
    }

    func testRoubleWallet_tierAlarm_chargesTheConstantRoubleTier() {
        XCTAssertTrue(balance.topUp(amount: 1000))
        let alarm = save(Alarm(penaltyAmount: 50).with(price: .tier(.high), progressiveScale: true))

        XCTAssertEqual(snooze(alarm, toCount: 2), .scheduled(newSnoozeCount: 2, charged: 400))
        XCTAssertEqual(balance.balance, 600)
    }

    // MARK: - Foreign wallet

    func testDollarWallet_tierAlarm_chargesTheResolvedProgressivePrice() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(balance.topUpFromPurchase(amount: 20, currency: usd), .credited)
        let alarm = save(Alarm(penaltyAmount: 50).with(price: .tier(.mid), progressiveScale: true))

        XCTAssertEqual(snooze(alarm, toCount: 3), .scheduled(newSnoozeCount: 3, charged: 7.96))
        XCTAssertEqual(balance.balance, 12.04)
        XCTAssertEqual(charges.map(\.amount), [7.96])
        XCTAssertEqual(charges.map(\.currency), [usd])
    }

    func testDollarWallet_legacyAmountAlarm_chargesItsTier_notTheRoubleNumber() {
        XCTAssertTrue(scaleStore.record(usdScale))
        XCTAssertEqual(balance.topUpFromPurchase(amount: 100, currency: usd), .credited)
        let alarm = save(Alarm(penaltyAmount: 50))

        XCTAssertEqual(snooze(alarm, toCount: 1), .scheduled(newSnoozeCount: 1, charged: 0.99))
        XCTAssertEqual(balance.balance, 99.01)
    }

    func testDollarWallet_storePricePrecisionArtefact_chargesTheMinorUnitPrice() {
        defaults.set(
            ["USD": [SnoozePriceScaleStore.tiersField: ["0.99", "1.9899999999", "2.99"]]],
            forKey: SnoozePriceScaleStore.scalesKey
        )
        XCTAssertEqual(balance.topUpFromPurchase(amount: 20, currency: usd), .credited)
        let alarm = save(Alarm(penaltyAmount: 50).with(price: .tier(.mid)))

        XCTAssertEqual(snooze(alarm, toCount: 1), .scheduled(newSnoozeCount: 1, charged: 1.99))
        XCTAssertEqual(charges.map(\.amount), [1.99])
    }

    // MARK: - Refusals

    func testDollarWallet_withoutCachedScale_chargesNothingAndRefuses() {
        XCTAssertEqual(balance.topUpFromPurchase(amount: 20, currency: usd), .credited)
        let rowsBefore = rows.count
        let alarm = save(Alarm(penaltyAmount: 50).with(price: .tier(.low)))

        XCTAssertEqual(snooze(alarm, toCount: 1), .priceUnavailable(currency: usd))
        XCTAssertEqual(balance.balance, 20)
        XCTAssertEqual(rows.count, rowsBefore, "no ledger row for an unresolvable price")
        XCTAssertTrue(charges.isEmpty)
    }

    /// #1136: the refusal is the wallet's own reason, a currency mismatch —
    /// no longer reported as insufficient funds.
    func testPristineWallet_onForeignStorefront_chargesNothingAndStaysPristine() {
        XCTAssertTrue(scaleStore.record(usdScale))
        let alarm = save(Alarm(penaltyAmount: 50))

        XCTAssertEqual(snooze(alarm, toCount: 1), .currencyMismatch(price: usd, wallet: .rub))
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(balance.walletIsPristine)
        XCTAssertNil(defaults.object(forKey: WalletCurrencyStore.storageKey))
    }
}
