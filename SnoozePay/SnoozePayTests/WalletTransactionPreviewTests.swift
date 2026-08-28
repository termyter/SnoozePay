import XCTest
@testable import SnoozePay

/// Tests the Wallet tab's transaction-preview builder (issue #233) —
/// ordering, 3-row cap, per-type formatting and relative timestamps.
final class WalletTransactionPreviewTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Helpers

    private func date(daysAgo: Int, from now: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: now)!
    }

    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Cap + ordering

    func testItems_cappedAtThree() {
        let transactions = (0..<5).map { idx in
            Transaction(type: .charge, amount: 50, createdAt: date(daysAgo: idx))
        }
        let items = WalletTransactionPreview.items(from: transactions)
        XCTAssertEqual(items.count, 3)
    }

    func testItems_sortedNewestFirst_evenIfInputUnsorted() {
        let now = Date()
        let oldest = Transaction(type: .charge, amount: 50, createdAt: date(daysAgo: 2, from: now))
        let newest = Transaction(type: .topup, amount: 500, createdAt: now)
        let middle = Transaction(type: .promotion, amount: 200, createdAt: date(daysAgo: 1, from: now))
        let items = WalletTransactionPreview.items(from: [oldest, newest, middle], now: now)
        XCTAssertEqual(items.map(\.title), ["Пополнение баланса", "Бонус за друга", "Поспать ещё"])
    }

    func testItems_emptyInput_returnsEmpty() {
        XCTAssertTrue(WalletTransactionPreview.items(from: []).isEmpty)
    }

    // MARK: - Per-type formatting

    func testChargeItem_isRedFlameWithMinusAmount() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .charge, amount: 50, createdAt: Date())
        )
        XCTAssertEqual(item.title, "Поспать ещё")
        XCTAssertTrue(item.isDebit)
        XCTAssertEqual(item.iconSystemName, "flame")
        XCTAssertEqual(item.amountText, "−50\u{202F}₽")
    }

    func testTopupItem_isGreenPlusWithPlusAmount() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .topup, amount: 500, createdAt: Date())
        )
        XCTAssertEqual(item.title, "Пополнение баланса")
        XCTAssertFalse(item.isDebit)
        XCTAssertEqual(item.iconSystemName, "plus")
        XCTAssertEqual(item.amountText, "+500\u{202F}₽")
    }

    /// #358 introduced `.refund` — the row must render as its own thing, not
    /// silently fall back to top-up copy (or crash a `default` branch).
    func testRefundItem_readsAsAReversalNotATopup() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .refund, amount: 50, createdAt: Date())
        )
        XCTAssertEqual(item.title, "Возврат за откладывание")
        XCTAssertFalse(item.isDebit, "The money comes back to the user")
        XCTAssertEqual(item.iconSystemName, "arrow.uturn.backward")
        XCTAssertEqual(item.amountText, "+50\u{202F}₽")
    }

    /// A row written by a newer build must still render (see
    /// `TransactionType.unknown`) — with no sign, since the direction is
    /// genuinely unknown.
    func testUnknownItem_rendersNeutrallyWithoutASign() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .unknown("cashback"), amount: 10, createdAt: Date())
        )
        XCTAssertEqual(item.title, "Операция")
        XCTAssertEqual(item.iconSystemName, "questionmark")
        XCTAssertEqual(item.amountText, "10\u{202F}₽")
    }

    func testPromotionItem_isGreenGiftWithHonestCopy() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .promotion, amount: 200, createdAt: Date())
        )
        // Honest, unified copy — no nonexistent 7-day hold (issue #282).
        XCTAssertEqual(item.title, "Бонус за друга")
        XCTAssertFalse(item.isDebit)
        XCTAssertEqual(item.iconSystemName, "gift")
        XCTAssertEqual(item.amountText, "+200\u{202F}₽")
    }

    // MARK: - Alarm context on charge rows (issue #282)

    func testChargeItem_appendsAlarmContextWhenResolvable() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 15; comps.hour = 7; comps.minute = 0
        let alarmTime = calendar.date(from: comps)!
        let alarm = Alarm(time: alarmTime, repeatDays: [0, 1, 2, 3, 4], name: "Поспать ещё")
        let tx = Transaction(
            type: .charge, amount: 50, alarmID: alarm.id.uuidString, createdAt: Date()
        )
        let item = WalletTransactionPreview.item(
            for: tx, alarmLookup: { $0 == alarm.id ? alarm : nil }
        )
        XCTAssertTrue(
            item.timestampText.hasPrefix("Будни · 07:00 · "),
            "got: \(item.timestampText)"
        )
    }

    func testChargeItem_missingAlarm_degradesToBareTimestamp() {
        let tx = Transaction(
            type: .charge, amount: 50, alarmID: UUID().uuidString, createdAt: Date()
        )
        // Lookup never resolves → no "Будни" prefix, just the timestamp.
        let item = WalletTransactionPreview.item(for: tx, alarmLookup: { _ in nil })
        XCTAssertFalse(item.timestampText.contains(" · 07:00 · "))
        XCTAssertTrue(item.timestampText.hasPrefix("Сегодня · "), "got: \(item.timestampText)")
    }

    func testChargeItem_nilAlarmID_degradesToBareTimestamp() {
        let tx = Transaction(type: .charge, amount: 50, alarmID: nil, createdAt: Date())
        let item = WalletTransactionPreview.item(for: tx, alarmLookup: { _ in
            XCTFail("lookup must not run for a nil alarmID")
            return nil
        })
        XCTAssertTrue(item.timestampText.hasPrefix("Сегодня · "), "got: \(item.timestampText)")
    }

    func testTopupItem_ignoresAlarmContext() {
        let alarm = Alarm(time: Date(), repeatDays: [0], name: "x")
        let tx = Transaction(
            type: .topup, amount: 500, alarmID: alarm.id.uuidString, createdAt: Date()
        )
        // Non-charge rows never carry alarm context even if an id leaks in.
        let item = WalletTransactionPreview.item(for: tx, alarmLookup: { _ in alarm })
        XCTAssertTrue(item.timestampText.hasPrefix("Сегодня · "), "got: \(item.timestampText)")
    }

    func testAmountText_usesRussianThousandsSeparator() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .topup, amount: 1500, createdAt: Date())
        )
        // `Decimal.formattedRubles()` inserts the ru_RU group separator —
        // never a hand-rolled "1500 ₽".
        XCTAssertEqual(item.amountText, "+1\u{00a0}500\u{202F}₽")
    }

    // MARK: - Relative timestamps

    func testTimestamp_today() {
        let now = Date()
        let text = WalletTransactionPreview.timestampText(for: now, now: now, calendar: calendar)
        XCTAssertEqual(text, "Сегодня · \(timeString(for: now))")
    }

    func testTimestamp_yesterday() {
        let now = Date()
        let yesterday = date(daysAgo: 1, from: now)
        let text = WalletTransactionPreview.timestampText(for: yesterday, now: now, calendar: calendar)
        XCTAssertEqual(text, "Вчера · \(timeString(for: yesterday))")
    }

    func testTimestamp_older_usesDayMonthFormat() {
        let now = Date()
        let older = date(daysAgo: 10, from: now)
        let text = WalletTransactionPreview.timestampText(for: older, now: now, calendar: calendar)
        XCTAssertFalse(text.hasPrefix("Сегодня"))
        XCTAssertFalse(text.hasPrefix("Вчера"))
        XCTAssertTrue(text.hasSuffix("· \(timeString(for: older))"), "got: \(text)")
        let day = calendar.component(.day, from: older)
        XCTAssertTrue(text.hasPrefix("\(day) "), "got: \(text)")
    }
}
