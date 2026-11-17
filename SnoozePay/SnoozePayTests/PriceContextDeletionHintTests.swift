import XCTest
@testable import SnoozePay

/// The confirm-delete sheet and the «Хватит на ~N откладываний» hint follow the
/// wallet's price context (#1151): the balance is printed in its display
/// currency, the hint divides by the price the row pill quotes, the low-balance
/// threshold scales with it, an unavailable context invents no count, and
/// rouble contexts render what they rendered before.
///
/// Every wallet lives in an isolated suite (`makeIsolatedDefaults`) with its own
/// `NotificationCenter`: `.shared` follows the scale the host app cached.
@MainActor
final class PriceContextDeletionHintTests: XCTestCase {

    private let usd = Currency(code: "USD")!

    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var scaleStore: SnoozePriceScaleStore!
    private var ledger: TransactionRepository!
    private var wallet: BalanceService!
    private var alarms: AlarmRepository!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        center = NotificationCenter()
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        ledger = TransactionRepository(defaults: defaults)
        wallet = BalanceService(
            defaults: defaults, transactionRepository: ledger,
            notificationCenter: center, priceScaleStore: scaleStore
        )
        alarms = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
    }

    override func tearDown() {
        // The pool empties the suite itself; never write to it from here.
        alarms = nil
        wallet = nil
        ledger = nil
        scaleStore = nil
        center = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func recordScale(_ tiers: [String]) {
        XCTAssertTrue(scaleStore.record(SnoozePriceScale(currency: usd, tierStrings: tiers)!))
    }

    private func fundDollars(_ amount: Double) {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: amount, currency: usd), .credited)
    }

    private func makeListViewModel(_ saved: [Alarm]) -> AlarmsListViewModel {
        saved.forEach { alarms.save($0) }
        let viewModel = AlarmsListViewModel(
            alarmRepository: alarms, balanceService: wallet, transactionRepository: ledger,
            notificationCenter: center, alarmDefaults: AlarmDefaults(defaults: defaults),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
            )
        )
        viewModel.loadData()
        return viewModel
    }

    private func walletHint(_ saved: [Alarm]) -> String? {
        WalletHints.affordHint(
            forBalance: wallet.balance, alarms: saved,
            defaults: AlarmDefaults(defaults: defaults), context: wallet.priceContext
        )
    }

    private func deletionBody() -> String {
        AlarmDeletionCopy.body(balance: wallet.balance, currency: wallet.displayCurrency)
    }

    // MARK: - Deletion sheet

    func testRoubleDeletionBody_isByteIdenticalToTheLegacyFormatter() {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 840.5, currency: nil), .credited)

        XCTAssertEqual(wallet.displayCurrency, .rub)
        XCTAssertEqual(deletionBody(), Localized.format("alarms.delete.reassurance", MoneyFormatter.string(840.5)))
        XCTAssertEqual(
            AlarmDeletionCopy.body(balance: 840, currency: .rub),
            Localized.format("alarms.delete.reassurance", "840\u{202F}₽")
        )
    }

    func testStoredDollarWallet_deletionBodyShowsDollarsNotRoubles() {
        recordScale(["0.99", "1.99", "2.99"])
        fundDollars(1.99)

        let body = deletionBody()
        XCTAssertTrue(body.contains(MoneyFormatter.string(1.99, currency: usd)), body)
        XCTAssertFalse(body.contains("₽"), body)
    }

    func testPristineWalletOnCachedDollarStorefront_deletionBodyShowsDollarZero() {
        recordScale(["0.99", "1.99", "2.99"])

        let body = deletionBody()
        XCTAssertTrue(body.contains(MoneyFormatter.string(0.0, currency: usd)), body)
        XCTAssertFalse(body.contains("₽"), body)
        XCTAssertNil(wallet.storedWalletCurrency, "display only: nothing is frozen")
    }

    // MARK: - Affordability

    func testStoredDollarWallet_legacyFiftyAlarmCountsAtTheLowTier() {
        recordScale(["0.99", "1.99", "2.99"])
        fundDollars(5)
        let saved = [Alarm(penaltyAmount: 50, enabled: true)]
        let viewModel = makeListViewModel(saved)

        XCTAssertEqual(viewModel.currentSnoozePrice, 0.99)
        XCTAssertEqual(viewModel.affordableSnoozeCount, 5)
        XCTAssertEqual(viewModel.balanceHint, Localized.format("common.snooze_affordability", 5))
        XCTAssertEqual(walletHint(saved), viewModel.balanceHint, "both screens answer the same (#546)")
        XCTAssertFalse(viewModel.isLowBalance, "$5.00 is five snoozes, not «under 100»")
    }

    func testStoredDollarWallet_tierProgressiveAndMedianVariants() {
        recordScale(["0.99", "1.99", "2.99"])
        fundDollars(5)
        let cases: [(alarms: [Alarm], price: Double, count: Int)] = [
            ([Alarm(penaltyAmount: 50, penaltyTier: .mid, enabled: true)], 1.99, 2),
            ([Alarm(penaltyAmount: 50, penaltyTier: .high, enabled: true)], 2.99, 1),
            ([Alarm(penaltyAmount: 150, enabled: true)], 2.99, 1),
            ([Alarm(penaltyAmount: 50, progressiveScale: true, enabled: true)], 0.99, 5),
            ([Alarm(penaltyAmount: 50, enabled: true), Alarm(penaltyAmount: 100, enabled: true),
              Alarm(penaltyAmount: 200, enabled: true)], 1.99, 2),
            ([Alarm(penaltyAmount: 200, enabled: false), Alarm(penaltyAmount: 50, enabled: true)], 0.99, 5)
        ]

        let settings = AlarmDefaults(defaults: defaults)
        for (index, testCase) in cases.enumerated() {
            let context = wallet.priceContext
            XCTAssertEqual(
                SnoozeAffordability.currentPrice(alarms: testCase.alarms, defaults: settings, context: context),
                testCase.price, "case \(index)"
            )
            XCTAssertEqual(
                SnoozeAffordability.affordableCount(
                    balance: wallet.balance, alarms: testCase.alarms, defaults: settings, context: context
                ),
                testCase.count, "case \(index)"
            )
            XCTAssertEqual(walletHint(testCase.alarms), Localized.format("common.snooze_affordability", testCase.count))
        }
    }

    /// 0.3 / 0.1 is 2.9999999999999996 in binary: the count must still be 3.
    func testDollarCountAtAnExactMultipleIsNotFlooredBelowIt() {
        recordScale(["0.1", "0.2", "0.3"])
        fundDollars(0.3)

        XCTAssertEqual(
            SnoozeAffordability.affordableCount(
                balance: wallet.balance, alarms: [Alarm(penaltyAmount: 50, enabled: true)],
                defaults: AlarmDefaults(defaults: defaults), context: wallet.priceContext
            ),
            3
        )
    }

    func testDollarLowBalanceThresholdIsTheMidTier() {
        recordScale(["0.99", "1.99", "2.99"])
        fundDollars(1.99)
        XCTAssertTrue(makeListViewModel([]).isLowBalance)
        fundDollars(0.01)
        XCTAssertFalse(makeListViewModel([]).isLowBalance, "$2.00 is above the $1.99 threshold")
    }

    func testRoubleLowBalanceAndCountAreUnchanged() {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 100, currency: nil), .credited)
        let viewModel = makeListViewModel([Alarm(penaltyAmount: 50, enabled: true)])
        XCTAssertTrue(viewModel.isLowBalance)
        XCTAssertEqual(viewModel.currentSnoozePrice, 50)
        XCTAssertEqual(viewModel.balanceHint, "Хватит на ~2 откладывания")

        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1, currency: nil), .credited)
        XCTAssertFalse(makeListViewModel([]).isLowBalance)
    }

    // MARK: - Unavailable context

    func testUnavailableContext_showsNoCountAndOnlyAnEmptyWalletIsLow() {
        fundDollars(1.99)
        XCTAssertEqual(wallet.priceContext, .unavailable(usd))
        let saved = [Alarm(penaltyAmount: 50, enabled: true)]
        let viewModel = makeListViewModel(saved)

        XCTAssertNil(viewModel.currentSnoozePrice)
        XCTAssertNil(viewModel.affordableSnoozeCount)
        XCTAssertNil(viewModel.affordabilityHint)
        XCTAssertNil(viewModel.balanceHint, "no hint line rather than «~0» for a funded wallet")
        XCTAssertNil(walletHint(saved))
        XCTAssertFalse(viewModel.isLowBalance)
        XCTAssertNil(SnoozeAffordability.hint(
            balance: 1.99, alarms: [], defaults: AlarmDefaults(defaults: defaults), context: .unavailable(usd)
        ), "the configured-default fallback does not resolve either")
    }
}
