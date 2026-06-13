import XCTest
@testable import SnoozePay

/// Read/write coverage for the global `AlarmDefaults` store that seeds new
/// alarms (#283). Each test uses an isolated `UserDefaults` suite so the
/// app's real defaults are never touched.
final class AlarmDefaultsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: AlarmDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmdefaults.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        sut = AlarmDefaults(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Snooze duration

    func testSnoozeMinutes_defaultsToFactoryFallback() {
        XCTAssertEqual(sut.snoozeMinutes, AlarmDefaults.fallbackSnoozeMinutes)
        XCTAssertEqual(sut.snoozeMinutes, 9)
    }

    func testSnoozeMinutes_persistsWrite() {
        sut.snoozeMinutes = 5
        XCTAssertEqual(sut.snoozeMinutes, 5)
        // Survives a fresh accessor on the same suite.
        XCTAssertEqual(AlarmDefaults(defaults: defaults).snoozeMinutes, 5)
    }

    func testSnoozeMinutes_clampsAboveRange() {
        sut.snoozeMinutes = 999
        XCTAssertEqual(sut.snoozeMinutes, Alarm.snoozeMinutesRange.upperBound)
    }

    func testSnoozeMinutes_clampsBelowRange() {
        sut.snoozeMinutes = -3
        XCTAssertEqual(sut.snoozeMinutes, Alarm.snoozeMinutesRange.lowerBound)
    }

    // MARK: - Volume

    func testVolume_defaultsToFull() {
        XCTAssertEqual(sut.volume, 1.0, accuracy: 0.0001)
    }

    func testVolume_persistsWrite() {
        sut.volume = 0.8
        XCTAssertEqual(sut.volume, 0.8, accuracy: 0.0001)
        XCTAssertEqual(AlarmDefaults(defaults: defaults).volume, 0.8, accuracy: 0.0001)
    }

    func testVolume_clampsOutOfRange() {
        sut.volume = 2.5
        XCTAssertEqual(sut.volume, 1.0, accuracy: 0.0001)
        sut.volume = -1.0
        XCTAssertEqual(sut.volume, 0.0, accuracy: 0.0001)
    }

    func testVolume_nonFiniteFallsBackToFull() {
        sut.volume = .nan
        XCTAssertEqual(sut.volume, AlarmDefaults.fallbackVolume, accuracy: 0.0001)
    }

    // MARK: - Vibration

    func testVibration_defaultsToTrue() {
        XCTAssertTrue(sut.vibrationEnabled)
    }

    func testVibration_persistsWrite() {
        sut.vibrationEnabled = false
        XCTAssertFalse(sut.vibrationEnabled)
        XCTAssertFalse(AlarmDefaults(defaults: defaults).vibrationEnabled)
    }

    // MARK: - Progressive price

    func testProgressive_defaultsToFalse() {
        XCTAssertFalse(sut.progressiveScale)
    }

    func testProgressive_persistsWrite() {
        sut.progressiveScale = true
        XCTAssertTrue(sut.progressiveScale)
        XCTAssertTrue(AlarmDefaults(defaults: defaults).progressiveScale)
    }

    // MARK: - Default snooze price (#315)

    func testPenaltyAmount_defaultsToFactoryFallback() {
        XCTAssertEqual(sut.penaltyAmount, AlarmDefaults.fallbackPenaltyAmount, accuracy: 0.0001)
        XCTAssertEqual(sut.penaltyAmount, 50, accuracy: 0.0001)
    }

    func testPenaltyAmount_persistsWrite() {
        sut.penaltyAmount = 200
        XCTAssertEqual(sut.penaltyAmount, 200, accuracy: 0.0001)
        XCTAssertEqual(AlarmDefaults(defaults: defaults).penaltyAmount, 200, accuracy: 0.0001)
    }

    func testPenaltyAmount_floorsAtOne() {
        sut.penaltyAmount = 0
        XCTAssertEqual(sut.penaltyAmount, 1, accuracy: 0.0001)
        sut.penaltyAmount = -100
        XCTAssertEqual(sut.penaltyAmount, 1, accuracy: 0.0001)
    }

    func testPenaltyAmount_hasNoUpperCap() {
        sut.penaltyAmount = 99_999
        XCTAssertEqual(sut.penaltyAmount, 99_999, accuracy: 0.0001)
    }

    func testPenaltyAmount_nonFiniteFallsBack() {
        sut.penaltyAmount = .nan
        XCTAssertEqual(sut.penaltyAmount, AlarmDefaults.fallbackPenaltyAmount, accuracy: 0.0001)
    }

    // MARK: - Seeds new alarms

    func testDefaults_seedNewAlarmDraft() {
        sut.snoozeMinutes = 5
        sut.vibrationEnabled = false
        sut.volume = 0.8
        sut.progressiveScale = true
        sut.penaltyAmount = 150

        let viewModel = CreateAlarmViewModel(alarm: nil, defaults: sut)

        XCTAssertEqual(viewModel.snoozeMinutes, 5)
        XCTAssertFalse(viewModel.vibrationEnabled)
        XCTAssertEqual(viewModel.volume, 0.8, accuracy: 0.0001)
        XCTAssertTrue(viewModel.progressiveScale)
        XCTAssertEqual(viewModel.penaltyAmount, 150, accuracy: 0.0001)
    }

    func testDefaults_doNotOverrideExistingAlarm() {
        sut.snoozeMinutes = 5
        sut.vibrationEnabled = false
        sut.penaltyAmount = 150

        let existing = Alarm(vibrationEnabled: true, snoozeMinutes: 12, penaltyAmount: 75)
        let viewModel = CreateAlarmViewModel(alarm: existing, defaults: sut)

        // Editing keeps the alarm's own values, ignoring the global default.
        XCTAssertEqual(viewModel.snoozeMinutes, 12)
        XCTAssertTrue(viewModel.vibrationEnabled)
        XCTAssertEqual(viewModel.penaltyAmount, 75, accuracy: 0.0001)
    }
}
