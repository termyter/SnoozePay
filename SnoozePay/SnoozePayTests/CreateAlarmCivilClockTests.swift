import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class CreateAlarmCivilClockTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var repository: AlarmRepository!
    private var wallet: BalanceService!

    override func setUp() {
        super.setUp()
        suite = "test.createAlarmCivilClock.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        repository = AlarmRepository(defaults: defaults, scheduler: ClockScheduler())
        let ledger = TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
        wallet = BalanceService(defaults: defaults, transactionRepository: ledger,
                                notificationCenter: NotificationCenter())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNewAlarmSavesSevenAndReopensAsSevenInAnotherTimezone() throws {
        let editor = makeEditor(calendar: calendar(offsetHours: 3))
        editor.enabled = false
        assertClock(editor.clockTime, 7, 0)
        XCTAssertTrue(editor.save())

        let saved = try storedAlarm()
        assertClock(saved.clockTime, 7, 0)
        let reloaded = try XCTUnwrap(try AlarmRepository(
            defaults: defaults, scheduler: ClockScheduler()
        ).fetchAllChecked().first)
        let reopened = makeEditor(alarm: reloaded, calendar: calendar(offsetHours: 1))
        assertClock(reopened.selectedTimeOfDay, 7, 0)
        assertClock(TimeOfDay(from: reopened.pickerTime, calendar: reopened.pickerCalendar), 7, 0)
        XCTAssertEqual(reopened.time, saved.time, "reopening must not rewrite the compatibility Date")
    }

    func testLegacyUnrelatedEditsKeepRawDateAndDoNotAdoptClock() throws {
        let legacy = legacyAlarm()
        XCTAssertTrue(repository.save(legacy))
        let editor = makeEditor(alarm: legacy, calendar: calendar(offsetHours: 1))
        assertClock(editor.selectedTimeOfDay, 5, 0)
        XCTAssertNil(editor.clockTime)
        editor.name = "Renamed"
        editor.theme = .ocean
        editor.toggleDay(4)
        editor.repeatMode = .weekly
        editor.enabled.toggle()
        editor.enabled.toggle()
        XCTAssertTrue(editor.save())

        let saved = try storedAlarm()
        XCTAssertNil(saved.clockTime)
        XCTAssertEqual(saved.time, legacy.time)
        XCTAssertEqual(saved.id, legacy.id)
        XCTAssertEqual(saved.name, "Renamed")
        XCTAssertEqual(saved.theme, .ocean)
        XCTAssertEqual(saved.repeatDays, [0, 4])
        let reopened = makeEditor(alarm: saved, calendar: calendar(offsetHours: -8))
        assertClock(reopened.selectedTimeOfDay, 20, 0)
        XCTAssertNil(reopened.clockTime, "legacy continues to use the reopening timezone")
    }

    func testNoopPickerCallbackWithDifferentReferenceDayPreservesLegacyDate() throws {
        let legacy = legacyAlarm()
        let editor = makeEditor(alarm: legacy, calendar: calendar(offsetHours: 1))
        editor.selectPickerTime(date(2030, 6, 1, 5, 0, calendar: calendar(offsetHours: 0)))
        XCTAssertNil(editor.clockTime)
        XCTAssertEqual(editor.time, legacy.time)
        XCTAssertTrue(editor.save())
        XCTAssertNil(try storedAlarm().clockTime)
        XCTAssertEqual(try storedAlarm().time, legacy.time)
    }

    func testChangedThenReturnedPickerClockIsAnExplicitRetime() throws {
        let legacy = legacyAlarm()
        let editor = makeEditor(alarm: legacy, calendar: calendar(offsetHours: 1))
        editor.selectPickerTime(pickerDate(6, 15))
        editor.selectPickerTime(pickerDate(5, 0))
        assertClock(editor.clockTime, 5, 0)
        XCTAssertTrue(editor.save())
        let saved = try storedAlarm()
        XCTAssertEqual(saved.time, legacy.time)
        assertClock(saved.clockTime, 5, 0)
        let reopened = makeEditor(alarm: saved, calendar: calendar(offsetHours: 3))
        assertClock(reopened.selectedTimeOfDay, 5, 0)
    }

    func testDirectDateAssignmentAdoptsOnlyChangedHourOrMinute() {
        let legacy = legacyAlarm()
        let local = calendar(offsetHours: 1)
        let editor = makeEditor(alarm: legacy, calendar: local)
        editor.time = date(2026, 10, 26, 5, 0, calendar: local)
        XCTAssertNil(editor.clockTime, "a different date with the same clock does not confirm legacy intent")
        editor.time = date(2026, 10, 26, 5, 20, calendar: local)
        assertClock(editor.clockTime, 5, 20)
        assertClock(editor.selectedTimeOfDay, 5, 20)
    }

    func testExistingCivilClockWinsOverRawDateDuringUnrelatedSave() throws {
        let legacy = legacyAlarm()
        let civil = Alarm(id: legacy.id, time: legacy.time, clockTime: TimeOfDay(hour: 7, minute: 30),
                          repeatDays: [0], enabled: false)
        let editor = makeEditor(alarm: civil, calendar: calendar(offsetHours: 1))
        assertClock(editor.selectedTimeOfDay, 7, 30)
        editor.selectPickerTime(editor.pickerTime)
        editor.name = "Still civil"
        XCTAssertTrue(editor.save())
        let saved = try storedAlarm()
        XCTAssertEqual(saved.time, legacy.time)
        assertClock(saved.clockTime, 7, 30)
        assertClock(makeEditor(alarm: saved, calendar: calendar(offsetHours: -8)).selectedTimeOfDay, 7, 30)
    }

    func testDSTTransitionDaysKeepChosenComponentsInFixedPickerBridge() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        for (month, day) in [(3, 29), (10, 25)] {
            let editor = makeEditor(calendar: berlin, now: date(2026, month, day, 12, 0, calendar: berlin))
            editor.enabled = false
            editor.selectPickerTime(pickerDate(2, 30))
            assertClock(editor.clockTime, 2, 30)
            assertClock(TimeOfDay(from: editor.pickerTime, calendar: editor.pickerCalendar), 2, 30)
            XCTAssertEqual(editor.pickerCalendar.timeZone.secondsFromGMT(for: editor.pickerTime), 0)
            let previousIDs = Set(try repository.fetchAllChecked().map(\.id))
            XCTAssertTrue(editor.save())
            let saved = try XCTUnwrap(try repository.fetchAllChecked().first { !previousIDs.contains($0.id) })
            assertClock(saved.clockTime, 2, 30)
        }
    }

    func testEditorCapturesCalendarWhileReopeningLegacyUsesNewCalendar() {
        let legacy = legacyAlarm()
        var opening = calendar(offsetHours: 1)
        let editor = makeEditor(alarm: legacy, calendar: opening)
        opening.timeZone = calendar(offsetHours: 9).timeZone
        assertClock(editor.selectedTimeOfDay, 5, 0)
        assertClock(makeEditor(alarm: legacy, calendar: opening).selectedTimeOfDay, 13, 0)
        editor.selectPickerTime(pickerDate(6, 0))
        assertClock(editor.clockTime, 6, 0)
        assertClock(TimeOfDay(from: editor.time, calendar: calendar(offsetHours: 1)), 6, 0)
    }

    func testCancellingRetimeDoesNotPersistClockOrDate() throws {
        let legacy = legacyAlarm()
        XCTAssertTrue(repository.save(legacy))
        let before = try XCTUnwrap(defaults.data(forKey: "stored_alarms"))
        let editor = makeEditor(alarm: legacy, calendar: calendar(offsetHours: 1))
        let controller = CreateAlarmViewController(viewModel: editor)
        controller.loadViewIfNeeded()
        editor.selectPickerTime(pickerDate(8, 15))
        assertClock(editor.clockTime, 8, 15)
        let barView = try XCTUnwrap(controller.navigationItem.leftBarButtonItem?.customView)
        let cancel = try XCTUnwrap(views(in: barView).first {
            $0.accessibilityIdentifier == "createAlarm.cancelButton"
        } as? UIControl)
        cancel.sendActions(for: .touchUpInside)
        XCTAssertEqual(defaults.data(forKey: "stored_alarms"), before, "cancel must not save the selected clock")
        let saved = try storedAlarm()
        XCTAssertNil(saved.clockTime)
        XCTAssertEqual(saved.time, legacy.time)
    }

    func testCorruptStoreStillRefusesEditorSaveAndPreservesBytes() throws {
        let editor = makeEditor(alarm: legacyAlarm(), calendar: calendar(offsetHours: 1))
        let corrupt = Data("broken alarm clock fixture".utf8)
        defaults.set(corrupt, forKey: "stored_alarms")
        XCTAssertThrowsError(try repository.fetchAllChecked())
        editor.selectPickerTime(pickerDate(8, 15))
        XCTAssertFalse(editor.save())
        var outcomes: [CreateAlarmViewModel.SaveOutcome] = []
        editor.save { outcomes.append($0) }
        XCTAssertEqual(outcomes, [.persistFailed])
        XCTAssertTrue(repository.lastLoadFailed)
        XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
        XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
    }

    func testControllerPickerWiringUsesUTCAndOnlyChangedClockAdoptsLegacy() throws {
        let legacy = legacyAlarm()
        let editor = makeEditor(alarm: legacy, calendar: calendar(offsetHours: 1))
        let controller = CreateAlarmViewController(viewModel: editor)
        controller.registerSectionCells(in: controller.tableView)
        let cell = try XCTUnwrap(controller.makeTimePickerCell(
            controller.tableView, at: IndexPath(row: 0, section: CreateAlarmViewController.Section.timePicker.rawValue)
        ) as? TimePickerCell)
        let picker = try XCTUnwrap(views(in: cell).compactMap { $0 as? UIDatePicker }.first)
        XCTAssertEqual(picker.calendar.identifier, .gregorian)
        XCTAssertEqual(picker.timeZone?.secondsFromGMT(for: picker.date), 0)
        assertClock(TimeOfDay(from: picker.date, calendar: editor.pickerCalendar), 5, 0)
        picker.sendActions(for: .valueChanged)
        XCTAssertNil(editor.clockTime)
        XCTAssertEqual(editor.time, legacy.time)
        picker.date = pickerDate(6, 40)
        picker.sendActions(for: .valueChanged)
        assertClock(editor.clockTime, 6, 40)
        XCTAssertTrue(editor.save())
        assertClock(try storedAlarm().clockTime, 6, 40)
    }

    func testCellUsesInjectedCalendarForPickerAndReadout() throws {
        let cell = TimePickerCell(style: .default, reuseIdentifier: nil)
        let local = calendar(offsetHours: 9)
        let instant = pickerDate(22, 15)
        var callbacks = 0
        cell.onTimeChanged = { _ in callbacks += 1 }
        cell.configure(time: instant, calendar: local)
        let picker = try XCTUnwrap(views(in: cell).compactMap { $0 as? UIDatePicker }.first)
        XCTAssertEqual(callbacks, 0, "configuration must not adopt an editor clock")
        XCTAssertEqual(picker.timeZone?.secondsFromGMT(for: instant), 9 * 3_600)
        XCTAssertEqual(picker.calendar.timeZone, local.timeZone)
        let expected = WallClockFormatter.string(from: instant, style: .padded, calendar: local)
        let strings = views(in: cell).compactMap { ($0 as? UILabel)?.attributedText?.string }
        XCTAssertTrue(strings.contains(expected))
        picker.sendActions(for: .valueChanged)
        XCTAssertEqual(callbacks, 1)
        cell.prepareForReuse()
        picker.sendActions(for: .valueChanged)
        XCTAssertEqual(callbacks, 1, "reuse must clear the previous editor callback")
    }

    private func makeEditor(
        alarm: Alarm? = nil, calendar: Calendar,
        now: Date = Date(timeIntervalSince1970: 1_793_001_600)
    ) -> CreateAlarmViewModel {
        CreateAlarmViewModel(alarm: alarm, repository: repository, defaults: AlarmDefaults(defaults: defaults),
                             balanceService: wallet, calendar: calendar, now: now)
    }

    private func legacyAlarm() -> Alarm {
        Alarm(time: date(2026, 10, 25, 7, 0, calendar: calendar(offsetHours: 3)),
              repeatDays: [0], name: "Legacy", enabled: false)
    }

    private func storedAlarm() throws -> Alarm {
        try XCTUnwrap(try repository.fetchAllChecked().first)
    }

    private func calendar(offsetHours: Int) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: offsetHours * 3_600)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
                      calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func pickerDate(_ hour: Int, _ minute: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(hour * 3_600 + minute * 60))
    }

    private func assertClock(_ clock: TimeOfDay?, _ hour: Int, _ minute: Int,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(clock?.hour, hour, file: file, line: line)
        XCTAssertEqual(clock?.minute, minute, file: file, line: line)
    }

    private func views(in view: UIView) -> [UIView] { [view] + view.subviews.flatMap { views(in: $0) } }

    private final class ClockScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}
