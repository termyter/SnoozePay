import XCTest
@testable import SnoozePay

/// The firing screen charges through the snooze-price context, locked once per
/// ring (#1137): exactly `alarm.penalty` in roubles, the resolved tier price in a
/// foreign wallet, nothing at all when the price is unavailable or denominated in
/// a currency the wallet does not hold.
final class AlarmFiringPriceLockTests: XCTestCase {

    private var defaults: UserDefaults!
    private var repository: TransactionRepository!
    private var scaleStore: SnoozePriceScaleStore!
    private var wallet: BalanceService!

    private let usd = Currency(code: "USD")!
    private var usdScale: SnoozePriceScale { SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])! }
    private let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        let center = NotificationCenter()
        repository = TransactionRepository(defaults: defaults)
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        wallet = BalanceService(
            defaults: defaults, transactionRepository: repository,
            notificationCenter: center, priceScaleStore: scaleStore
        )
    }

    override func tearDown() {
        wallet = nil
        scaleStore = nil
        repository = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeViewModel(_ alarm: Alarm, snoozeCount: Int = 0) -> AlarmFiringViewModel {
        AlarmFiringViewModel(
            alarm: alarm, snoozeCount: snoozeCount, balanceService: wallet,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults), ledger: repository
        )
    }

    /// Charge rows, oldest first.
    private var charges: [Transaction] {
        ((try? repository.fetchAllChecked()) ?? []).filter { $0.type == .charge }.sorted { $0.createdAt < $1.createdAt }
    }

    private func fund(_ amount: Double, in currency: Currency) {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: amount, currency: currency), .credited)
    }

    /// Snoozes and waits for the scheduler, so the next snooze is not refused as busy.
    private func snoozeAndSettle(_ model: AlarmFiringViewModel, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(description: "snooze scheduled")
        XCTAssertTrue(model.snooze { _ in done.fulfill() }, file: file, line: line)
        wait(for: [done], timeout: 5)
    }

    // MARK: - Rouble parity

    func testRoubleWallet_chargesSufficiencyAndLadderEqualAlarmPenalty() throws {
        fund(1_000_000, in: .rub)
        for amount in [20.0, 50, 100, 200, 500, 49.5] {
            for progressive in [false, true] {
                let alarm = Alarm(penaltyAmount: amount, progressiveScale: progressive)
                for count in 1...6 {
                    let expected = alarm.penalty(forSnoozeCount: count)
                    let model = makeViewModel(alarm, snoozeCount: count - 1)
                    let label = "\(amount) progressive=\(progressive) count=\(count)"
                    XCTAssertEqual(model.currentPenalty, expected, label)
                    XCTAssertEqual(model.currentPrice, Money(Decimal(string: "\(expected)")!, currency: .rub), label)
                    XCTAssertTrue(model.canSnooze, label)
                    if progressive {
                        let ladder = (1...4).map { alarm.penalty(forSnoozeCount: $0) }
                        XCTAssertEqual(model.ladderSteps.map(\.amount), ladder, label)
                    }
                    let before = Set(charges.map(\.id))
                    XCTAssertTrue(model.snooze(), label)
                    let charge = try XCTUnwrap(charges.first { !before.contains($0.id) }, label)
                    XCTAssertEqual(charge.amount, expected, label)
                    XCTAssertEqual(charge.currency, .rub, label)
                    XCTAssertEqual(model.lastChargeAmount, expected, label)
                }
            }
        }
    }

    func testRoubleWallet_sufficiencyEdgeIsTheExactPenalty() {
        fund(49.5, in: .rub)
        XCTAssertTrue(makeViewModel(Alarm(penaltyAmount: 49.5)).canSnooze)
        XCTAssertFalse(makeViewModel(Alarm(penaltyAmount: 50)).canSnooze)
    }

    // MARK: - Foreign wallet with a cached scale

    func testDollarWallet_legacyFiftyChargesTheLowTier_progressiveDoublesToTheCap() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fund(100, in: usd)
        let model = makeViewModel(Alarm(penaltyAmount: 50, progressiveScale: true))

        XCTAssertEqual(model.currentPrice, Money(Decimal(string: "0.99")!, currency: usd))
        XCTAssertEqual(model.ladderSteps.map(\.amount), [0.99, 1.98, 3.96, 7.92])
        for _ in 1...6 { snoozeAndSettle(model) }

        XCTAssertEqual(charges.map(\.amount), [0.99, 1.98, 3.96, 7.92, 7.92, 7.92])
        XCTAssertEqual(Set(charges.map(\.currency)), [usd])
        XCTAssertEqual(model.lastChargeAmount, 7.92)
    }

    // MARK: - Price lock

    func testScaleRecordedMidRing_lockedPriceIsStillCharged() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fund(100, in: usd)
        let model = makeViewModel(Alarm(penaltyAmount: 50))

        let raised = SnoozePriceScale(currency: usd, tierStrings: ["1.49", "2.49", "3.49"])!
        XCTAssertTrue(scaleStore.record(raised))
        XCTAssertEqual(wallet.priceContext, .scale(raised), "the wallet's context really moved")

        XCTAssertEqual(model.currentPrice, Money(Decimal(string: "0.99")!, currency: usd))
        snoozeAndSettle(model)
        snoozeAndSettle(model)
        XCTAssertEqual(charges.map(\.amount), [0.99, 0.99])
    }

    // MARK: - Refund (review of #1140)

    func testLockedDollarPrice_scheduleFails_refundsTheProgressiveChargeLinkedToIt() throws {
        XCTAssertTrue(scaleStore.record(usdScale))
        fund(10, in: usd)
        let failing = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend(failSnooze: true))
        let model = AlarmFiringViewModel(
            alarm: Alarm(penaltyAmount: 50, progressiveScale: true), snoozeCount: 1, balanceService: wallet,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: failing),
            scheduler: failing, wakeStore: WakeEventStore(defaults: defaults), ledger: repository
        )
        XCTAssertEqual(model.currentPrice, Money(Decimal(string: "1.98")!, currency: usd))

        let done = expectation(description: "schedule outcome")
        var outcome: AlarmFiringViewModel.SnoozeScheduleOutcome?
        XCTAssertTrue(model.snooze { outcome = $0; done.fulfill() })
        wait(for: [done], timeout: 5)

        guard case .scheduleFailed = outcome else { return XCTFail("got \(String(describing: outcome))") }
        let rows = (try? repository.fetchAllChecked()) ?? []
        let charge = try XCTUnwrap(rows.first { $0.type == .charge })
        let refund = try XCTUnwrap(rows.first { $0.type == .refund })
        XCTAssertEqual(charge.amount, 1.98)
        XCTAssertEqual(charge.currency, usd)
        XCTAssertEqual(refund.amount, 1.98)
        XCTAssertEqual(refund.currency, usd)
        XCTAssertEqual(refund.refundsTransactionID, charge.id)
        XCTAssertEqual(wallet.balance, 10)
    }

    // MARK: - Unavailable

    func testUnavailablePrice_refusesWithoutChargeAndStopStillWorks() {
        fund(100, in: usd)  // a dollar wallet whose scale was never cached
        let alarmRepository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        let alarm = Alarm(repeatDays: [], penaltyAmount: 50, progressiveScale: true, enabled: true)
        alarmRepository.save(alarm)
        let model = AlarmFiringViewModel(
            alarm: alarm, balanceService: wallet, alarmRepository: alarmRepository,
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults), ledger: repository
        )

        XCTAssertEqual(model.lockedPriceContext, .unavailable(usd))
        XCTAssertFalse(model.isProgressionAvailable)
        XCTAssertTrue(model.currentPenalty.isNaN)
        XCTAssertNil(model.currentPrice)
        XCTAssertFalse(model.canSnooze)
        XCTAssertEqual(model.ladderSteps, [])
        XCTAssertEqual(model.snoozeButtonTitle, Localized.text("firing.progression.unavailable"))
        XCTAssertFalse(model.snooze())
        XCTAssertEqual(model.snoozeCount, 0)
        XCTAssertTrue(charges.isEmpty)
        XCTAssertEqual(wallet.balance, 100)

        guard case .success = model.dismiss() else { return XCTFail("Stop must still work") }
        XCTAssertEqual(alarmRepository.fetchOrFail(id: alarm.id)?.enabled, false)
    }

    // MARK: - Currency the wallet does not hold

    func testPristineWalletOnForeignStorefront_cannotAffordUntilTopUpInThatCurrency() {
        XCTAssertTrue(scaleStore.record(usdScale))  // pristine wallet: still roubles
        let model = makeViewModel(Alarm(penaltyAmount: 50))

        XCTAssertEqual(model.currentPrice, Money(Decimal(string: "0.99")!, currency: usd))
        XCTAssertTrue(model.isProgressionAvailable, "a real price, not the refusal state")
        XCTAssertFalse(model.canSnooze, "never debit dollars from a rouble wallet")
        XCTAssertFalse(model.snooze())
        XCTAssertTrue(charges.isEmpty)

        fund(1.99, in: usd)  // the top-up path the no-balance state offers
        XCTAssertTrue(model.canSnooze)
        snoozeAndSettle(model)
        XCTAssertEqual(charges.map(\.amount), [0.99])
        XCTAssertEqual(charges.map(\.currency), [usd])
        XCTAssertEqual(wallet.balance, 1, accuracy: 1e-9)
    }

    /// Review of #1140: the catalogue had not loaded when the ring started, so
    /// the lock is roubles; then it loads in USD and a purchase freezes the
    /// wallet in dollars. No top-up can ever pay the locked rouble price, so
    /// the ring refuses rather than keep offering purchases.
    func testWalletFrozenInAnotherCurrencyMidRing_refusesInsteadOfOfferingTopUps() {
        let alarmRepository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        let alarm = Alarm(repeatDays: [], penaltyAmount: 50, enabled: true)
        alarmRepository.save(alarm)
        let model = AlarmFiringViewModel(
            alarm: alarm, balanceService: wallet, alarmRepository: alarmRepository,
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults), ledger: repository
        )
        XCTAssertEqual(model.lockedPriceContext, .scale(.rouble))
        XCTAssertTrue(model.isProgressionAvailable, "pristine rouble wallet: the no-balance route is right")

        XCTAssertTrue(scaleStore.record(usdScale))
        fund(9.99, in: usd)

        XCTAssertTrue(model.isLockedPriceStranded)
        XCTAssertFalse(model.isProgressionAvailable)
        XCTAssertFalse(model.canSnooze)
        XCTAssertTrue(model.currentPenalty.isNaN)
        XCTAssertFalse(model.snooze())
        XCTAssertTrue(charges.isEmpty)
        XCTAssertEqual(wallet.balance, 9.99, accuracy: 1e-9)

        guard case .success = model.dismiss() else { return XCTFail("Stop must still work") }
        XCTAssertEqual(alarmRepository.fetchOrFail(id: alarm.id)?.enabled, false)
    }
}
