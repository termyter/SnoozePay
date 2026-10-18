import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class StatisticsCurrencyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var repository: TransactionRepository!
    private var wakeStore: WakeEventStore!
    private var alarms: AlarmRepository!
    private let calendar = StatisticsViewModel.mondayFirstCalendar
    private let usd = Currency(code: "USD")!

    override func setUp() {
        super.setUp()
        suiteName = "test.statisticsCurrency.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        wakeStore = WakeEventStore(defaults: defaults)
        repository = TransactionRepository(defaults: defaults, wakeStore: wakeStore)
        alarms = AlarmRepository(defaults: defaults, scheduler: InertScheduler())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testActualScreenKeepsUSDCentsAndAccessibilityWhileCountingAllCurrencies() {
        freezeUSD()
        let today = Date()
        record(.charge, 0.49, usd, today)
        record(.charge, 500, .rub, today)
        record(.charge, 20, Currency(code: "EUR")!, today)
        let model = makeModel()
        let screen = StatisticsViewController(viewModel: model)
        screen.loadViewIfNeeded()
        screen.viewWillAppear(false)

        XCTAssertEqual(model.weekMoneySummary.spent, 0.49, accuracy: 0.000001)
        XCTAssertEqual(model.charges.count, 3)
        XCTAssertEqual(model.thisWeekCount, 3)
        let day = model.heatmapDays.first { calendar.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(day?.snoozes, 3)
        XCTAssertEqual(day?.status, .heavy)
        let amounts = labels(in: screen.weekMoneyCard).filter { $0.font == AppTypography.moneyMd }
        XCTAssertEqual(amounts.count, 3, "Read the actual card's three total labels")
        for label in amounts {
            let text = label.attributedText?.string ?? ""
            XCTAssertEqual(label.accessibilityLabel, text)
            XCTAssertTrue(text.contains("$"), text)
            XCTAssertFalse(text.contains("₽"), text)
        }
        let debits = amounts.filter { $0.attributedText?.string.hasPrefix("−") == true }
        XCTAssertEqual(debits.count, 2, "Spent and net must retain the fractional debit")
        for label in debits {
            XCTAssertTrue(label.attributedText?.string.contains("0,49") == true)
            XCTAssertEqual(label.textColor, AppColors.pain400)
        }
    }

    func testRefundsPairWithinCurrencyAcrossTheFullLedgerBeforeWeekFiltering() {
        freezeUSD()
        let monday = date(26)
        let own = record(.charge, 0.49, usd, monday)
        record(.refund, 0.49, .rub, date(27), refunding: own.id)
        let reversed = record(.charge, 1.49, usd, monday)
        // A later legacy refund outside the displayed week still cancels its charge.
        record(.topup, 1.49, usd, date(27).addingTimeInterval(14 * 86_400), refunding: reversed.id)
        let model = makeModel()
        model.loadData()
        model.recomputeSnapshots(today: date(27))

        XCTAssertEqual(model.charges.map(\.id), [own.id])
        XCTAssertEqual(model.weekMoneySummary.spent, 0.49, accuracy: 0.000001)
        XCTAssertEqual(model.thisWeekCount, 1)
    }

    func testForeignRefundedAttemptDoesNotInventSavingsOnAWakeMorning() {
        freezeUSD()
        let monday = date(26)
        let attempt = record(.charge, 500, .rub, monday)
        record(.refund, 500, .rub, date(27), refunding: attempt.id)
        wakeStore.recordWake(on: monday, calendar: calendar)
        XCTAssertTrue(alarms.save(Alarm(penaltyAmount: 1.49)))
        let model = makeModel()
        model.loadData()
        model.recomputeSnapshots(today: date(27))

        XCTAssertEqual(model.snoozePrice, 1.49)
        XCTAssertTrue(model.attemptedSnoozeDays.contains(calendar.startOfDay(for: monday)))
        XCTAssertEqual(model.weekMoneySummary.spent, 0)
        XCTAssertEqual(model.weekMoneySummary.saved, 0)
        XCTAssertFalse(model.weekMoneyDays[0].isCleanWake)
    }

    func testCleanWakeSavingsKeepTheFractionalWalletPrice() {
        freezeUSD()
        wakeStore.recordWake(on: Date(), calendar: calendar)
        XCTAssertTrue(alarms.save(Alarm(penaltyAmount: 1.49)))
        let model = makeModel()
        model.loadData()

        XCTAssertEqual(model.weekMoneySummary.saved, 1.49)
        XCTAssertEqual(model.weekMoneySummary.spent, 0)
        XCTAssertEqual(model.weekMoneySummary.net, 1.49)
        XCTAssertEqual(model.walletCurrency, usd)
    }

    func testLoadCapturesTheFirstPaidCurrencyAfterModelInitialization() {
        let model = makeModel()
        XCTAssertEqual(model.walletCurrency, .rub)
        freezeUSD()
        record(.charge, 0.49, usd, Date())
        model.loadData()
        XCTAssertEqual(model.walletCurrency, usd)
        XCTAssertEqual(model.weekMoneySummary.spent, 0.49, accuracy: 0.000001)
    }

    func testForeignUnknownRowsAndUnreadableLedgerStillWithholdMoney() throws {
        freezeUSD()
        let unknown = Transaction(type: .unknown("future"), amount: 500, currency: .rub)
        for payload in [try JSONEncoder().encode([unknown]), Data("invalid ledger".utf8)] {
            defaults.set(payload, forKey: "stored_transactions")
            let model = makeModel()
            model.loadData()
            XCTAssertFalse(model.ledgerReadable)
            XCTAssertNotNil(model.ledgerUnavailableReason)
            XCTAssertTrue(model.weekMoneyDays.isEmpty)
            XCTAssertTrue(model.weekMoneySummary.isEmpty)
        }
    }

    func testSignedMoneyPreservesFractionsMinorUnitsAndAttributedSigns() {
        for (code, amount, digits) in [("USD", 0.49, "0,49"), ("EUR", 0.49, "0,49"),
                                     ("RUB", 0.49, "0,49"), ("KWD", 0.001, "0,001")] {
            let currency = Currency(code: code)!
            for (sign, value) in [("+", amount), ("−", -amount)] {
                let text = StatisticsViewModel.signedMoneyText(value, currency: currency)
                let attributed = StatisticsViewModel.signedMoneyAttributed(
                    value, currency: currency, digitsFont: AppTypography.moneyMd, color: AppColors.pain400
                )
                XCTAssertTrue(text.hasPrefix(sign), text)
                XCTAssertTrue(text.contains(digits), text)
                if code != "RUB" { XCTAssertFalse(text.contains("₽"), text) }
                XCTAssertEqual(attributed.string, text)
                XCTAssertEqual(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
                               AppTypography.moneyMd)
                XCTAssertEqual(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
                               AppColors.pain400)
            }
        }
        let zero = StatisticsViewModel.signedMoneyText(0, currency: usd)
        XCTAssertTrue(zero.contains("0,00"), zero)
        XCTAssertFalse(zero.hasPrefix("+"))
        XCTAssertFalse(zero.hasPrefix("−"))
    }

    func testUnavailableMoneyIsOneUnsignedDashInBothRepresentations() {
        for amount: Double? in [nil, .nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            XCTAssertEqual(StatisticsViewModel.signedMoneyText(amount, currency: usd), "—")
            let attributed = StatisticsViewModel.signedMoneyAttributed(
                amount, currency: usd, digitsFont: AppTypography.moneyMd, color: AppColors.fg1
            )
            XCTAssertEqual(attributed.string, "—")
        }
    }

    private func makeModel() -> StatisticsViewModel {
        StatisticsViewModel(repository: repository, wakeStore: wakeStore, alarmRepository: alarms,
                            defaults: defaults, calendar: calendar)
    }

    private func freezeUSD() {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(usd), .frozen(usd))
    }

    @discardableResult
    private func record(_ type: TransactionType, _ amount: Double, _ currency: Currency,
                        _ date: Date, refunding id: UUID? = nil) -> Transaction {
        let row = Transaction(type: type, amount: amount, currency: currency,
                              createdAt: date, refundsTransactionID: id)
        XCTAssertTrue(repository.record(row))
        return row
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: 12))!
    }

    private func labels(in view: UIView) -> [UILabel] {
        let ownLabels = (view as? UILabel).map { [$0] } ?? []
        return ownLabels + view.subviews.flatMap { labels(in: $0) }
    }

    private final class InertScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm,
                      completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}
