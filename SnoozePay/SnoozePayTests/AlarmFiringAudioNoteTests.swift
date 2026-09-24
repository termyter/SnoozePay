import UIKit
import XCTest
@testable import SnoozePay

/// The firing screen applies only the audio notes about its own alarm (#851).
///
/// `AudioService` posts state notes asynchronously on main (#848), so screen
/// A's `.stopped`, queued when A is dismissed, can land on screen B after B
/// has registered its observer. Applied blindly, it hides B's warning banner
/// while B's sound is failing. The notes are posted by hand here, so the
/// test pins the screen's filter alone; which id the service puts in a note
/// is pinned in `AudioServiceNotificationDeliveryTests`.
final class AlarmFiringAudioNoteTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    func testStateNote_forAnotherAlarm_leavesTheBannerAlone_andOneForThisAlarmApplies() throws {
        let alarm = Alarm(name: "Работа", snoozeMinutes: 5, penaltyAmount: 50)
        let otherAlarmID = UUID()
        var screen: AlarmFiringViewController? = makeScreen(for: alarm)
        // A loaded firing screen must not outlive the test (the #846 lesson):
        // `viewDidDisappear` stops its ticker, dropping the reference lets
        // `deinit` remove its observers, and the stop resets the service.
        defer {
            screen?.viewDidDisappear(false)
            screen = nil
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }
        let banner = try XCTUnwrap(screen?.audioWarningBanner)
        XCTAssertTrue(banner.isHidden, "test precondition: the banner starts hidden")

        post(.vibrationOnly, about: otherAlarmID)
        XCTAssertTrue(banner.isHidden, "a failure of another alarm's sound raised this screen's banner")

        post(.vibrationOnly, about: nil)
        XCTAssertTrue(banner.isHidden, "a note naming no alarm must be ignored (isAudioNoteAboutThisAlarm)")

        post(.vibrationOnly, about: alarm.id)
        XCTAssertFalse(banner.isHidden, "a failure of this alarm's own sound must raise the banner")
        XCTAssertEqual(banner.accessibilityLabel, Localized.text("firing.audio.vibration_only"))

        post(.stopped, about: otherAlarmID)
        XCTAssertFalse(
            banner.isHidden,
            "another screen's stop hid this screen's banner while this alarm's sound is still failing"
        )

        post(.stopped, about: alarm.id)
        XCTAssertTrue(banner.isHidden, "this alarm's own stop must clear the banner")
    }

    // MARK: - Helpers

    /// A firing screen on the AlarmKit path, so `viewDidLoad` does not start
    /// `AudioService`: the banner then moves only on the notes posted here.
    private func makeScreen(for alarm: Alarm) -> AlarmFiringViewController {
        let viewModel = AlarmFiringViewModel(
            alarm: alarm,
            balanceService: AudioNoteWallet(),
            scheduler: AlarmScheduler(
                notificationCenter: InertNotificationCenter(),
                alarmKit: TestAlarmKitBackend()
            )
        )
        let screen = AlarmFiringViewController(viewModel: viewModel)
        screen.loadViewIfNeeded()
        XCTAssertTrue(viewModel.usesAlarmKit, "test precondition: the screen must not own the sound")
        return screen
    }

    /// Post a state note the way `AudioService.postOnMain` shapes it, then let
    /// main run the screen's `queue: .main` observer.
    private func post(_ state: AudioPlaybackState, about alarmID: UUID?) {
        var userInfo: [AnyHashable: Any] = [AudioService.stateUserInfoKey: state]
        if let alarmID { userInfo[AudioService.alarmIDUserInfoKey] = alarmID }
        NotificationCenter.default.post(
            name: AudioService.stateChangedNotification,
            object: AudioService.shared,
            userInfo: userInfo
        )
        drainMainQueue()
    }
}

/// A funded wallet that is never charged: the test only reads the banner.
private final class AudioNoteWallet: AlarmFiringBalancing {
    var balance: Double { 1000 }
    func canAfford(_ amount: Double) -> Bool { true }
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? { nil }
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool { false }
}
