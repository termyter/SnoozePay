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
///
/// Every scenario gets its OWN `UserDefaults` suite. The balance is derived from
/// the ledger (#483): the first read of a suite adopts `openingBalance =
/// user_balance − Σ(rows)`, so re-seeding `user_balance` inside a suite that has
/// already been read does nothing and a second `BalanceService` keeps reporting
/// the first balance. Reusing one suite across balances therefore measures the
/// harness, not the screens.
final class SnoozeAffordabilityTests: XCTestCase {

    /// Suites handed out by `renderBothScreens` — torn down together.
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    // MARK: - Helpers

    /// What each screen renders for one state of the world.
    private struct Screens {
        let list: String
        let wallet: String
        let price: Double
        let count: Int
    }

    /// Builds an isolated world and renders both screens from it.
    ///
    /// - the alarms list goes through the real `AlarmsListViewModel.balanceHint`
    /// - the wallet goes through the same `WalletHints.affordHint` call that
    ///   `WalletViewController.refresh()` makes, fed from the same
    ///   `BalanceService` and the same repository
    private func renderBothScreens(
        balance: Double,
        alarms: [Alarm],
        settingsPrice: Double? = nil
    ) -> Screens {
        let suiteName = "test.snoozeAffordability.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!

        let repo = AlarmRepository(
            defaults: defaults,
            scheduler: AlarmsListViewModelTests.StubScheduler()
        )
        for alarm in alarms {
            repo.save(alarm)
        }

        let alarmDefaults = AlarmDefaults(defaults: defaults)
        if let settingsPrice {
            alarmDefaults.penaltyAmount = settingsPrice
        }

        // Seed the balance BEFORE the first read: `BalanceService.init` probes
        // it and pins the ledger's opening balance to what it finds.
        defaults.set(balance, forKey: "user_balance")
        let center = NotificationCenter()
        let service = BalanceService(defaults: defaults, notificationCenter: center)

        let viewModel = AlarmsListViewModel(
            alarmRepository: repo,
            balanceService: service,
            transactionRepository: TransactionRepository(defaults: defaults),
            notificationCenter: center,
            alarmDefaults: alarmDefaults
        )
        viewModel.loadData()

        return Screens(
            list: viewModel.balanceHint,
            wallet: WalletHints.affordHint(
                forBalance: service.balance,
                alarms: repo.fetchAll(),
                defaults: alarmDefaults
            ),
            price: viewModel.currentSnoozePrice,
            count: viewModel.affordableSnoozeCount
        )
    }

    /// The exact state from the #546 screenshot: three alarms priced
    /// 200 / 100 / 50, of which the 200 ₽ one ("Рейс в Стамбул") is switched off.
    private var issueScreenshotAlarms: [Alarm] {
        [
            Alarm(name: "Рейс в Стамбул", penaltyAmount: 200, enabled: false),
            Alarm(name: "Работа", penaltyAmount: 100, enabled: true),
            Alarm(name: "Зарядка", penaltyAmount: 50, enabled: true)
        ]
    }

    // MARK: - The regression: the two screens must agree

    /// RED before #546: the list rendered "Хватит на ~1 откладывание" (its mode
    /// tie-break picked the 200 ₽ alarm — which is disabled) while the wallet
    /// rendered "Хватит на ~5 откладываний при текущей цене" (298 / hardcoded 50).
    func testBothScreensAgreeOnTheSameBalanceAndAlarms() {
        let screens = renderBothScreens(balance: 298, alarms: issueScreenshotAlarms)

        XCTAssertEqual(
            screens.list,
            screens.wallet,
            "The alarms list and the wallet must answer 'на сколько хватит' identically (#546)"
        )
    }

    /// The agreement above must not be an agreement on the wrong number: with
    /// enabled prices 50 and 100 the quoted price is 100 ₽, so 298 ₽ buys two.
    func testAgreedNumberIsTheUpperMedianOfEnabledAlarms() {
        let screens = renderBothScreens(balance: 298, alarms: issueScreenshotAlarms)

        XCTAssertEqual(screens.price, 100, accuracy: 0.0001)
        XCTAssertEqual(screens.list, "Хватит на ~2 откладывания")
        XCTAssertEqual(screens.wallet, "Хватит на ~2 откладывания")
    }

