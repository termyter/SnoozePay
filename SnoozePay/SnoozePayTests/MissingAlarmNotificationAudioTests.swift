import UIKit
import UserNotifications
import XCTest
@testable import SnoozePay

/// A notification for an alarm missing from the repository must leave another
/// alarm's ringing screen alone (#854).
///
/// `startForegroundAlarm` used to start the sound before resolving the alarm,
/// which moved `AudioService` ownership to the missing alarm, and the "alarm
/// not found" branch then called `stopAlarmSound()` unconditionally. Screen A
/// went silent with no dismiss, and since #851 it ignores the `.stopped` note,
/// which names the other alarm, so its banner kept claiming the last state.
///
/// Driven through the same seams the delegate callbacks use:
/// `foregroundPresentationOptions(for:startAlarm:)` for `willPresent` and
/// `handleDefaultTap(on:presentAlarm:stopAlarmSound:)` for a default tap.
@MainActor
final class MissingAlarmNotificationAudioTests: XCTestCase {

    /// A sound id with no file behind it, so `AudioService` falls back to the
    /// synthetic tone, as the presenter tests do: the bundle's files are not
    /// what this pins.
    private static let toneSoundID = "nonexistent_test_sound"

    override func setUp() {
        super.setUp()
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        super.tearDown()
    }

    func testWillPresent_forAMissingAlarm_leavesAnotherAlarmsRingingScreenRinging() throws {
        let appDelegate = try appDelegate()
        let ringingAlarm = Alarm(soundID: Self.toneSoundID)
        var screen: AlarmFiringViewController? = makeRingingScreen(for: ringingAlarm)
        // A loaded firing screen must not outlive the test (the #846 lesson):
        // `viewDidDisappear` stops its sound and ticker, dropping the reference
        // lets `deinit` remove its observers, and the stop resets the service.
        defer {
            screen?.viewDidDisappear(false)
            screen = nil
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }
        let banner = try XCTUnwrap(screen?.audioWarningBanner)
        assertRinging(ringingAlarm, banner: banner, "test precondition")

        let missingID = UUID()
        XCTAssertNil(
            try AlarmRepository.shared.fetchChecked(id: missingID),
            "test precondition: the notification's alarm must be missing from the repository"
        )
        let options = AppDelegate.foregroundPresentationOptions(for: request(forAlarm: missingID)) {
            appDelegate.startForegroundAlarm($0)
        }
        drainMainQueue()

        XCTAssertEqual(options, [], "an alarm notification is never shown as a system banner in the foreground")
        assertRinging(ringingAlarm, banner: banner, "after the missing alarm's willPresent")
    }

    func testDefaultTap_onAMissingAlarm_leavesAnotherAlarmsRingingScreenRinging() throws {
        let appDelegate = try appDelegate()
        let ringingAlarm = Alarm(soundID: Self.toneSoundID)
        var screen: AlarmFiringViewController? = makeRingingScreen(for: ringingAlarm)
        defer {
            screen?.viewDidDisappear(false)
            screen = nil
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }
        let banner = try XCTUnwrap(screen?.audioWarningBanner)
        assertRinging(ringingAlarm, banner: banner, "test precondition")

        AppDelegate.handleDefaultTap(
            on: request(forAlarm: UUID()),
            presentAlarm: { appDelegate.presentAlarmFiringScreen(for: $0) },
            stopAlarmSound: { XCTFail("a decodable alarm payload took the invalid-payload branch") }
        )
        drainMainQueue()

        assertRinging(ringingAlarm, banner: banner, "after a tap on the missing alarm's notification")
    }

    /// The stop the miss used to make unconditionally is kept for the one case
    /// it was for: sound the missing alarm itself owns has no screen coming
    /// that could ever stop it.
    func testDefaultTap_onAMissingAlarm_stillStopsTheSoundThatAlarmOwns() throws {
        let appDelegate = try appDelegate()
        let missingID = UUID()
        AudioService.shared.startAlarmSound(soundID: Self.toneSoundID, alarmID: missingID)
        XCTAssertTrue(AudioService.shared.isPlaying, "test precondition: the missing alarm's sound has to be audible")
        XCTAssertEqual(AudioService.shared.currentAlarmID, missingID, "test precondition")

        AppDelegate.handleDefaultTap(
            on: request(forAlarm: missingID),
            presentAlarm: { appDelegate.presentAlarmFiringScreen(for: $0) },
            stopAlarmSound: { XCTFail("a decodable alarm payload took the invalid-payload branch") }
        )
        drainMainQueue()

        XCTAssertFalse(AudioService.shared.isPlaying, "the missing alarm's own sound kept ringing with no screen")
        XCTAssertNil(AudioService.shared.currentAlarmID)
    }

    // MARK: - Helpers

    private func appDelegate() throws -> AppDelegate {
        try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate, "the test host runs the app's delegate")
    }

    /// A firing screen on the notification path: `viewDidLoad` starts
    /// `AudioService` under this alarm's id, as a real screen A does.
    private func makeRingingScreen(for alarm: Alarm) -> AlarmFiringViewController {
        let viewModel = AlarmFiringViewModel(
            alarm: alarm,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        )
        let screen = AlarmFiringViewController(viewModel: viewModel)
        XCTAssertFalse(viewModel.usesAlarmKit, "test precondition: the screen must own the sound")
        screen.loadViewIfNeeded()
        drainMainQueue()
        return screen
    }

    private func request(forAlarm alarmID: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = AlarmNotificationPayload(
            alarmID: alarmID,
            penaltyAmount: 50,
            progressiveScale: false,
            snoozeCount: 0,
            snoozeMinutes: 5,
            soundID: Self.toneSoundID
        ).asUserInfo()
        return UNNotificationRequest(identifier: alarmID.uuidString, content: content, trigger: nil)
    }

    /// Screen A's claim is truthful: the service still plays under A's id, and
    /// the banner says what that state says (hidden while playing).
    private func assertRinging(
        _ alarm: Alarm,
        banner: UILabel,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            AudioService.shared.currentAlarmID, alarm.id,
            "\(context): the ringing screen lost its sound to another alarm",
            file: file, line: line
        )
        XCTAssertEqual(
            AudioService.shared.state, .playing,
            "\(context): the ringing screen's alarm is not playing",
            file: file, line: line
        )
        XCTAssertTrue(
            banner.isHidden,
            "\(context): the banner claims \(banner.accessibilityLabel ?? "nil") while the sound plays",
            file: file, line: line
        )
    }
}
