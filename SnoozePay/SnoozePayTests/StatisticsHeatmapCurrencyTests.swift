import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class StatisticsHeatmapCurrencyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var repository: TransactionRepository!
    private var wakes: WakeEventStore!
    private var alarms: AlarmRepository!
    private let usd = Currency(code: "USD")!
    private var calendar: Calendar {
        var value = StatisticsViewModel.mondayFirstCalendar
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }
    private var today: Date { date(6, 17) }

    override func setUp() {
        super.setUp()
        suiteName = "test.heatmapCurrency.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        wakes = WakeEventStore(defaults: defaults)
        repository = TransactionRepository(defaults: defaults, wakeStore: wakes)
        alarms = AlarmRepository(defaults: defaults, scheduler: InertScheduler())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMixedDayKeepsThreeSnoozesAndShowsOnlyUSDCentsInRealTooltip() throws {
        freeze(usd)
        record(.charge, 0.49, usd, today)
        record(.charge, 500, .rub, today)
        record(.charge, 20, Currency(code: "EUR")!, today)
        let model = loadModel()
        let day = try day(in: model)
        XCTAssertEqual(day.snoozes, 3)
        XCTAssertEqual(day.status, .heavy)
        XCTAssertEqual(day.spent, 0.49, accuracy: 0.000001)
        XCTAssertEqual(model.charges.count, 3)
        XCTAssertEqual(model.thisWeekCount, 3)
        XCTAssertEqual(model.weekMoneySummary.spent, day.spent)
        let payload = model.tooltip(for: day)
        XCTAssertTrue(payload.statusText.hasPrefix("3"), payload.statusText)
        let view = HeatmapTooltipView()
        view.apply(payload)
        let amount = try amountLabel(in: view)
        XCTAssertTrue(amount.text?.contains("0,49") == true)
        XCTAssertTrue(amount.text?.contains("$") == true)
        XCTAssertFalse(amount.text?.contains("₽") == true)
        XCTAssertTrue(amount.text?.hasPrefix("· −") == true)
        XCTAssertEqual(amount.accessibilityLabel, amount.text)
        XCTAssertTrue(amount.isAccessibilityElement)
        XCTAssertFalse(amount.isHidden)
    }

    func testForeignOnlyDayKeepsBehaviorAndClearsReusedTooltipMoneyAndAccessibility() throws {
        freeze(usd)
        record(.charge, 0.49, usd, date(6, 16))
        record(.charge, 500, .rub, today)
        record(.charge, 20, Currency(code: "EUR")!, today)
        let model = loadModel()
        let previous = try XCTUnwrap(model.heatmapDays.first { calendar.isDate($0.date, inSameDayAs: date(6, 16)) })
        let view = HeatmapTooltipView()
        view.apply(model.tooltip(for: previous))
        let amount = try amountLabel(in: view)
        let foreign = try day(in: model)
        XCTAssertEqual(foreign.snoozes, 2)
        XCTAssertEqual(foreign.status, .light)
        XCTAssertEqual(foreign.spent, 0)
        let payload = model.tooltip(for: foreign)
        XCTAssertNil(payload.spentText)
        XCTAssertTrue(payload.statusText.hasPrefix("2"), payload.statusText)
        view.apply(payload)
        XCTAssertNil(amount.text)
        XCTAssertNil(amount.accessibilityLabel)
        XCTAssertTrue(amount.isHidden)
        XCTAssertFalse(amount.isAccessibilityElement)
    }

    func testFullLedgerRefundsApplyBeforeMonthAndCurrencyProjection() throws {
        freeze(usd)
        let retained = record(.charge, 0.49, usd, today)
        let refunded = record(.charge, 1.49, usd, today)
        let legacy = record(.charge, 3.49, usd, today)
        // Refunds arrive in the next month, outside the displayed month/week.
        record(.refund, 0.49, .rub, date(7, 1), refunding: retained.id)
        record(.refund, 1.49, usd, date(7, 1), refunding: refunded.id)
        record(.topup, 3.49, usd, date(7, 1), refunding: legacy.id)
        let model = loadModel()
        let day = try day(in: model)
        XCTAssertEqual(model.charges.map(\.id), [retained.id])
        XCTAssertEqual(day.snoozes, 1)
        XCTAssertEqual(day.status, .light)
        XCTAssertEqual(day.spent, 0.49)
        XCTAssertTrue(model.tooltip(for: day).spentText?.contains("0,49") == true)
    }

    func testLegacyRubleWalletKeepsWholeTypographyAndActualKopecks() throws {
        record(.charge, 50, .legacyDefault, date(6, 16))
        record(.charge, 0.49, .legacyDefault, today)
        let model = loadModel()
        XCTAssertEqual(model.walletCurrency, .rub)
        let previous = try XCTUnwrap(model.heatmapDays.first { calendar.isDate($0.date, inSameDayAs: date(6, 16)) })
        XCTAssertEqual(model.tooltip(for: previous).spentText, "· −50\u{202F}₽")
        XCTAssertEqual(model.tooltip(for: try day(in: model)).spentText, "· −0,49\u{202F}₽")
    }

    func testEuroTooltipPreservesCents() throws {
        try assertMinorUnits(code: "EUR", amount: 0.49, digits: "0,49", symbol: "€")
    }

    func testKuwaitiDinarTooltipPreservesItsThirdMinorUnit() throws {
        try assertMinorUnits(code: "KWD", amount: 0.001, digits: "0,001", symbol: nil)
    }

    func testCleanWakeWithoutChargesKeepsWokeStatusAndNoMoney() throws {
        freeze(usd)
        wakes.recordWake(on: today, calendar: calendar)
        let model = loadModel()
        let day = try day(in: model)
        XCTAssertEqual(day.status, .woke)
        XCTAssertEqual(day.snoozes, 0)
        XCTAssertEqual(day.spent, 0)
        XCTAssertNil(model.tooltip(for: day).spentText)
    }

    func testForeignUnknownRowsAndMalformedLedgerStillWithholdHeatmap() throws {
        freeze(usd)
        let unknown = Transaction(type: .unknown("future"), amount: 500, currency: .rub, createdAt: today)
        for payload in [try JSONEncoder().encode([unknown]), Data("invalid ledger".utf8)] {
            defaults.set(payload, forKey: "stored_transactions")
            let model = loadModel()
            XCTAssertFalse(model.ledgerReadable)
            XCTAssertNotNil(model.ledgerUnavailableReason)
            XCTAssertTrue(model.heatmapDays.isEmpty)
            XCTAssertTrue(model.weekMoneyDays.isEmpty)
        }
    }

    private func assertMinorUnits(code: String, amount: Double, digits: String, symbol: String?) throws {
        let currency = Currency(code: code)!
        freeze(currency)
        record(.charge, amount, currency, today)
        let model = loadModel()
        XCTAssertEqual(model.walletCurrency, currency)
        let payload = model.tooltip(for: try day(in: model))
        let view = HeatmapTooltipView()
        view.apply(payload)
        let label = try amountLabel(in: view)
        XCTAssertTrue(label.text?.contains(digits) == true)
        if let symbol { XCTAssertTrue(label.text?.contains(symbol) == true) }
        XCTAssertFalse(label.text?.contains("₽") == true)
        XCTAssertEqual(label.accessibilityLabel, label.text)
        XCTAssertTrue(label.isAccessibilityElement)
    }

    private func loadModel() -> StatisticsViewModel {
        let model = StatisticsViewModel(repository: repository, wakeStore: wakes, alarmRepository: alarms,
                                        defaults: defaults, calendar: calendar)
        model.loadData()
        model.recomputeSnapshots(today: today)
        return model
    }

    private func day(in model: StatisticsViewModel) throws -> StatisticsViewModel.HeatmapDay {
        try XCTUnwrap(model.heatmapDays.first { calendar.isDate($0.date, inSameDayAs: today) })
    }

    private func freeze(_ currency: Currency) {
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(currency), .frozen(currency))
    }

    @discardableResult
    private func record(_ type: TransactionType, _ amount: Double, _ currency: Currency,
                        _ date: Date, refunding id: UUID? = nil) -> Transaction {
        let row = Transaction(type: type, amount: amount, currency: currency,
                              createdAt: date, refundsTransactionID: id)
        XCTAssertTrue(repository.record(row))
        return row
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func amountLabel(in view: UIView) throws -> UILabel {
        try XCTUnwrap(labels(in: view).first { $0.text?.hasPrefix("· ") == true })
    }

    private func labels(in view: UIView) -> [UILabel] {
        let own = (view as? UILabel).map { [$0] } ?? []
        return own + view.subviews.flatMap { labels(in: $0) }
    }

    private final class InertScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm,
                      completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}
