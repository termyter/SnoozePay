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
/// `handleDefaultTap(on:presentAlarm:stopAlarmSound:)` for a default tap. Each
/// test builds its own `AppDelegate` over a repository on its own defaults
/// suite, so saving an alarm never writes `.standard` (#814).
@MainActor
final class MissingAlarmNotificationAudioTests: XCTestCase {

    /// A sound id with no file behind it, so `AudioService` falls back to the
    /// synthetic tone, as the presenter tests do: the bundle's files are not
    /// what this pins.
    private static let toneSoundID = "nonexistent_test_sound"

    /// `repository.save` must never reach AlarmKit or the notification center.
    private final class NoopScheduler: AlarmScheduling {
        func schedule(
            _ alarm: Alarm,
            completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?
        ) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }

    /// A host that accepts the firing screen the way UIKit does for the
    /// presenter's read-back: by wiring the screen's `presentingViewController`.
    private final class RecordingHost: UIViewController {
        private(set) var presentedScreens: [UIViewController] = []

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            (screen as? ReadBackFiringScreen)?.wiredPresenter = self
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repository: AlarmRepository!
    private var delegate: AppDelegate!

    override func setUp() {
        super.setUp()
        suiteName = "test.missingAlarmAudio.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        repository = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
        delegate = AppDelegate()
        delegate.alarmRepository = repository
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        delegate = nil
        repository = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testWillPresent_forAMissingAlarm_leavesAnotherAlarmsRingingScreenRinging() throws {
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
        try assertAbsentFromRepository(missingID)
        let options = AppDelegate.foregroundPresentationOptions(for: request(forAlarm: missingID)) {
            self.delegate.startForegroundAlarm($0)
        }
        drainMainQueue()

        XCTAssertEqual(options, [], "an alarm notification is never shown as a system banner in the foreground")
        assertRinging(ringingAlarm, banner: banner, "after the missing alarm's willPresent")
    }

    func testDefaultTap_onAMissingAlarm_leavesAnotherAlarmsRingingScreenRinging() throws {
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

        let missingID = UUID()
        try assertAbsentFromRepository(missingID)
        AppDelegate.handleDefaultTap(
            on: request(forAlarm: missingID),
            presentAlarm: { self.delegate.presentAlarmFiringScreen(for: $0) },
            stopAlarmSound: { XCTFail("a decodable alarm payload took the invalid-payload branch") }
        )
        drainMainQueue()

        assertRinging(ringingAlarm, banner: banner, "after a tap on the missing alarm's notification")
    }

    /// The stop the miss used to make unconditionally is kept for the one case
    /// it was for: sound the missing alarm itself owns has no screen coming
    /// that could ever stop it.
    func testDefaultTap_onAMissingAlarm_stillStopsTheSoundThatAlarmOwns() throws {
        let missingID = UUID()
        try assertAbsentFromRepository(missingID)
        AudioService.shared.startAlarmSound(soundID: Self.toneSoundID, alarmID: missingID)
        XCTAssertTrue(AudioService.shared.isPlaying, "test precondition: the missing alarm's sound has to be audible")
        XCTAssertEqual(AudioService.shared.currentAlarmID, missingID, "test precondition")

        AppDelegate.handleDefaultTap(
            on: request(forAlarm: missingID),
            presentAlarm: { self.delegate.presentAlarmFiringScreen(for: $0) },
            stopAlarmSound: { XCTFail("a decodable alarm payload took the invalid-payload branch") }
        )
        drainMainQueue()

        XCTAssertFalse(AudioService.shared.isPlaying, "the missing alarm's own sound kept ringing with no screen")
        XCTAssertNil(AudioService.shared.currentAlarmID)
    }

    /// Every foreground alarm now resolves before its sound starts. A resolve
    /// that failed for a real alarm would silence every alarm the app rings
    /// in the foreground, and the three tests above would stay green.
    func testWillPresent_forAnAlarmInTheRepository_ringsIt_andAsksForItsScreen() throws {
        let alarm = Alarm(soundID: Self.toneSoundID, enabled: false)
        XCTAssertTrue(repository.save(alarm), "test precondition: the alarm has to be in the repository")
        XCTAssertEqual(try repository.fetchChecked(id: alarm.id)?.id, alarm.id, "test precondition")

        let presenter = AlarmFiringPresenter.shared
        let recording = installRecordingHost()
        let host: RecordingHost? = recording.host
        defer {
            recording.restore()
            repository.delete(id: alarm.id)
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }

        let options = AppDelegate.foregroundPresentationOptions(for: request(forAlarm: alarm.id)) {
            self.delegate.startForegroundAlarm($0)
        }
        // The present hops to main.
        drainMainQueue()

        XCTAssertEqual(options, [])
        XCTAssertEqual(AudioService.shared.currentAlarmID, alarm.id, "the found alarm did not take the sound")
        XCTAssertEqual(AudioService.shared.state, .playing, "the found alarm is not ringing")
        let presented = host?.presentedScreens.compactMap { $0 as? AlarmFiringViewController } ?? []
        XCTAssertEqual(
            presented.map(\.viewModel.alarm.id), [alarm.id],
            "the host was not asked for exactly one firing screen of the found alarm"
        )
        XCTAssertNotEqual(
            presenter.pendingPresentation?.alarmID, alarm.id,
            "the screen read back as up, yet the alarm is still parked for a retry"
        )
    }

    /// A real alarm fires in the foreground while the stored alarms fail to
    /// decode. The app cannot ring it, so the system has to: `[]` used to
    /// suppress the system sound as well, and the only trace of the alarm was
    /// the data-corrupted alert (#860).
    func testWillPresent_whenStoredAlarmsFailToDecode_letsTheSystemPlayTheSound() throws {
        defaults.set(Data("{ not a list of alarms".utf8), forKey: "stored_alarms")
        let alarmID = UUID()
        XCTAssertThrowsError(
            try repository.fetchChecked(id: alarmID),
            "test precondition: the stored alarms have to fail to decode"
        )
        // The alert would mount on the test host's window; record it instead.
        var reported: [Error] = []
        delegate.reportAlarmDataCorrupted = { reported.append($0) }
        // Nothing loads a screen on this path; stop and drain anyway, so a
        // regression that starts the sound cannot leak it into the next test
        // (#846). The suite goes in `tearDown`.
        defer {
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }

        var start: AppDelegate.ForegroundAlarmStart?
        let options = AppDelegate.foregroundPresentationOptions(for: request(forAlarm: alarmID)) {
            let outcome = self.delegate.startForegroundAlarm($0)
            start = outcome
            return outcome
        }
        drainMainQueue()

        XCTAssertEqual(start, .loadFailed)
        XCTAssertTrue(options.contains(.sound), "the system sound is suppressed, so the alarm rings nowhere")
        XCTAssertEqual(options, [.banner, .sound, .list])
        XCTAssertEqual(reported.count, 1, "the user must still be told the alarm data is corrupted")
        XCTAssertNotEqual(
            AudioService.shared.currentAlarmID, alarmID,
            "the app started its own sound for an alarm it could not load"
        )
    }

    /// The alarm resolves, but the audio session refuses to activate (another
    /// app holds it, e.g. a call). The service goes `.silentBecauseConfigFailed`
    /// and skips vibration on purpose, yet `willPresent` used to report
    /// `.ringing` and return `[]`: no app sound, no vibration and no system
    /// sound (#864).
    func testWillPresent_whenTheAudioSessionFails_letsTheSystemPlayTheSound() throws {
        let alarm = Alarm(soundID: Self.toneSoundID, enabled: false)
        XCTAssertTrue(repository.save(alarm), "test precondition: the alarm has to be in the repository")
        // `NSError`, not a local `Error` struct: under the target's default
        // isolation a struct's initializer is main-actor, and the activator
        // runs on the audio queue.
        AudioService.shared.overrideSessionActivation {
            throw NSError(domain: "MissingAlarmNotificationAudioTests.sessionRefused", code: 1)
        }
        let recording = installRecordingHost()
        defer {
            recording.restore()
            AudioService.shared.overrideSessionActivation(nil)
            repository.delete(id: alarm.id)
            AudioService.shared.stopAlarmSound()
            drainMainQueue()
        }

        var start: AppDelegate.ForegroundAlarmStart?
        let options = AppDelegate.foregroundPresentationOptions(for: request(forAlarm: alarm.id)) {
            let outcome = self.delegate.startForegroundAlarm($0)
            start = outcome
            return outcome
        }
        drainMainQueue()

        XCTAssertEqual(AudioService.shared.state, .silentBecauseConfigFailed, "test precondition: the seam must fail")
        XCTAssertEqual(start, .silent)
        XCTAssertEqual(options, [.banner, .sound, .list], "the app rings nothing, so the system has to")
        XCTAssertEqual(
            recording.host.presentedScreens.count, 1,
            "the firing screen is still asked for: it carries the session-failed banner"
        )
    }

    /// SNOOZE_ACTION on an alarm whose stored alarms fail to decode used to
    /// come back `.alarmNotFound`: logged as a deleted alarm, and the user
    /// heard nothing. It now keeps the load failure, and the delegate puts up
    /// the data-corrupted alert the foreground path does (#864).
    func testSnoozeAction_whenStoredAlarmsFailToDecode_reportsTheCorruption() throws {
        defaults.set(Data("{ not a list of alarms".utf8), forKey: "stored_alarms")
        var reported: [Error] = []
        delegate.reportAlarmDataCorrupted = { reported.append($0) }
        let coordinator = AlarmFiringCoordinator(
            alarmRepository: repository,
            balanceService: BalanceService(defaults: defaults),
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        )

        var outcome: AlarmFiringCoordinator.SnoozeOutcome?
        coordinator.handleSnooze(userInfo: request(forAlarm: UUID()).content.userInfo) { outcome = $0 }
        guard case .alarmLoadFailed? = outcome else {
            return XCTFail("a load failure must not read as a deleted alarm; got \(String(describing: outcome))")
        }
        delegate.handleSnoozeOutcome(try XCTUnwrap(outcome))

        XCTAssertEqual(reported.count, 1, "the user must be told the alarm data is corrupted")
        guard case .decodeFailure? = reported.first as? AlarmRepository.RepositoryError else {
            return XCTFail("the alert must get the decode error, for its detail line; got \(reported)")
        }
    }

    // MARK: - Helpers

    /// Points the shared presenter at a `RecordingHost`. The shared presenter
    /// outlives the test, so call `restore` from a `defer`: it puts every seam
    /// back and takes down anything that went up, the way #846 does.
    private func installRecordingHost() -> (host: RecordingHost, restore: () -> Void) {
        let presenter = AlarmFiringPresenter.shared
        let originalLocateHost = presenter.locateHost
        let originalIsRootReady = presenter.isRootReady
        let originalMakeFiringScreen = presenter.makeFiringScreen
        let host = RecordingHost()
        presenter.locateHost = { [weak host] in
            guard let host else { return .failure(.noHostingWindow) }
            return .success(host)
        }
        presenter.isRootReady = { true }
        presenter.makeFiringScreen = { ReadBackFiringScreen(alarm: $0, snoozeCount: $1) }
        return (host, {
            presenter.locateHost = originalLocateHost
            presenter.isRootReady = originalIsRootReady
            presenter.makeFiringScreen = originalMakeFiringScreen
            for screen in host.presentedScreens where screen.isViewLoaded {
                screen.viewDidDisappear(false)
            }
        })
    }

    private func assertAbsentFromRepository(
        _ alarmID: UUID, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertNil(
            try repository.fetchChecked(id: alarmID),
            "test precondition: the notification's alarm must be missing from the repository",
            file: file, line: line
        )
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
