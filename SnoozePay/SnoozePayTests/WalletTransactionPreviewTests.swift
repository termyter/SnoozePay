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
        XCTAssertEqual(items.map(\.title), ["Пополнение баланса", "Промо-зачисление", "Поспать ещё"])
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

    func testPromotionItem_isGreenGiftWithPlusAmount() {
        let item = WalletTransactionPreview.item(
            for: Transaction(type: .promotion, amount: 200, createdAt: Date())
        )
        XCTAssertEqual(item.title, "Промо-зачисление")
        XCTAssertFalse(item.isDebit)
        XCTAssertEqual(item.iconSystemName, "gift")
        XCTAssertEqual(item.amountText, "+200\u{202F}₽")
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
