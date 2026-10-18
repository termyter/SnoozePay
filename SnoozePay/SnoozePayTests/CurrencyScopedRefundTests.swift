import XCTest
@testable import SnoozePay

/// Refund links are scoped to their row currency before any display window (#951).
final class CurrencyScopedRefundTests: XCTestCase {
    private let usd = Currency(code: "USD")!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!
    }

    private func row(
        _ type: TransactionType, currency: Currency, id: UUID = UUID(),
        amount: Double = 5, offset: Int = 0, refunds: UUID? = nil
    ) -> Transaction {
        Transaction(id: id, type: type, amount: amount, currency: currency,
                    createdAt: calendar.date(byAdding: .day, value: offset, to: today)!,
                    refundsTransactionID: refunds)
    }

    func testEveryExistingLinkShapeCancelsOnlyItsOwnCurrency() {
        for type in [TransactionType.refund, .topup, .promotion, .unknown("future-credit")] {
            let sharedID = UUID()
            let dollar = row(.charge, currency: usd, id: sharedID)
            let ruble = row(.charge, currency: .rub, id: sharedID)
            let rubleLink = row(type, currency: .rub, refunds: sharedID)
            let dollarLink = row(type, currency: usd, refunds: sharedID)
            XCTAssertEqual(TransactionRepository.realCharges(from: [dollar, ruble, rubleLink]).map(\.currency), [usd])
            XCTAssertEqual(TransactionRepository.realCharges(from: [dollarLink, ruble, dollar]).map(\.currency), [.rub])
            XCTAssertTrue(TransactionRepository.realCharges(from: [rubleLink, dollar, dollarLink, ruble]).isEmpty)
        }
    }

    func testChargeRowWithALinkRetainsTheExistingAnyRowLinkContract() {
        let original = row(.charge, currency: usd)
        let linkedCharge = row(.charge, currency: usd, refunds: original.id)
        XCTAssertEqual(TransactionRepository.realCharges(from: [original, linkedCharge]).map(\.id), [linkedCharge.id])
    }

    func testCrossCurrencyAndUnrelatedLinksPreserveChargeOrder() {
        let first = row(.charge, currency: usd, offset: -3)
        let second = row(.charge, currency: .rub, offset: -1)
        let refunded = row(.charge, currency: usd, offset: -2)
        let ledger = [second, row(.refund, currency: .rub, refunds: first.id), first,
                      row(.topup, currency: usd, refunds: refunded.id), refunded,
                      row(.refund, currency: usd, refunds: UUID()), row(.topup, currency: .rub)]
        XCTAssertEqual(TransactionRepository.realCharges(from: ledger).map(\.id), [second.id, first.id])
    }

    func testStatisticsWindowUsesFullLedgerLinksBeforeCurrencyAndDateFiltering() {
        let refunded = row(.charge, currency: usd, amount: 3.25, offset: -1)
        let retained = row(.charge, currency: usd, amount: 4.5, offset: -1)
        // These links lie in the following week, outside the displayed week.
        let ledger = [refunded, retained,
                      row(.refund, currency: usd, offset: 8, refunds: refunded.id),
                      row(.refund, currency: .rub, offset: 8, refunds: retained.id)]
        let charges = TransactionRepository.realCharges(from: ledger).filter { $0.currency == usd }
        let days = StatisticsViewModel.weekMoneyDays(
            today: today, inputs: .init(charges: charges), currency: usd, calendar: calendar
        )
        XCTAssertEqual(charges.map(\.id), [retained.id])
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.reduce(0) { $0 + $1.spent }, 4.5)
    }

    func testStreakKeepsCrossCurrencyChargeOnAccurateAndLegacyPaths() {
        let charge = row(.charge, currency: usd, offset: -1)
        let opening = row(.topup, currency: usd, offset: -5)
        let wakeDays = Set([0, -1, -2].map {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: today)!)
        })
        let crossCurrency = [opening, charge, row(.refund, currency: .rub, refunds: charge.id)]
        let sameCurrency = [opening, charge, row(.topup, currency: usd, refunds: charge.id)]
        for wakes in [wakeDays, Set<Date>()] {
            XCTAssertEqual(StreakCalculator.currentStreak(transactions: crossCurrency, wakeDays: wakes,
                                                         now: today, calendar: calendar), 1)
            XCTAssertEqual(StreakCalculator.currentStreak(transactions: sameCurrency, wakeDays: wakes,
                                                         now: today, calendar: calendar), wakes.isEmpty ? 6 : 3)
        }
    }

    func testLegacyUntaggedRubleTopupStillCancelsOnlyRubleCharge() throws {
        let rubleID = UUID()
        let dollarID = UUID()
        let json = """
        [
          {"id":"\(rubleID)","type":"charge","amount":50,"createdAt":760000000},
          {"id":"\(dollarID)","type":"charge","amount":5,"currency":"USD","createdAt":760000000},
          {"id":"\(UUID())","type":"topup","amount":50,"createdAt":760000100,
           "refundsTransactionID":"\(rubleID)"},
          {"id":"\(UUID())","type":"refund","amount":50,"createdAt":760000100,
           "refundsTransactionID":"\(dollarID)"}
        ]
        """
        let ledger = try JSONDecoder().decode([Transaction].self, from: Data(json.utf8))
        XCTAssertEqual(ledger[0].currency, .rub)
        XCTAssertEqual(ledger[2].currency, .rub)
        XCTAssertEqual(TransactionRepository.realCharges(from: ledger).map(\.id), [dollarID])
    }
}
