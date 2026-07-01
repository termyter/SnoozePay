import XCTest
@testable import SnoozePay

/// Unit coverage for `StreakCalculator` (#439). Exercises the accurate walk
/// (charge break / neutral skip / wake +1), the empty-wake-store legacy
/// fallback, and — the regression this ticket fixes — that a REFUNDED snooze
/// charge does not break the streak on either path.
///
/// All maths is driven off an injected fixed UTC calendar + `now` so the tests
/// are deterministic regardless of the machine's timezone.
final class StreakCalculatorTests: XCTestCase {

    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
        // Fixed reference "now": 2026-06-15 08:00 UTC.
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 8
        now = cal.date(from: components)!
    }

    override func tearDown() {
        calendar = nil
        now = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// `startOfDay` `offset` days from `now` (negative = past). Matches the
    /// keys `StreakCalculator` compares against, so use for `wakeDays`.
    private func startDay(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    /// A concrete timestamp within the day `offset` days from `now` — use for
    /// transaction `createdAt` so we also prove the calculator floors to the
    /// day.
    private func at(_ offset: Int, hour: Int = 12) -> Date {
        startDay(offset).addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func charge(_ offset: Int, id: UUID = UUID()) -> Transaction {
        Transaction(id: id, type: .charge, amount: 50, createdAt: at(offset))
    }

    private func topup(_ offset: Int, refunds: UUID? = nil) -> Transaction {
        Transaction(type: .topup, amount: 50, createdAt: at(offset), refundsTransactionID: refunds)
    }

    private func streak(_ transactions: [Transaction], wake offsets: [Int]) -> Int {
        StreakCalculator.currentStreak(
            transactions: transactions,
            wakeDays: Set(offsets.map(startDay)),
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Accurate walk

    func testChargeDayBreaksStreak() {
        // Wakes on the last two days, a charge the day before that.
        // Walk: today neutral, -1 wake(+1), -2 wake(+1), -3 charge → stop.
        let result = streak([charge(-3)], wake: [-1, -2])
        XCTAssertEqual(result, 2, "Charge day must bound the streak after counting the intervening wakes")
    }

    func testNeutralGapIsSkippedNotReset() {
        // Wake on -1 and -3, nothing on -2 (no alarm scheduled). The neutral
        // gap must not reset the run.
        let result = streak([], wake: [-1, -3])
        XCTAssertEqual(result, 2, "A neutral (no wake, no charge) day should be skipped, not break the streak")
    }

    func testTodayBeforeItsWakeIsNeutral() {
        // No wake recorded for today yet → today doesn't optimistically count.
        XCTAssertEqual(streak([], wake: [-1]), 1, "Today must stay neutral until its own wake is recorded")
        // Once today's wake lands, it extends.
        XCTAssertEqual(streak([], wake: [0, -1]), 2, "Today's wake should extend the streak once recorded")
    }

    // MARK: - Legacy fallback

    func testEmptyWakeStoreFallsBackToLegacyChargeFreeDays() {
        // No wake history → legacy path: consecutive charge-free days from today
        // back to the first transaction (a topup on -5), stopped by a charge -2.
        let txns = [topup(-5), charge(-2)]
        let result = streak(txns, wake: [])
        // today(1), -1(2), -2 charge → stop.
        XCTAssertEqual(result, 2, "Empty wake store must use the legacy charge-free-days heuristic, not return 0")
    }

    // MARK: - Refunded charge (#439 regression)

    func testRefundedChargeDoesNotBreakStreak_accuratePath() {
        // A snooze charge on -2 that was auto-refunded (offsetting topup carries
        // its id). With wakes on -1/-2/-3 the run should reach 3 because the
        // refunded charge no longer bounds it. Pre-fix this returned 1.
        let chargeID = UUID()
        let txns = [charge(-2, id: chargeID), topup(-2, refunds: chargeID)]
        let result = streak(txns, wake: [-1, -2, -3])
        XCTAssertEqual(result, 3, "A refunded charge must not break the streak (must match the heatmap)")
    }

    func testRefundedChargeDoesNotBreakStreak_legacyPath() {
        // Same refund, but empty wake store → legacy path. First tx is a topup
        // on -5; the refunded charge on -2 must not stop the charge-free walk,
        // so all of today…-5 count (6 days). Pre-fix this returned 2.
        let chargeID = UUID()
        let txns = [topup(-5), charge(-2, id: chargeID), topup(-2, refunds: chargeID)]
        let result = streak(txns, wake: [])
        XCTAssertEqual(result, 6, "A refunded charge must not break the legacy streak either")
    }
}
