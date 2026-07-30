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
        let delta = WalletStats.weeklyDelta(from: [
            charge,
            Transaction(type: .refund, amount: 50, createdAt: daysAgo(1),
                        refundsTransactionID: charge.id)
        ])
        XCTAssertEqual(delta, 0)
    }

    func testWeeklyDelta_refundCountsAsMoneyIn() {
        XCTAssertEqual(
            WalletStats.weeklyDelta(from: [
                Transaction(type: .refund, amount: 50, createdAt: daysAgo(1))
            ]),
            50
        )
    }

    func testWeeklyDelta_sumsCreditsAgainstCharges() {
        let delta = WalletStats.weeklyDelta(from: [
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
        let withUnknown = WalletStats.weeklyDelta(from: [
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(1)),
            Transaction(type: .unknown("cashback"), amount: 999, createdAt: daysAgo(1))
        ])
        XCTAssertEqual(withUnknown, -50)
    }

    /// Rows older than the rolling window are excluded, and a window with
    /// nothing in it hides the row entirely (`nil`, not `0`).
    func testWeeklyDelta_ignoresRowsOlderThanSevenDays() {
        XCTAssertNil(WalletStats.weeklyDelta(from: [
            Transaction(type: .charge, amount: 50, createdAt: daysAgo(30))
        ]))
    }

    func testWeeklyDelta_emptyLedger_isNil() {
        XCTAssertNil(WalletStats.weeklyDelta(from: []))
    }

    // MARK: - weeklyPenaltyTotals

    /// Only `.charge` feeds the pain chart — credits of every flavour, refunds
    /// included, must stay out of it.
    func testWeeklyPenaltyTotals_onlyChargesContribute() {
        let totals = WalletStats.weeklyPenaltyTotals(from: [
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
        let totals = WalletStats.weeklyPenaltyTotals(from: [
            Transaction(type: .charge, amount: 30, createdAt: daysAgo(6)),
            Transaction(type: .charge, amount: 70, createdAt: daysAgo(0))
        ])
        XCTAssertEqual(totals.first, 30)
        XCTAssertEqual(totals.last, 70)
    }
}
