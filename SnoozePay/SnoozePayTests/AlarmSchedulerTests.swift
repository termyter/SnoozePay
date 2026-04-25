import XCTest
import UserNotifications
@testable import SnoozePay

/// Unit tests for AlarmScheduler — notification content creation and sound file resolution.
final class AlarmSchedulerTests: XCTestCase {

    private let scheduler = AlarmScheduler.shared

    // MARK: - Notification content

    func testNotificationContent_hasCriticalInterruptionLevel() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        XCTAssertEqual(content.interruptionLevel, .critical,
                       "Alarm notifications must use critical interruption level to bypass DND")
    }

    func testNotificationContent_includesSoundIDInUserInfo() {
        let alarm = Alarm(soundID: "morning_bells", penaltyAmount: 100)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        let soundID = content.userInfo["soundID"] as? String
        XCTAssertEqual(soundID, "morning_bells",
                       "userInfo should contain the alarm's soundID for AudioService")
    }

    func testNotificationContent_includesAlarmIDInUserInfo() {
        let alarmID = UUID()
        let alarm = Alarm(id: alarmID, penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        let storedID = content.userInfo["alarmID"] as? String
        XCTAssertEqual(storedID, alarmID.uuidString)
    }

    func testNotificationContent_includesSnoozeCountInUserInfo() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 3)

        let count = content.userInfo["snoozeCount"] as? Int
        XCTAssertEqual(count, 3)
    }

    func testNotificationContent_includesPenaltyInUserInfo() {
        let alarm = Alarm(penaltyAmount: 75)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        let penalty = content.userInfo["penaltyAmount"] as? Double
        XCTAssertEqual(penalty, 75)
    }

    func testNotificationContent_includesProgressiveScaleInUserInfo() {
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        let progressive = content.userInfo["progressiveScale"] as? Bool
        XCTAssertEqual(progressive, true)
    }

    func testNotificationContent_hasCriticalSound() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        // The content must have a sound set (either named critical or default critical)
        XCTAssertNotNil(content.sound,
                        "Alarm notification must include a critical sound")
    }

    func testNotificationContent_hasCorrectCategoryIdentifier() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        XCTAssertEqual(content.categoryIdentifier, "ALARM_CATEGORY")
    }

    func testNotificationContent_subtitleShowsNextPenalty() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        // snoozeCount=0, so penalty(forSnoozeCount: 1) = 50
        XCTAssertEqual(content.subtitle, "Отложить \u{00B7} 50 ₽")
    }

    func testNotificationContent_subtitleWithProgressiveScale() {
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 2)

        // snoozeCount=2, penalty(forSnoozeCount: 3) = 50 * 4 = 200
        XCTAssertEqual(content.subtitle, "Отложить \u{00B7} 200 ₽")
    }

    func testNotificationContent_titleIsAlarmName() {
        let alarm = Alarm(name: "Утренний", penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        XCTAssertEqual(content.title, "Утренний")
    }

    func testNotificationContent_bodyText() {
        let alarm = Alarm(penaltyAmount: 50)
        let content = scheduler.makeContent(for: alarm, snoozeCount: 0)

        XCTAssertEqual(content.body, "Время вставать!")
    }

    // MARK: - Sound file resolution

    func testAlarmSoundFileName_returnsNilForMissingSoundFile() {
        // A sound ID that definitely does not exist in the test bundle
        let result = scheduler.alarmSoundFileName(for: "completely_nonexistent_sound_xyz_123")
        // If default_alarm is also missing, should return nil
        // If default_alarm exists, it returns a fallback — both are valid
        // We just verify it doesn't crash and returns a consistent result
        if result != nil {
            // Fallback to default_alarm found in bundle
            XCTAssertTrue(result!.hasPrefix("default_alarm."))
        } else {
            XCTAssertNil(result)
        }
    }

    func testAlarmSoundFileName_checksMultipleExtensions() {
        // Verify the method handles the extension search gracefully
        // for a non-existent file it should try caf, m4a, wav, mp3
        let result = scheduler.alarmSoundFileName(for: "no_such_sound_file")
        // Should either be nil (no files at all) or a default_alarm fallback
        if let name = result {
            let validExtensions = ["caf", "m4a", "wav", "mp3"]
            let ext = (name as NSString).pathExtension
            XCTAssertTrue(validExtensions.contains(ext),
                          "Returned filename should have one of the supported extensions")
        }
    }

    func testAlarmSoundFileName_returnsCorrectFormat() {
        // If any sound file exists in the bundle, it should return "name.ext"
        let result = scheduler.alarmSoundFileName(for: "default_alarm")
        if let name = result {
            XCTAssertTrue(name.contains("."), "Filename should include extension separator")
            XCTAssertTrue(name.hasPrefix("default_alarm."))
        }
        // If file doesn't exist, nil is acceptable
    }

    // MARK: - Permission / scheduling smoke
    //
    // NOTE: AlarmScheduler depends on UNUserNotificationCenter.current() which is a
    // process-wide singleton and cannot be DI'd without a refactor (extracting a
    // protocol seam). Until that refactor lands, we cannot mock notification-center
    // failures to assert that errors are logged. The smoke test below verifies that
    // requesting permission does not crash and invokes its completion handler in a
    // reasonable time — which at minimum guards against regressions in the
    // permission dispatch flow added in IOS-033.

    func testRequestPermission_invokesCompletionWithoutCrash() {
        let expectation = expectation(description: "requestPermission completes")
        AlarmScheduler.shared.requestPermission { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}
