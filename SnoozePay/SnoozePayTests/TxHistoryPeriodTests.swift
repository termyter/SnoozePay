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

    func testSummary_aggregatesSpentTopupsAndSnoozeCount() {
        let now = Date()
        let summary = TxHistorySummary.compute(from: [
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
        let summary = TxHistorySummary.compute(from: [
            Transaction(type: .topup, amount: 500, createdAt: now),
            Transaction(type: .promotion, amount: 200, createdAt: now)
        ])
        XCTAssertEqual(summary.topups, 500, "Bonus credits must not inflate Пополнения")
        XCTAssertEqual(summary.spent, 0)
        XCTAssertEqual(summary.snoozeCount, 0)
    }

    func testSummary_emptyList_allZero() {
        let summary = TxHistorySummary.compute(from: [])
        XCTAssertEqual(summary, TxHistorySummary(spent: 0, topups: 0, snoozeCount: 0))
    }

    // MARK: - Captions

    func testCaptions_singleMonth() {
        let period = TxHistoryPeriod(month: YearMonth(year: 2026, month: 1))
        XCTAssertEqual(period.chipCaption, "январь 2026")
        XCTAssertEqual(period.summaryCaption, "январь 2026")
        XCTAssertEqual(period.pickerCaption, "Январь 2026")
        XCTAssertEqual(period.monthCountText, "1 мес.")
    }

    func testCaptions_range() {
        let period = TxHistoryPeriod(
            start: YearMonth(year: 2025, month: 11),
            end: YearMonth(year: 2026, month: 1)
        )
        XCTAssertEqual(period.chipCaption, "ноя 2025 — янв 2026")
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
}
