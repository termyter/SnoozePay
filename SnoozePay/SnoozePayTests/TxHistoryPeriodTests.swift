import XCTest
@testable import SnoozePay

/// Tests the TxHistory V3 period logic (issue #234) — month-range
/// filtering, the Списано / Пополнения / Откладываний aggregates (bonuses
/// excluded), captions and the picker tap-selection state machine.
final class TxHistoryPeriodTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int = 15, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    // MARK: - YearMonth

    func testYearMonth_comparesAcrossYearBoundary() {
        XCTAssertLessThan(YearMonth(year: 2025, month: 12), YearMonth(year: 2026, month: 1))
        XCTAssertLessThan(YearMonth(year: 2025, month: 3), YearMonth(year: 2025, month: 11))
    }

    func testYearMonth_fromDate() {
        let yearMonth = YearMonth(date: date(year: 2026, month: 1, day: 31), calendar: calendar)
        XCTAssertEqual(yearMonth, YearMonth(year: 2026, month: 1))
    }

    // MARK: - Period normalization + counting

    func testPeriod_normalizesReversedEndpoints() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2026, month: 1),
            end: YearMonth(year: 2025, month: 11)
        )
        XCTAssertEqual(period.start, YearMonth(year: 2025, month: 11))
        XCTAssertEqual(period.end, YearMonth(year: 2026, month: 1))
    }

    func testPeriod_monthCount_singleAndRange() {
        XCTAssertEqual(TxHistoryPeriod(month: YearMonth(year: 2026, month: 1)).monthCount, 1)
        let range = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        XCTAssertEqual(range.monthCount, 3)
        XCTAssertFalse(range.isSingleMonth)
    }

    func testCurrentMonth_matchesNow() {
        let now = date(year: 2026, month: 2, day: 10)
        let period = TxHistoryPeriod.currentMonth(now: now, calendar: calendar)
        XCTAssertEqual(period, TxHistoryPeriod(month: YearMonth(year: 2026, month: 2)))
    }

    // MARK: - Range filtering

    func testFilter_keepsOnlyTransactionsInsideRange() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        let october = Transaction(type: .charge, amount: 50, createdAt: date(year: 2025, month: 10, day: 31))
        let november = Transaction(type: .charge, amount: 100, createdAt: date(year: 2025, month: 11, day: 1))
        let december = Transaction(type: .topup, amount: 500, createdAt: date(year: 2025, month: 12, day: 28))
        let january = Transaction(type: .charge, amount: 50, createdAt: date(year: 2026, month: 1, day: 12))
        let february = Transaction(type: .topup, amount: 500, createdAt: date(year: 2026, month: 2, day: 1))

        let visible = period.filter(
            [october, november, december, january, february], calendar: calendar
        )
        XCTAssertEqual(visible.map(\.id), [november, december, january].map(\.id))
    }

    func testFilter_singleMonth_includesFirstAndLastDay() {
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        let first = Transaction(type: .charge, amount: 50, createdAt: date(year: 2026, month: 1, day: 1, hour: 0))
        let last = Transaction(type: .charge, amount: 50, createdAt: date(year: 2026, month: 1, day: 31, hour: 23))
        let next = Transaction(type: .charge, amount: 50, createdAt: date(year: 2026, month: 2, day: 1, hour: 0))

        let visible = period.filter([first, last, next], calendar: calendar)
        XCTAssertEqual(visible.map(\.id), [first, last].map(\.id))
    }

    func testFilter_preservesInputOrder() {
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        let newest = Transaction(type: .charge, amount: 50, createdAt: date(year: 2026, month: 1, day: 20))
        let oldest = Transaction(type: .charge, amount: 50, createdAt: date(year: 2026, month: 1, day: 5))
        XCTAssertEqual(
            period.filter([newest, oldest], calendar: calendar).map(\.id),
            [newest, oldest].map(\.id)
        )
    }

    // MARK: - Summary aggregates

    /// Most cases look at one period whose refunds are all in-window, so the
    /// visible slice doubles as the ledger.
    private func summary(of transactions: [Transaction]) -> TxHistorySummary {
        TxHistorySummary.compute(from: transactions, ledger: transactions)
    }

    func testSummary_aggregatesSpentTopupsAndSnoozeCount() {
        let now = Date()
        let summary = summary(of: [
            Transaction(type: .charge, amount: 50, createdAt: now),
            Transaction(type: .charge, amount: 100, createdAt: now),
            Transaction(type: .charge, amount: 200, createdAt: now),
            Transaction(type: .topup, amount: 500, createdAt: now),
            Transaction(type: .topup, amount: 1000, createdAt: now)
        ])
        XCTAssertEqual(summary.spent, 350)
        XCTAssertEqual(summary.topups, 1500)
        XCTAssertEqual(summary.snoozeCount, 3)
    }

    func testSummary_excludesBonusesFromTopups() {
        let now = Date()
        let summary = summary(of: [
            Transaction(type: .topup, amount: 500, createdAt: now),
            Transaction(type: .promotion, amount: 200, createdAt: now)
        ])
        XCTAssertEqual(summary.topups, 500, "Bonus credits must not inflate Пополнения")
        XCTAssertEqual(summary.spent, 0)
        XCTAssertEqual(summary.snoozeCount, 0)
    }

    /// #358: a penalty reversal is returned money, not income — it must stay
    /// out of the Пополнения aggregate exactly like a bonus does.
    func testSummary_excludesRefundsFromTopups() {
        let now = Date()
        let summary = summary(of: [
            Transaction(type: .topup, amount: 500, createdAt: now),
            Transaction(type: .refund, amount: 50, createdAt: now)
        ])
        XCTAssertEqual(summary.topups, 500, "A refund must not be booked as a top-up")
    }

    /// The other half of #358: once the refund stops counting as a top-up, the
    /// charge it reverses must stop counting as spend — otherwise the card
    /// claims money left the wallet when it came straight back.
    func testSummary_refundedChargeExcludedFromSpentAndSnoozeCount() {
        let now = Date()
        let reversed = Transaction(type: .charge, amount: 50, createdAt: now)
        let summary = summary(of: [
            reversed,
            Transaction(type: .charge, amount: 100, createdAt: now),
            Transaction(type: .refund, amount: 50, createdAt: now,
                        refundsTransactionID: reversed.id)
        ])
        XCTAssertEqual(summary.spent, 100, "Only the snooze the user really paid for counts")
        XCTAssertEqual(summary.snoozeCount, 1)
        XCTAssertEqual(summary.topups, 0)
    }

    /// Pre-#358 ledgers recorded the reversal as a `.topup` carrying the link.
    /// BOTH sides must drop out: the charge (it pairs on the link, not the
    /// type) and the reversal itself. Asserting only `spent`/`snoozeCount`
    /// here would miss the card claiming a +50 ₽ top-up that never happened
    /// against a balance that never moved.
    func testSummary_legacyTopupShapedRefund_cancelsBothSides() {
        let now = Date()
        let reversed = Transaction(type: .charge, amount: 50, createdAt: now)
        let summary = summary(of: [
            reversed,
            Transaction(type: .topup, amount: 50, createdAt: now,
                        refundsTransactionID: reversed.id)
        ])
        XCTAssertEqual(summary.spent, 0)
        XCTAssertEqual(summary.snoozeCount, 0)
        XCTAssertEqual(summary.topups, 0,
            "A legacy .topup-shaped reversal is not income — the card must not imply +50 ₽ of movement")
    }

    /// Only reversals are excluded — an organic top-up (no link) still counts,
    /// so the guard can't quietly zero out real revenue.
    func testSummary_organicTopupStillCounts_alongsideALegacyReversal() {
        let now = Date()
        let reversed = Transaction(type: .charge, amount: 50, createdAt: now)
        let summary = summary(of: [
            reversed,
            Transaction(type: .topup, amount: 50, createdAt: now,
                        refundsTransactionID: reversed.id),
            Transaction(type: .topup, amount: 500, createdAt: now)
        ])
        XCTAssertEqual(summary.topups, 500)
    }

    /// A refund can land in a different period than the charge it reverses
    /// (23:59 on the 31st → 00:00 on the 1st). The pairing is resolved against
    /// the full ledger, so the январь card must not bill a reversed snooze.
    func testSummary_refundInAdjacentPeriod_stillCancelsTheCharge() {
        let charge = Transaction(
            type: .charge, amount: 50,
            createdAt: date(year: 2026, month: 1, day: 31)
        )
        let refund = Transaction(
            type: .refund, amount: 50,
            createdAt: date(year: 2026, month: 2, day: 1),
            refundsTransactionID: charge.id
        )
        let january = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
            .filter([charge, refund])

        let scoped = TxHistorySummary.compute(from: january, ledger: [charge, refund])
        XCTAssertEqual(scoped.spent, 0, "A fully reversed snooze must not be billed in either period")
        XCTAssertEqual(scoped.snoozeCount, 0)

        // Guard the regression the full-ledger argument exists to prevent.
        let narrow = TxHistorySummary.compute(from: january, ledger: january)
        XCTAssertEqual(narrow.spent, 50,
            "Scoping the pairing to the visible slice is exactly the bug — pinned so the argument can't be dropped")
    }

    /// A row this build can't classify contributes to nothing.
    func testSummary_unknownType_isIgnored() {
        let summary = summary(of: [
            Transaction(type: .unknown("cashback"), amount: 10, createdAt: Date())
        ])
        XCTAssertEqual(summary, TxHistorySummary(spent: 0, topups: 0, snoozeCount: 0))
    }

    func testSummary_emptyList_allZero() {
        XCTAssertEqual(summary(of: []), TxHistorySummary(spent: 0, topups: 0, snoozeCount: 0))
    }

    // MARK: - Captions

    func testCaptions_singleMonth() {
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        XCTAssertEqual(period.chipCaption, "Январь 2026")
        XCTAssertEqual(period.summaryCaption, "январь 2026")
        XCTAssertEqual(period.pickerCaption, "Январь 2026")
        XCTAssertEqual(period.monthCountText, "1 мес.")
    }

    func testCaptions_range() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        XCTAssertEqual(period.chipCaption, "Ноя 2025 — Янв 2026")
        XCTAssertEqual(period.summaryCaption, "ноябрь 2025 — январь 2026")
        XCTAssertEqual(period.pickerCaption, "Ноябрь 2025 — Январь 2026")
        XCTAssertEqual(period.monthCountText, "3 мес.")
    }

    // MARK: - Picker selection state machine

    func testSelection_firstTap_selectsSingleMonth() {
        var selection = TxHistoryPeriodSelection()
        selection.tap(YearMonth(year: 2026, month: 1))
        XCTAssertEqual(selection.period, TxHistoryPeriod(month: YearMonth(year: 2026, month: 1)))
    }

    func testSelection_secondTap_extendsIntoRange() {
        var selection = TxHistoryPeriodSelection()
        selection.tap(YearMonth(year: 2025, month: 11))
        selection.tap(YearMonth(year: 2026, month: 1))
        XCTAssertEqual(
            selection.period,
            TxHistoryPeriod(start: YearMonth(year: 2025, month: 11), end: YearMonth(year: 2026, month: 1))
        )
    }

    func testSelection_secondTapBeforeAnchor_normalizesOrder() {
        var selection = TxHistoryPeriodSelection()
        selection.tap(YearMonth(year: 2026, month: 1))
        selection.tap(YearMonth(year: 2025, month: 11))
        XCTAssertEqual(
            selection.period,
            TxHistoryPeriod(start: YearMonth(year: 2025, month: 11), end: YearMonth(year: 2026, month: 1))
        )
    }

    func testSelection_thirdTap_restartsWithNewAnchor() {
        var selection = TxHistoryPeriodSelection()
        selection.tap(YearMonth(year: 2025, month: 11))
        selection.tap(YearMonth(year: 2026, month: 1))
        selection.tap(YearMonth(year: 2024, month: 6))
        XCTAssertEqual(selection.period, TxHistoryPeriod(month: YearMonth(year: 2024, month: 6)))
    }

    func testSelection_retapAnchor_keepsSingleSelection() {
        var selection = TxHistoryPeriodSelection()
        selection.tap(YearMonth(year: 2026, month: 1))
        selection.tap(YearMonth(year: 2026, month: 1))
        XCTAssertEqual(selection.period, TxHistoryPeriod(month: YearMonth(year: 2026, month: 1)))
    }

    func testSelection_reset_clearsPeriod() {
        var selection = TxHistoryPeriodSelection(
            period: TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        )
        selection.reset()
        XCTAssertNil(selection.period)
    }

    func testSelection_initFromExistingRange_roundTrips() {
        let range = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        XCTAssertEqual(TxHistoryPeriodSelection(period: range).period, range)
    }

    // MARK: - Grid cell roles

    func testCellRole_singleMonthSelection() {
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        XCTAssertEqual(
            PeriodPickerSheetViewController.role(of: YearMonth(year: 2026, month: 1), in: period),
            .single
        )
        XCTAssertEqual(
            PeriodPickerSheetViewController.role(of: YearMonth(year: 2025, month: 12), in: period),
            MonthCellRole.none
        )
    }

    func testCellRole_rangeEndpointsAndMiddle() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        XCTAssertEqual(
            PeriodPickerSheetViewController.role(of: YearMonth(year: 2025, month: 11), in: period), .start
        )
        XCTAssertEqual(
            PeriodPickerSheetViewController.role(of: YearMonth(year: 2025, month: 12), in: period), .mid
        )
        XCTAssertEqual(
            PeriodPickerSheetViewController.role(of: YearMonth(year: 2026, month: 1), in: period), .end
        )
        XCTAssertEqual(
            PeriodPickerSheetViewController.role(of: YearMonth(year: 2026, month: 2), in: period),
            MonthCellRole.none
        )
    }

    // MARK: - Capitalized chip caption (issue #282)

    func testChipCaption_singleMonth_isCapitalized() {
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        XCTAssertEqual(period.chipCaption, "Январь 2026")
    }

    func testChipCaption_range_capitalizesBothEndpoints() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        XCTAssertEqual(period.chipCaption, "Ноя 2025 — Янв 2026")
    }

    // MARK: - Type filter (issue #282)

    private func tx(_ type: TransactionType, month: Int) -> Transaction {
        Transaction(type: type, amount: 50, createdAt: date(year: 2026, month: month))
    }

    func testTypeFilter_all_passesEverything() {
        let list = [tx(.charge, month: 1), tx(.topup, month: 1), tx(.promotion, month: 1)]
        XCTAssertEqual(TxHistoryTypeFilter.all.filter(list).count, 3)
    }

    func testTypeFilter_charges_keepsOnlyDebits() {
        let list = [tx(.charge, month: 1), tx(.topup, month: 1), tx(.promotion, month: 1)]
        let filtered = TxHistoryTypeFilter.charges.filter(list)
        XCTAssertEqual(filtered.map(\.type), [.charge])
    }

    func testTypeFilter_credits_keepsTopupsPromotionsAndRefunds() {
        let list = [
            tx(.charge, month: 1), tx(.topup, month: 1),
            tx(.promotion, month: 1), tx(.refund, month: 1)
        ]
        let filtered = TxHistoryTypeFilter.credits.filter(list)
        XCTAssertEqual(Set(filtered.map(\.type.rawValue)), ["topup", "promotion", "refund"],
            "A refund puts money back in the wallet — the user reads it as «поступление» (#358)")
    }

    /// An unrecognised row has no known direction, so neither chip may claim
    /// it — it stays visible only under «Все».
    func testTypeFilter_unknownType_claimedByNeitherChip() {
        let list = [tx(.unknown("cashback"), month: 1)]
        XCTAssertEqual(TxHistoryTypeFilter.all.filter(list).count, 1)
        XCTAssertTrue(TxHistoryTypeFilter.charges.filter(list).isEmpty)
        XCTAssertTrue(TxHistoryTypeFilter.credits.filter(list).isEmpty)
    }

    func testTypeFilter_composesWithPeriod() {
        // Two months of mixed transactions; January period + charges chip
        // must keep only January charges.
        let list = [
            tx(.charge, month: 1), tx(.topup, month: 1),
            tx(.charge, month: 2), tx(.promotion, month: 2)
        ]
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        let periodVisible = period.filter(list)
        let composed = TxHistoryTypeFilter.charges.filter(periodVisible)
        XCTAssertEqual(composed.count, 1)
        XCTAssertEqual(composed.first?.type, .charge)
        XCTAssertTrue(period.contains(composed.first!.createdAt))
    }
}
