import XCTest
@testable import SnoozePay

/// Unit tests for `AlarmDeletionCopy` (#277) — the confirm-delete sheet copy
/// composer. The body must reassure that the balance stays put (deleting an
/// alarm never touches it), with the live amount rendered via
/// `MoneyFormatter`, and the context line must mirror the design's
/// «Будни · Пн–Пт · 07:00» phrasing.
final class AlarmDeletionCopyTests: XCTestCase {

    private let narrowSpace = MoneyFormatter.narrowSpace
    private let groupSpace = "\u{00A0}"   // ru-RU thousands separator

    /// 07:00 today — the design artboard's example time.
    private var sevenAM: Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    }

    // MARK: - body(contextLine:balance:)

    func testBody_withoutContext_reassuresBalanceStaysPut() {
        XCTAssertEqual(
            AlarmDeletionCopy.body(balance: 840),
            "Баланс 840\(narrowSpace)₽ останется на месте — "
                + "он привязан к аккаунту, а не к будильнику."
        )
    }

    func testBody_withContext_prependsContextSentence() {
        let body = AlarmDeletionCopy.body(contextLine: "Будни · Пн–Пт · 07:00", balance: 840)
        XCTAssertEqual(
            body,
            "Будни · Пн–Пт · 07:00. Баланс 840\(narrowSpace)₽ останется на месте — "
                + "он привязан к аккаунту, а не к будильнику."
        )
    }

    func testBody_emptyContext_degradesToReassuranceOnly() {
        XCTAssertEqual(
            AlarmDeletionCopy.body(contextLine: "", balance: 100),
            AlarmDeletionCopy.body(balance: 100)
        )
    }

    func testBody_groupsThousandsViaMoneyFormatter() {
        let body = AlarmDeletionCopy.body(balance: 1234)
        XCTAssertTrue(
            body.contains("1\(groupSpace)234\(narrowSpace)₽"),
            "Balance must render through fmtRub grouping: \(body)"
        )
    }

    func testBody_neverClaimsMoneyIsLost() {
        let body = AlarmDeletionCopy.body(contextLine: "Будни · Пн–Пт · 07:00", balance: 50)
        XCTAssertFalse(body.contains("не вернутся"), "Pre-#277 false claim must be gone: \(body)")
        XCTAssertFalse(body.contains("безвозвратно"), "Pre-#277 false claim must be gone: \(body)")
    }

    // MARK: - contextLine — weekly buckets

    func testContextLine_weeklyWeekdays_matchesDesignExample() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [0, 1, 2, 3, 4], repeatMode: .weekly, time: sevenAM
        )
        XCTAssertEqual(line, "Будни · Пн–Пт · 07:00")
    }

    func testContextLine_weeklyWeekend() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [5, 6], repeatMode: .weekly, time: sevenAM
        )
        XCTAssertEqual(line, "Выходные · Сб–Вс · 07:00")
    }

    func testContextLine_weeklyEveryDay() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: Array(0...6), repeatMode: .weekly, time: sevenAM
        )
        XCTAssertEqual(line, "Каждый день · 07:00")
    }

    func testContextLine_weeklySubset_listsDayNamesSorted() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [3, 1], repeatMode: .weekly, time: sevenAM
        )
        XCTAssertEqual(line, "Вт, Чт · 07:00")
    }

    // MARK: - contextLine — one-shot

    func testContextLine_noDays_isOneShot() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [], repeatMode: .weekly, time: sevenAM
        )
        XCTAssertEqual(line, "Единожды · 07:00")
    }

    func testContextLine_neverMode_weekdays_usesCompactRange() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [0, 1, 2, 3, 4], repeatMode: .never, time: sevenAM
        )
        XCTAssertEqual(line, "Единожды · Пн–Пт · 07:00")
    }

    func testContextLine_neverMode_noDays() {
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [], repeatMode: .never, time: sevenAM
        )
        XCTAssertEqual(line, "Единожды · 07:00")
    }

    // MARK: - contextLine — robustness

    func testContextLine_dropsOutOfRangeDayIndices() {
        // Corrupt storage can carry indices outside 0...6 (#72) — the copy
        // composer must drop them instead of crashing or rendering garbage.
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [-1, 0, 1, 2, 3, 4, 7], repeatMode: .weekly, time: sevenAM
        )
        XCTAssertEqual(line, "Будни · Пн–Пт · 07:00")
    }

    func testContextLine_rendersTimeAs24Hour() {
        let evening = Calendar.current.date(
            bySettingHour: 19, minute: 5, second: 0, of: Date()
        )!
        let line = AlarmDeletionCopy.contextLine(
            repeatDays: [5, 6], repeatMode: .weekly, time: evening
        )
        XCTAssertEqual(line, "Выходные · Сб–Вс · 19:05")
    }
}
