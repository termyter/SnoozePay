import XCTest
@testable import SnoozePay

/// Money maths behind the Wallet header delta and the weekly chart.
///
/// `WalletStats.weeklyDelta` had no coverage before #358 — the similarly named
/// `weeklyDelta` tests in `AlarmsListViewModelTests` exercise a *different*
/// computation (charges only, over the alarms-list header). This suite pins the
/// wallet one, whose type switch #358 changed.
final class WalletStatsTests: XCTestCase {

    private let calendar = Calendar.current

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - weeklyDelta

    /// The delta must track the BALANCE, not revenue: a refund puts money back
    /// in the wallet, so a charge and its reversal net to zero. Booking the
    /// reversal anywhere else (or skipping it) would make the header contradict
    /// the balance printed directly above it (#358).
    func testWeeklyDelta_chargeAndItsRefundNetToZero() {
        let charge = Transaction(type: .charge, amount: 50, createdAt: daysAgo(1))
        let delta = WalletStats.weeklyDelta(currency: .rub, from: [
            charge,
            Transaction(type: .refund, amount: 50, createdAt: daysAgo(1),
                        refundsTransactionID: charge.id)
        ])
        XCTAssertEqual(delta, 0)
    }

    func testWeeklyDelta_refundCountsAsMoneyIn() {
        XCTAssertEqual(
            WalletStats.weeklyDelta(currency: .rub, from: [
                Transaction(type: .refund, amount: 50, createdAt: daysAgo(1))
            ]),
            50
        )
    }

    func testWeeklyDelta_sumsCreditsAgainstCharges() {
        let delta = WalletStats.weeklyDelta(currency: .rub, from: [
            Transaction(type: .topup, amount: 500, createdAt: daysAgo(2)),
            Transaction(type: .promotion, amount: 100, createdAt: daysAgo(2)),
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(1)),
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(1))
        ])
        XCTAssertEqual(delta, 500)
    }

    /// An unrecognised row has no direction, so it must not be signed into the
    /// delta in either direction. It DOES leave the totals understated versus
    /// `user_balance` — which is why `TransactionRepository` latches
    /// `lastLoadHadUnrecognizedTypes` and the history screen warns.
    func testWeeklyDelta_unknownRowDoesNotMoveTheDelta() {
        let withUnknown = WalletStats.weeklyDelta(currency: .rub, from: [
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(1)),
            Transaction(type: .unknown("cashback"), amount: 999, createdAt: daysAgo(1))
        ])
        XCTAssertEqual(withUnknown, -50)
    }

    /// Rows older than the rolling window are excluded, and a window with
    /// nothing in it hides the row entirely (`nil`, not `0`).
    func testWeeklyDelta_ignoresRowsOlderThanSevenDays() {
        XCTAssertNil(WalletStats.weeklyDelta(currency: .rub, from: [
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(30))
        ]))
    }

    func testWeeklyDelta_emptyLedger_isNil() {
        XCTAssertNil(WalletStats.weeklyDelta(currency: .rub, from: []))
    }

    // MARK: - weeklyPenaltyTotals

    /// Only `.charge` feeds the pain chart — credits of every flavour, refunds
    /// included, must stay out of it.
    func testWeeklyPenaltyTotals_onlyChargesContribute() {
        let totals = WalletStats.weeklyPenaltyTotals(currency: .rub, from: [
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(0)),
            Transaction(type: .refund, amount: 50, createdAt: daysAgo(0)),
            Transaction(type: .topup, amount: 500, createdAt: daysAgo(0)),
            Transaction(type: .unknown("cashback"), amount: 10, createdAt: daysAgo(0))
        ])
        XCTAssertEqual(totals.count, 7)
        XCTAssertEqual(totals.last, 50, "Today's bucket holds the single charge")
        XCTAssertEqual(totals.dropLast().reduce(0, +), 0)
    }

    func testWeeklyPenaltyTotals_bucketsByDayOldestFirst() {
        let totals = WalletStats.weeklyPenaltyTotals(currency: .rub, from: [
            Transaction(type: .charge, amount: 30, createdAt: daysAgo(6)),
            Transaction(type: .charge, amount: 70, createdAt: daysAgo(0))
        ])
        XCTAssertEqual(totals.first, 30)
        XCTAssertEqual(totals.last, 70)
    }
    func testMixedCurrencyDeltaAndChartUseOnlyRequestedWalletCurrency() throws {
        let usd = try XCTUnwrap(Currency(code: "USD"))
        let eur = try XCTUnwrap(Currency(code: "EUR"))
        let charge = Transaction(type: .charge, amount: 0.49, currency: usd)
        let rows = [
            Transaction(type: .topup, amount: 2.99, currency: usd), charge,
            Transaction(type: .refund, amount: 0.49, currency: usd, refundsTransactionID: charge.id),
            Transaction(type: .topup, amount: 1000, currency: .rub),
            Transaction(type: .charge, amount: 500, currency: .rub),
            Transaction(type: .charge, amount: 20, currency: eur)
        ]
        for (currency, net, spent) in [(usd, 2.99, 0.49), (.rub, 500.0, 500.0)] {
            let delta = try XCTUnwrap(WalletStats.weeklyDelta(currency: currency, from: rows))
            XCTAssertEqual(NSDecimalNumber(decimal: delta).doubleValue, net, accuracy: 0.000000001)
            let buckets = WalletStats.weeklyPenaltyTotals(currency: currency, from: rows)
            XCTAssertEqual(buckets.count, 7)
            XCTAssertEqual(NSDecimalNumber(decimal: buckets[6]).doubleValue, spent, accuracy: 0.000000001)
            XCTAssertEqual(buckets.dropLast(), Array(repeating: Decimal.zero, count: 6)[...])
        }
        let foreign = rows.filter { $0.currency != usd }
        XCTAssertNil(WalletStats.weeklyDelta(currency: usd, from: foreign))
        XCTAssertEqual(WalletStats.weeklyPenaltyTotals(currency: usd, from: foreign), Array(repeating: 0, count: 7))
    }

}