    /// Both screens stay in step as the balance moves — including the boundary
    /// where the money no longer covers a single snooze.
    func testScreensStayInStepAcrossBalances() {
        for balance in [1.0, 99.0, 100.0, 250.0, 298.0, 1000.0, 5000.0] {
            let screens = renderBothScreens(balance: balance, alarms: issueScreenshotAlarms)
            XCTAssertEqual(
                screens.list,
                screens.wallet,
                "Screens disagreed at \(balance) ₽"
            )
        }
    }

    // MARK: - What "the current price" is

    /// A switched-off alarm can never charge the user, so it must not decide
    /// the hint. This is what made the screenshot read "~1".
    func testDisabledAlarmDoesNotSetThePrice() {
        let screens = renderBothScreens(
            balance: 298,
            alarms: [
                Alarm(penaltyAmount: 1000, enabled: false),
                Alarm(penaltyAmount: 50, enabled: true)
            ]
        )

        XCTAssertEqual(screens.price, 50, accuracy: 0.0001)
        XCTAssertEqual(screens.count, 5)
        XCTAssertEqual(screens.list, screens.wallet)
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
            SnoozeAffordability.currentPrice(alarms: alarms, defaults: AlarmDefaults()),
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
            SnoozeAffordability.currentPrice(alarms: alarms, defaults: AlarmDefaults()),
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
            SnoozeAffordability.currentPrice(alarms: alarms, defaults: AlarmDefaults()),
            200,
            accuracy: 0.0001
        )
    }

    /// With nothing to measure, the answer is the price the user configured in
    /// Settings — not a private copy of `50` (#546 comment).
    func testFallsBackToTheUserConfiguredDefaultPrice() {
        let screens = renderBothScreens(balance: 600, alarms: [], settingsPrice: 200)

        XCTAssertEqual(screens.price, 200, accuracy: 0.0001)
        XCTAssertEqual(screens.list, "Хватит на ~3 откладывания")
        XCTAssertEqual(screens.wallet, "Хватит на ~3 откладывания")
    }

    /// Only-disabled alarms count as "nothing to measure" too.
    func testAllAlarmsDisabledFallsBackToTheDefaultPrice() {
        let screens = renderBothScreens(
            balance: 600,
            alarms: [Alarm(penaltyAmount: 1000, enabled: false)],
            settingsPrice: 150
        )

        XCTAssertEqual(screens.price, 150, accuracy: 0.0001)
        XCTAssertEqual(screens.list, screens.wallet)
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
        let cases: [(balance: Double, expected: String)] = [
            (50, "Хватит на ~1 откладывание"),
            (100, "Хватит на ~2 откладывания"),
            (250, "Хватит на ~5 откладываний")
        ]

        for testCase in cases {
            let screens = renderBothScreens(
                balance: testCase.balance,
                alarms: [Alarm(penaltyAmount: 50, enabled: true)]
            )
            XCTAssertEqual(screens.list, testCase.expected)
            XCTAssertEqual(screens.wallet, testCase.expected)
        }
    }

    // MARK: - Empty balance

    /// The wallet keeps its own zero-balance copy — it is the screen with the
    /// top-up button, so it nudges rather than reporting "~0".
    func testWalletEmptyBalanceCopy() {
        let screens = renderBothScreens(
            balance: 0,
            alarms: [Alarm(penaltyAmount: 50, enabled: true)]
        )

        XCTAssertEqual(screens.wallet, WalletHints.emptyBalanceHint)
        XCTAssertEqual(screens.list, AlarmsListViewModel.zeroBalanceHint)
        XCTAssertFalse(WalletHints.emptyBalanceHint.contains("откладываний"))
    }

    /// A balance too small for one snooze reports zero on both screens rather
    /// than the wallet's old `max(1, …)`, which promised a snooze the user
    /// could not pay for — in the wrong grammatical case at that.
    func testBalanceBelowOneSnoozeReportsZeroOnBothScreens() {
        let screens = renderBothScreens(
            balance: 30,
            alarms: [Alarm(penaltyAmount: 50, enabled: true)]
        )

        XCTAssertEqual(screens.list, "Хватит на ~0 откладываний")
        XCTAssertEqual(screens.wallet, "Хватит на ~0 откладываний")
    }
}
