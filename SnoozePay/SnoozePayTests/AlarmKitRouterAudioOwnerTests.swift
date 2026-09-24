import os
import XCTest
@testable import SnoozePay

/// #869: the AlarmKit Stop and Snooze buttons stop the in-app audio only for
/// the alarm that owns it, as `AppDelegate.stopAlarmSoundIfOwner` and the
/// presenter's miss already do (#854, #859).
///
/// Both handlers used to call `stopAlarmSound()` unconditionally. A Stop or
/// Snooze on the system alert of a stale or deleted alarm B silenced the ring
/// of alarm A.
///
/// Each test builds its own router over a repository on its own defaults
/// suite, so nothing here writes `.standard` (#814) or swaps a seam on the
/// shared router. `present` is recorded and never reaches the real presenter.
/// A's ring is the service started under A's id on the synthetic tone, as
/// `AlarmFiringPresenterMissTests.ring` does, and `tearDown` stops it.
@MainActor
final class AlarmKitRouterAudioOwnerTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    /// A sound id with no file behind it, so the service plays the synthetic
    /// tone: the bundle's files are not what this pins.
    private static let toneSoundID = "nonexistent_test_sound"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var router: AlarmKitActionRouter!
    private var poster: LocalNotificationPosterSpy!
    private var presented: [UUID] = []
    private var lines: [Line] = []

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmKitRouterAudioOwner.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        poster = LocalNotificationPosterSpy()
        router = AlarmKitActionRouter()
        router.alarmRepository = AlarmRepository(
            defaults: defaults,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        )
        router.notificationPoster = poster
        router.present = { [weak self] in self?.presented.append($0) }
        // Start from silence, with anything an earlier test queued already run (#618).
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        router = nil
        poster = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        presented = []
        lines = []
        super.tearDown()
    }

    // MARK: - Stop

    /// The issue's scenario: A rings in-app, the system alert of B is stopped.
    func testStopForAnotherAlarm_leavesTheOwnersSoundRinging() {
        let ringingID = UUID()
        let otherID = UUID()
        ring(ringingID)

        recording { router.handleStop(alarmIDString: otherID.uuidString) }
        drainMainQueue()

        assertStillRinging(ringingID, "after a Stop for another alarm")
        XCTAssertEqual(presented, [otherID], "the Stop must still open the firing screen for its own alarm")
        XCTAssertEqual(decisionLines("AlarmKit stop"), [
            "AlarmKit stop: audio owner \(handle(ringingID)), alarm \(handle(otherID))"
                + " — leaving the audio of \(handle(ringingID)) alone"
        ])
    }

    /// The stop is kept for the case it was for: the alarm's own sound.
    func testStopForTheOwner_stopsItsSound() {
        let alarmID = UUID()
        ring(alarmID)

        recording { router.handleStop(alarmIDString: alarmID.uuidString) }

        XCTAssertNil(AudioService.shared.soundingAlarmID, "the Stop left its own alarm's sound ringing")
        XCTAssertNil(AudioService.shared.currentAlarmID)
        XCTAssertEqual(presented, [alarmID])
        XCTAssertEqual(decisionLines("AlarmKit stop"), [
            "AlarmKit stop: audio owner \(handle(alarmID)), alarm \(handle(alarmID)) — stopping the audio it owns"
        ])
    }

    /// No in-app sound at all, the usual AlarmKit case since #472: nothing to
    /// stop, and the screen still goes up.
    func testStopWhenNobodyOwnsTheSound_stillPresents() {
        let alarmID = UUID()
        XCTAssertNil(AudioService.shared.currentAlarmID, "test precondition: nobody may own the sound")

        recording { router.handleStop(alarmIDString: alarmID.uuidString) }

        XCTAssertNil(AudioService.shared.soundingAlarmID)
        XCTAssertEqual(presented, [alarmID], "the Stop must open the firing screen with no sound playing")
        XCTAssertEqual(decisionLines("AlarmKit stop"), [
            "AlarmKit stop: audio owner nobody, alarm \(handle(alarmID)) — leaving the audio of nobody alone"
        ])
    }

    // MARK: - Snooze

    func testSnoozeForAnotherAlarm_leavesTheOwnersSoundRinging() {
        let ringingID = UUID()
        let otherID = UUID()
        ring(ringingID)

        snooze(otherID)
        drainMainQueue()

        assertStillRinging(ringingID, "after a Snooze for another alarm")
        XCTAssertEqual(presented, [otherID], "the Snooze must still open the firing screen for its own alarm")
        XCTAssertEqual(decisionLines("AlarmKit snooze"), [
            "AlarmKit snooze: audio owner \(handle(ringingID)), alarm \(handle(otherID))"
                + " — leaving the audio of \(handle(ringingID)) alone"
        ])
        XCTAssertTrue(poster.requests.isEmpty, "a missing alarm is not a lost snooze; posted \(poster.requests)")
    }

    func testSnoozeForTheOwner_stopsItsSound() {
        let alarmID = UUID()
        ring(alarmID)

        snooze(alarmID)

        XCTAssertNil(AudioService.shared.soundingAlarmID, "the Snooze left its own alarm's sound ringing")
        XCTAssertNil(AudioService.shared.currentAlarmID)
        XCTAssertEqual(presented, [alarmID])
        XCTAssertEqual(decisionLines("AlarmKit snooze"), [
            "AlarmKit snooze: audio owner \(handle(alarmID)), alarm \(handle(alarmID)) — stopping the audio it owns"
        ])
    }

    // MARK: - Helpers

    private func ring(_ alarmID: UUID) {
        AudioService.shared.startAlarmSound(soundID: Self.toneSoundID, alarmID: alarmID)
        XCTAssertEqual(AudioService.shared.currentAlarmID, alarmID, "test precondition: the alarm has to own the sound")
        XCTAssertEqual(AudioService.shared.state, .playing, "test precondition: the alarm has to be audible")
    }

    private func assertStillRinging(
        _ alarmID: UUID, _ context: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            AudioService.shared.currentAlarmID, alarmID,
            "\(context): the ringing alarm lost its sound", file: file, line: line
        )
        XCTAssertEqual(
            AudioService.shared.state, .playing,
            "\(context): the ringing alarm is not playing", file: file, line: line
        )
    }

    /// The gate's lines for one action, on the scheduler category at the
    /// `.notice` level (`.default` in `OSLogType`).
    private func decisionLines(_ action: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let matching = lines.filter { $0.message.hasPrefix("\(action): ") }
        for entry in matching {
            XCTAssertEqual(entry.category, .scheduler, "«\(entry.message)»", file: file, line: line)
            XCTAssertEqual(entry.level, .default, "«\(entry.message)»", file: file, line: line)
        }
        return matching.map(\.message)
    }

    private func recording(_ body: () -> Void) {
        AppLogger.withTestSink({ [weak self] in self?.lines.append(($0, $1, $2)) }, perform: body)
    }

    /// `handleSnooze` is `async` and `withTestSink` takes a synchronous body,
    /// so the body starts it in a task and waits for it with the sink still
    /// installed, as `AlarmKitSnoozeLoadFailureTests.snooze` does.
    private func snooze(_ alarmID: UUID) {
        let router: AlarmKitActionRouter = self.router
        let returned = expectation(description: "handleSnooze returned")
        recording {
            Task { @MainActor in
                await router.handleSnooze(alarmIDString: alarmID.uuidString)
                returned.fulfill()
            }
            wait(for: [returned], timeout: 5)
        }
    }

    private func handle(_ alarmID: UUID) -> String { String(alarmID.uuidString.prefix(8)) }
}
