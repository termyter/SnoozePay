import XCTest
@testable import SnoozePay

/// Tests alarm-context resolution for charge rows (issue #282) — both the
/// pure `TransactionAlarmContext` resolver and the history screen's
/// `subtitle(for:time:lookup:)` composition, including the deleted-alarm
/// fallback.
final class TransactionAlarmContextTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func alarm(
        repeatDays: [Int],
        hour: Int,
        minute: Int = 0,
        name: String = "Поспать ещё"
    ) -> Alarm {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 15
        comps.hour = hour; comps.minute = minute
        return Alarm(time: calendar.date(from: comps)!, repeatDays: repeatDays, name: name)
    }

    // MARK: - Resolver

    func testCaption_weekdaysAlarm() {
        let sample = alarm(repeatDays: [0, 1, 2, 3, 4], hour: 7)
        XCTAssertEqual(
            TransactionAlarmContext.caption(for: sample, calendar: calendar),
            "Будни · 07:00"
        )
    }

    func testCaption_weekendAlarm() {
        let sample = alarm(repeatDays: [5, 6], hour: 9, minute: 30)
        XCTAssertEqual(
            TransactionAlarmContext.caption(for: sample, calendar: calendar),
            "Выходные · 09:30"
        )
    }

    func testCaption_resolvesByID() {
        let sample = alarm(repeatDays: [0, 1, 2, 3, 4], hour: 7)
        let caption = TransactionAlarmContext.caption(
            for: sample.id.uuidString, calendar: calendar, lookup: { $0 == sample.id ? sample : nil }
        )
        XCTAssertEqual(caption, "Будни · 07:00")
    }

    func testCaption_deletedAlarm_returnsNil() {
        let caption = TransactionAlarmContext.caption(
            for: UUID().uuidString, calendar: calendar, lookup: { _ in nil }
        )
        XCTAssertNil(caption)
    }

    func testCaption_nilID_returnsNil() {
        XCTAssertNil(
            TransactionAlarmContext.caption(for: nil, calendar: calendar, lookup: { _ in
                XCTFail("lookup must not run for nil id")
                return nil
            })
        )
    }

    func testCaption_malformedID_returnsNil() {
        XCTAssertNil(
            TransactionAlarmContext.caption(
                for: "not-a-uuid", calendar: calendar, lookup: { _ in nil }
            )
        )
    }

    // MARK: - History-screen subtitle composition

    func testSubtitle_chargeWithResolvableAlarm_showsAlarmContext() {
        let sample = alarm(repeatDays: [0, 1, 2, 3, 4], hour: 7)
        let tx = Transaction(type: .charge, amount: 50, alarmID: sample.id.uuidString)
        let subtitle = WalletTransactionHistoryViewController.subtitle(
            for: tx, time: "08:15", calendar: calendar, lookup: { $0 == sample.id ? sample : nil }
        )
        // Day-grouped list → row shows the alarm context, not the charge time.
        XCTAssertEqual(subtitle, "Будни · 07:00")
    }

    func testSubtitle_chargeMissingAlarm_fallsBackToBareTime() {
        let tx = Transaction(type: .charge, amount: 50, alarmID: UUID().uuidString)
        let subtitle = WalletTransactionHistoryViewController.subtitle(
            for: tx, time: "08:15", calendar: calendar, lookup: { _ in nil }
        )
        XCTAssertEqual(subtitle, "08:15")
    }

    func testSubtitle_nonChargeNeverGetsContext() {
        let sample = alarm(repeatDays: [0], hour: 7)
        let tx = Transaction(type: .topup, amount: 500, alarmID: sample.id.uuidString)
        let subtitle = WalletTransactionHistoryViewController.subtitle(
            for: tx, time: "08:15", calendar: calendar, lookup: { _ in sample }
        )
        XCTAssertEqual(subtitle, "08:15")
    }

    // MARK: - Unified promotion copy

    func testPromotionTitle_isHonestUnifiedCopy() {
        let tx = Transaction(type: .promotion, amount: 200)
        XCTAssertEqual(WalletTransactionHistoryViewController.title(for: tx), "Бонус за друга")
    }
}
