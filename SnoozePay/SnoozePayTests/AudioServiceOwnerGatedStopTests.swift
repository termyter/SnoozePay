import XCTest
@testable import SnoozePay

/// #878: `stopAlarmSound(ifOwnedBy:)` checks the owner and stops in one step.
///
/// The three owner-gated callers (`AppDelegate.stopAlarmSoundIfOwner`, the
/// presenter's miss, the AlarmKit router) used to read `currentAlarmID` and
/// then call `stopAlarmSound()`, taking the service's queue twice. A start for
/// another alarm landing between the two handed that alarm the sound, and the
/// stop silenced it. These tests pin the gate on the service itself; the
/// callers' own tests pin their log lines.
///
/// A's ring is the shared service started under A's id on the synthetic tone,
/// as `AlarmKitRouterAudioOwnerTests.ring` does. Nothing here touches
/// `UserDefaults` (#814). Setup and teardown stop the sound and drain main, so
/// no post queued here or earlier leaks across tests (#618, #846).
@MainActor
final class AudioServiceOwnerGatedStopTests: XCTestCase {

    /// A sound id with no file behind it, so the service plays the synthetic
    /// tone: the bundle's files are not what this pins.
    private static let toneSoundID = "nonexistent_test_sound"

    private var service: AudioService { AudioService.shared }

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

    /// The gate's whole point: a stop for B leaves A's sound alone.
    func testStopForAnotherAlarm_returnsFalseAndLeavesTheOwnerRinging() {
        let ownerID = UUID()
        let otherID = UUID()
        ring(ownerID)

        let result = service.stopAlarmSound(ifOwnedBy: otherID)

        XCTAssertFalse(result.stopped, "a stop for another alarm reported that it stopped the sound")
        XCTAssertEqual(result.owner, ownerID, "the result must name the alarm that owned the sound")
        XCTAssertEqual(service.currentAlarmID, ownerID, "the owner lost the sound to another alarm's stop")
        XCTAssertEqual(service.soundingAlarmID, ownerID, "the owner is no longer sounding")
        XCTAssertEqual(service.state, .playing)
    }

    /// The owner's own stop does everything `stopAlarmSound()` does.
    func testStopForTheOwner_returnsTrueAndStopsTheSound() {
        let ownerID = UUID()
        ring(ownerID)

        let result = service.stopAlarmSound(ifOwnedBy: ownerID)

        XCTAssertTrue(result.stopped, "the owner's stop reported that it left the sound alone")
        XCTAssertEqual(result.owner, ownerID)
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID, "the stop left an owner behind")
        XCTAssertNil(service.soundingAlarmID)
        XCTAssertFalse(service.isPaused)
    }

    /// Same `.stopped` note as `stopAlarmSound()`, naming the alarm that lost
    /// the sound (#851): the firing screen's banner relies on it.
    func testStopForTheOwner_postsTheStoppedNoteNamingIt() {
        let ownerID = UUID()
        ring(ownerID)
        drainMainQueue()

        var notes: [(state: AudioPlaybackState?, alarmID: UUID?)] = []
        let token = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification, object: service, queue: nil
        ) { note in
            notes.append((
                note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState,
                note.userInfo?[AudioService.alarmIDUserInfoKey] as? UUID
            ))
        }
        defer { NotificationCenter.default.removeObserver(token) }

        service.stopAlarmSound(ifOwnedBy: ownerID)
        drainMainQueue()

        XCTAssertEqual(notes.count, 1, "expected exactly one transition, got \(notes)")
        XCTAssertEqual(notes.first?.state, .stopped)
        XCTAssertEqual(notes.first?.alarmID, ownerID)
    }

    func testStopWithNoOwner_returnsFalseAndStaysStopped() {
        XCTAssertNil(service.currentAlarmID, "test precondition: nothing may own the sound")

        let result = service.stopAlarmSound(ifOwnedBy: UUID())

        XCTAssertFalse(result.stopped)
        XCTAssertNil(result.owner)
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID)
    }

    /// A sound started without an alarm id belongs to no alarm, so no alarm's
    /// gated stop may end it: only the unconditional `stopAlarmSound()` does.
    func testStopAgainstAnUnownedRing_leavesItPlaying() {
        service.startAlarmSound(soundID: Self.toneSoundID)
        XCTAssertEqual(service.state, .playing, "test precondition: the sound has to be audible")
        XCTAssertNil(service.currentAlarmID, "test precondition: the sound must have no owner")

        let result = service.stopAlarmSound(ifOwnedBy: UUID())

        XCTAssertFalse(result.stopped)
        XCTAssertNil(result.owner)
        XCTAssertEqual(service.state, .playing, "an alarm's gated stop ended a sound it did not own")
    }

    // MARK: - Helpers

    private func ring(_ alarmID: UUID, file: StaticString = #filePath, line: UInt = #line) {
        service.startAlarmSound(soundID: Self.toneSoundID, alarmID: alarmID)
        XCTAssertEqual(
            service.currentAlarmID, alarmID, "test precondition: the alarm has to own the sound",
            file: file, line: line
        )
        XCTAssertEqual(
            service.state, .playing, "test precondition: the alarm has to be audible",
            file: file, line: line
        )
    }
}
