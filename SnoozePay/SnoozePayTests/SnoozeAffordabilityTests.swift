import XCTest
@testable import SnoozePay

/// Tests for the shared "Хватит на ~N откладываний" calculation (#546).
///
/// The headline test is `testBothScreensAgree…`: the bug was not that either
/// screen was wrong on its own terms, it was that the two disagreed — 298 ₽ read
/// as "~1 откладывание" on the alarms list and "~5 откладываний при текущей
/// цене" in the wallet, one tap apart. A pair of per-screen tests would have
/// stayed green through that, so the cross-screen assertion is the regression
/// guard and the per-screen ones only explain why.
final class SnoozeAffordabilityTests: XCTestCase {

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var repo: AlarmRepository!
    private var alarmDefaults: AlarmDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.snoozeAffordability.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(
            defaults: testDefaults,
            scheduler: AlarmsListViewModelTests.StubScheduler()
        )
        alarmDefaults = AlarmDefaults(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Alarms-list side: the real VM bound to the isolated store.
    private func makeListViewModel(balance: Double) -> AlarmsListViewModel {
        let center = NotificationCenter()
        testDefaults.set(balance, forKey: "user_balance")
        let viewModel = AlarmsListViewModel(
            alarmRepository: repo,
            balanceService: BalanceService(defaults: testDefaults, notificationCenter: center),
            transactionRepository: TransactionRepository(defaults: testDefaults),
            notificationCenter: center,
            alarmDefaults: alarmDefaults
        )
        viewModel.loadData()
        return viewModel
    }

    /// Wallet side: the same call `WalletViewController.refresh()` makes.
    private func walletHint(balance: Double) -> String {
        WalletHints.affordHint(
            forBalance: balance,
            alarms: repo.fetchAll(),
            defaults: alarmDefaults
        )
    }

    /// The exact state from the #546 screenshot: 298 ₽ and three alarms priced
    /// 200 / 100 / 50, of which the 200 ₽ one ("Рейс в Стамбул") is switched off.
    private func seedIssueScreenshotState() {
        repo.save(Alarm(name: "Рейс в Стамбул", penaltyAmount: 200, enabled: false))
        repo.save(Alarm(name: "Работа", penaltyAmount: 100, enabled: true))
        repo.save(Alarm(name: "Зарядка", penaltyAmount: 50, enabled: true))
    }

    // MARK: - The regression: the two screens must agree

    /// RED before #546: the list rendered "Хватит на ~1 откладывание" (its mode
    /// tie-break picked the 200 ₽ alarm — which is disabled) while the wallet
    /// rendered "Хватит на ~5 откладываний при текущей цене" (298 / hardcoded 50).
    func testBothScreensAgreeOnTheSameBalanceAndAlarms() {
        seedIssueScreenshotState()

        let list = makeListViewModel(balance: 298)

        XCTAssertEqual(
            list.balanceHint,
            walletHint(balance: 298),
            "The alarms list and the wallet must answer 'на сколько хватит' identically (#546)"
        )
    }

    /// The agreement above must not be an agreement on the wrong number: with
    /// enabled prices 50 and 100 the quoted price is 100 ₽, so 298 ₽ buys two.
    func testAgreedNumberIsTheUpperMedianOfEnabledAlarms() {
        seedIssueScreenshotState()

        let list = makeListViewModel(balance: 298)

        XCTAssertEqual(list.currentSnoozePrice, 100, accuracy: 0.0001)
        XCTAssertEqual(list.balanceHint, "Хватит на ~2 откладывания")
        XCTAssertEqual(walletHint(balance: 298), "Хватит на ~2 откладывания")
    }

    /// Both screens stay in step as the balance moves — including the boundary
    /// where the money no longer covers a single snooze.
    func testScreensStayInStepAcrossBalances() {
        seedIssueScreenshotState()

        for balance in [1.0, 99.0, 100.0, 250.0, 298.0, 1000.0, 5000.0] {
            let list = makeListViewModel(balance: balance)
            XCTAssertEqual(
                list.balanceHint,
                walletHint(balance: balance),
                "Screens disagreed at \(balance) ₽"
            )
        }
    }

    // MARK: - What "the current price" is

    /// A switched-off alarm can never charge the user, so it must not decide
    /// the hint. This is what made the screenshot read "~1".
    func testDisabledAlarmDoesNotSetThePrice() {
        repo.save(Alarm(penaltyAmount: 1000, enabled: false))
        repo.save(Alarm(penaltyAmount: 50, enabled: true))

        let list = makeListViewModel(balance: 298)

        XCTAssertEqual(list.currentSnoozePrice, 50, accuracy: 0.0001)
        XCTAssertEqual(list.affordableSnoozeCount, 5)
    }

    /// The degenerate case that the mode produced: all prices distinct, every
    /// frequency 1, so the "most frequent" penalty became the most expensive
    /// one. The median lands in the middle instead.
    func testDistinctPricesDoNotCollapseToTheMostExpensive() {
        let alarms = [
            Alarm(penaltyAmount: 50, enabled: true),
            Alarm(penaltyAmount: 100, enabled: true),
            Alarm(penaltyAmount: 200, enabled: true)
        ]

        XCTAssertEqual(
            SnoozeAffordability.currentPrice(alarms: alarms, defaults: alarmDefaults),
            100,
            accuracy: 0.0001
        )
    }

    /// The property the mode was chosen for in the first place, kept: a single
    /// pricey outlier among cheap alarms does not drag the hint with it.
    func testOutlierDoesNotDragThePrice() {
        var alarms = (0..<4).map { _ in Alarm(penaltyAmount: 50, enabled: true) }
        alarms.append(Alarm(penaltyAmount: 200, enabled: true))

        XCTAssertEqual(
            SnoozeAffordability.currentPrice(alarms: alarms, defaults: alarmDefaults),
            50,
            accuracy: 0.0001
        )
    }

    /// Even counts resolve upward — the hint would rather under-promise than
    /// claim snoozes the user cannot pay for.
    func testEvenCountResolvesToTheUpperMiddle() {
        let alarms = [
            Alarm(penaltyAmount: 50, enabled: true),
            Alarm(penaltyAmount: 200, enabled: true)
        ]

        XCTAssertEqual(
            SnoozeAffordability.currentPrice(alarms: alarms, defaults: alarmDefaults),
            200,
            accuracy: 0.0001
        )
    }

    /// With nothing to measure, the answer is the price the user configured in
    /// Settings — not a private copy of `50` (#546 comment).
    func testFallsBackToTheUserConfiguredDefaultPrice() {
        alarmDefaults.penaltyAmount = 200

        let listNoAlarms = makeListViewModel(balance: 600)
        XCTAssertEqual(listNoAlarms.balanceHint, "Хватит на ~3 откладывания")
        XCTAssertEqual(walletHint(balance: 600), "Хватит на ~3 откладывания")
    }

    /// Only-disabled alarms count as "nothing to measure" too.
    func testAllAlarmsDisabledFallsBackToTheDefaultPrice() {
        alarmDefaults.penaltyAmount = 150
        repo.save(Alarm(penaltyAmount: 1000, enabled: false))

        XCTAssertEqual(
            SnoozeAffordability.currentPrice(alarms: repo.fetchAll(), defaults: alarmDefaults),
            150,
            accuracy: 0.0001
        )
    }

    // MARK: - Pluralisation

    /// "~1 откладываний" was reachable in the wallet, which never declined the
    /// noun at all. 1 / 2 / 5 are the three Russian buckets.
    func testSnoozeWordDeclension() {
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 1), "откладывание")
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 2), "откладывания")
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 5), "откладываний")
        // The traps: teens are all genitive plural, and the buckets repeat
        // above 20.
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 11), "откладываний")
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 14), "откладываний")
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 21), "откладывание")
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 22), "откладывания")
        XCTAssertEqual(SnoozeAffordability.snoozeWord(for: 0), "откладываний")
    }

    /// Both screens decline, on the same three buckets, at 50 ₽ a snooze.
    func testBothScreensDeclineTheNoun() {
        repo.save(Alarm(penaltyAmount: 50, enabled: true))

        let cases: [(balance: Double, expected: String)] = [
            (50, "Хватит на ~1 откладывание"),
            (100, "Хватит на ~2 откладывания"),
            (250, "Хватит на ~5 откладываний")
        ]

        for testCase in cases {
            let list = makeListViewModel(balance: testCase.balance)
            XCTAssertEqual(list.balanceHint, testCase.expected)
            XCTAssertEqual(walletHint(balance: testCase.balance), testCase.expected)
        }
    }

    // MARK: - Empty balance

    /// The wallet keeps its own zero-balance copy — it is the screen with the
    /// top-up button, so it nudges rather than reporting "~0".
    func testWalletEmptyBalanceCopy() {
        repo.save(Alarm(penaltyAmount: 50, enabled: true))

        XCTAssertEqual(walletHint(balance: 0), WalletHints.emptyBalanceHint)
        XCTAssertFalse(WalletHints.emptyBalanceHint.contains("откладываний"))
    }

    /// A balance too small for one snooze reports zero on both screens rather
    /// than the wallet's old `max(1, …)`, which promised a snooze the user
    /// could not pay for — in the wrong grammatical case at that.
    func testBalanceBelowOneSnoozeReportsZeroOnBothScreens() {
        repo.save(Alarm(penaltyAmount: 50, enabled: true))

        let list = makeListViewModel(balance: 30)

        XCTAssertEqual(list.balanceHint, "Хватит на ~0 откладываний")
        XCTAssertEqual(walletHint(balance: 30), "Хватит на ~0 откладываний")
    }
}
