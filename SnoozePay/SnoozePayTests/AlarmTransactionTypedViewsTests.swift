import XCTest
@testable import SnoozePay

/// Integration tests for the phase-1 typed views layered onto the legacy
/// `Alarm` and `Transaction` primitives (issue #31). These pin the bridge
/// contracts that phase-2 migration will rely on — off-by-one in `weekdays`
/// would silently fire alarms on the wrong day, `Money?` returning `nil` for
/// corrupt legacy data would silently drop charges in the UI.
final class AlarmTransactionTypedViewsTests: XCTestCase {

    // MARK: - Alarm.timeOfDay

    func testAlarmTimeOfDay_extractsHourAndMinuteFromCurrentCalendar() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: 7, minute: 30))!
        let alarm = Alarm(time: date)

        let timeOfDay = alarm.timeOfDay
        XCTAssertNotNil(timeOfDay)
        XCTAssertEqual(timeOfDay?.hour, 7)
        XCTAssertEqual(timeOfDay?.minute, 30)
    }

    // MARK: - Alarm.weekdays (off-by-one regression fence)

    func testAlarmWeekdays_legacyZeroIsMondayNotSunday() {
        // Legacy storage convention: 0 = Monday. Calendar.weekday convention:
        // 1 = Sunday. Bridge must NOT shift the origin — testing both endpoints.
        let alarm = Alarm(repeatDays: [0])
        XCTAssertEqual(alarm.weekdays, [.monday])
    }

    func testAlarmWeekdays_legacySixIsSunday() {
        let alarm = Alarm(repeatDays: [6])
        XCTAssertEqual(alarm.weekdays, [.sunday])
    }

    func testAlarmWeekdays_emptyRepeatDaysProducesEmptySet() {
        let alarm = Alarm(repeatDays: [])
        XCTAssertTrue(alarm.weekdays.isEmpty)
    }

    func testAlarmWeekdays_dropsOutOfRangeLegacyIntegers() {
        // Corrupted legacy data (`-1`, `8`, `99`) must not crash; the bridge
        // silently drops invalid indices, mirroring `repeatDaysDescription`.
        let alarm = Alarm(repeatDays: [-1, 0, 8, 99, 6])
        XCTAssertEqual(alarm.weekdays, [.monday, .sunday])
    }

    func testAlarmWeekdays_deduplicatesSetSemantics() {
        let alarm = Alarm(repeatDays: [0, 0, 1])
        XCTAssertEqual(alarm.weekdays, [.monday, .tuesday])
    }

    // MARK: - Alarm.penaltyMoney

    func testAlarmPenaltyMoney_positiveAmountWraps() {
        let alarm = Alarm(penaltyAmount: 50)
        XCTAssertEqual(alarm.penaltyMoney, Money(50))
    }

    func testAlarmPenaltyMoney_zeroIsValidMoneyZero() {
        let alarm = Alarm(penaltyAmount: 0)
        XCTAssertEqual(alarm.penaltyMoney, .zero)
    }

    func testAlarmPenaltyMoney_negativeLegacyValueReturnsNil() {
        // The primitive setter never validated, so corrupt persisted alarms
        // could carry a negative `penaltyAmount`. The typed view surfaces this
        // as `nil` so phase-2 callers must explicitly handle it.
        let alarm = Alarm(penaltyAmount: -50)
        XCTAssertNil(alarm.penaltyMoney)
    }

    func testAlarmPenaltyMoney_nanReturnsNil() {
        let alarm = Alarm(penaltyAmount: .nan)
        XCTAssertNil(alarm.penaltyMoney)
    }

    // MARK: - Transaction.money

    func testTransactionMoney_positiveAmountWraps() {
        let transaction = Transaction(type: .topup, amount: 100)
        XCTAssertEqual(transaction.money, Money(100))
    }

    func testTransactionMoney_zeroIsValid() {
        let transaction = Transaction(type: .charge, amount: 0)
        XCTAssertEqual(transaction.money, .zero)
    }

    func testTransactionMoney_negativeLegacyValueReturnsNil() {
        let transaction = Transaction(type: .charge, amount: -10)
        XCTAssertNil(transaction.money)
    }

    func testTransactionMoney_nanReturnsNil() {
        let transaction = Transaction(type: .topup, amount: .nan)
        XCTAssertNil(transaction.money)
    }
}
