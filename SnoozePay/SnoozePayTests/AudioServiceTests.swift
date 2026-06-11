import XCTest
@testable import SnoozePay

/// Unit tests for AudioService — alarm sound playback state management.
final class AudioServiceTests: XCTestCase {

    // MARK: - Synthetic tone (#210)

    /// The in-memory WAV fallback must produce a ready AVAudioPlayer — if it
    /// ever returns nil the alarm fires vibration-only, which previously
    /// happened without a trace (`try?`). Now the failure path logs, and this
    /// test pins the happy path so the generated WAV header stays valid.
    func testGenerateAlarmTone_returnsPlayer() {
        XCTAssertNotNil(AudioService.generateAlarmTone(),
                        "Synthetic tone generation must succeed for valid in-memory WAV data")
    }

    // MARK: - Start

    func testStartAlarmSound_setsIsPlaying() {
        let service = AudioService.shared
        // Ensure clean state
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        service.startAlarmSound(soundID: "nonexistent_test_sound")
        // Missing bundle file → AudioService falls back to a synthetic tone
        // (generateAlarmTone). isPlaying must be true to reflect that real audio
        // is being produced, not just vibration.
        XCTAssertTrue(service.isPlaying)

        // Cleanup
        service.stopAlarmSound()
    }

    /// IOS-037 — silent failure regression guard.
    /// When the bundle does not contain the requested sound file, AudioService
    /// must fall back to the synthetic tone instead of silently going
    /// vibration-only with isPlaying = true.
    func testStartAlarmSound_withMissingFile_fallsBackToSynthetic() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        service.startAlarmSound(soundID: "definitely_not_a_real_sound_file_xyz")
        // Synthetic tone generation is deterministic and does not depend on
        // audio session state for unit-test correctness — isPlaying reflects
        // the in-memory player being created and started.
        XCTAssertTrue(
            service.isPlaying,
            "Missing bundle file should fall back to synthetic tone, not silent vibration"
        )

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    // NOTE: We cannot easily simulate AVAudioSession.setActive failure without
    // a DI refactor (AVAudioSession is a hard-coded singleton inside AudioService).
    // A follow-up could introduce a session-providing protocol so the
    // setActive-throws path can be exercised in unit tests.

    func testStartAlarmSound_whenAlreadyPlaying_doesNotRestart() {
        let service = AudioService.shared
        service.stopAlarmSound()

        // Start the first time
        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(service.isPlaying)

        // Calling start again should be a no-op (guard !isPlaying)
        // The fact that it doesn't crash and isPlaying remains true confirms the guard
        service.startAlarmSound(soundID: "another_nonexistent_sound")
        XCTAssertTrue(service.isPlaying)

        // Cleanup
        service.stopAlarmSound()
    }

    // MARK: - Stop

    func testStopAlarmSound_stopsPlaying() {
        let service = AudioService.shared
        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    func testStopAlarmSound_whenNotPlaying_doesNotCrash() {
        let service = AudioService.shared
        // Ensure we're in a stopped state
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        // Calling stop again should not crash
        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    // MARK: - Round-trip

    func testStartAndStopCycle_resetsState() {
        let service = AudioService.shared
        service.stopAlarmSound()

        service.startAlarmSound(soundID: "test")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)

        // Can restart after stopping
        service.startAlarmSound(soundID: "test")
        XCTAssertTrue(service.isPlaying)

        service.stopAlarmSound()
        XCTAssertFalse(service.isPlaying)
    }

    // MARK: - State + notifications (IOS-077)

    /// Successful start path must transition state through `.stopped → .playing`
    /// and broadcast the change via `stateChangedNotification`.
    func testStartAlarmSound_postsPlayingStateNotification() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)

        var observedStates: [AudioPlaybackState] = []
        let token = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: service,
            queue: nil
        ) { note in
            if let state = note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState {
                observedStates.append(state)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertEqual(service.state, .playing)
        XCTAssertTrue(observedStates.contains(.playing),
                      "Expected .playing state to be broadcast, got \(observedStates)")

        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertTrue(observedStates.contains(.stopped),
                      "Expected .stopped state to be broadcast, got \(observedStates)")
    }

    // MARK: - Ownership tracking (IOS-116)

    /// `currentAlarmID` must reflect the alarm that started the current session
    /// and clear back to nil after `stopAlarmSound()`.
    func testCurrentAlarmID_setOnStart_clearedOnStop() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertNil(service.currentAlarmID)

        let alarmID = UUID()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarmID)
        XCTAssertEqual(service.currentAlarmID, alarmID)

        service.stopAlarmSound()
        XCTAssertNil(service.currentAlarmID)
    }

    /// IOS-116 — alarm-stacking race regression guard.
    ///
    /// Sequence:
    ///   1. Alarm A starts → owns the audio session.
    ///   2. AppDelegate dismisses A's firing VC and presents B's; B's
    ///      `viewDidLoad` calls `startAlarmSound(alarmID: B)` while A's
    ///      `viewDidDisappear` has not yet fired.
    ///   3. A's `viewDidDisappear` finally runs and would normally call
    ///      `stopAlarmSound()` — but with the new ownership check, it sees
    ///      `currentAlarmID != A.id` and skips the stop, preserving B's audio.
    ///
    /// We can't simulate the VC lifecycle in a unit test directly, so we
    /// reproduce the *contract* the VC relies on: after a second start with a
    /// different ID, the previous owner has lost the session.
    func testStartAlarmSound_secondStartOverridesOwnership() {
        let service = AudioService.shared
        service.stopAlarmSound()

        let alarmA = UUID()
        let alarmB = UUID()

        service.startAlarmSound(soundID: "tone_a", alarmID: alarmA)
        XCTAssertEqual(service.currentAlarmID, alarmA)

        // Simulating B taking over — startAlarmSound is guarded by `state == .stopped`,
        // so the second call short-circuits, but it still must transfer ownership
        // so the dismissed-VC's stop check skips correctly.
        service.startAlarmSound(soundID: "tone_b", alarmID: alarmB)
        XCTAssertEqual(
            service.currentAlarmID,
            alarmB,
            "Second startAlarmSound must transfer ownership to the new alarm so " +
            "the previous VC's viewDidDisappear does not silence it (#116)"
        )

        // Now A's "viewDidDisappear" check would compare `currentAlarmID == alarmA`,
        // see false, and refuse to stop — emulate that and confirm audio still plays.
        if service.currentAlarmID == alarmA {
            service.stopAlarmSound()
        }
        XCTAssertTrue(
            service.isPlaying,
            "Audio for alarm B must keep playing when A's VC dismisses after the handoff"
        )

        service.stopAlarmSound()
    }

    /// Restarting while already playing must not re-emit `.playing` (didSet
    /// guards on equality). This protects observers from spurious banner flicker.
    func testStateNotification_notRepostedOnSameState() {
        let service = AudioService.shared
        service.stopAlarmSound()

        var emissionCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: service,
            queue: nil
        ) { _ in emissionCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        service.startAlarmSound(soundID: "x") // → .playing  (1)
        let afterFirstStart = emissionCount

        // Second call hits `guard state == .stopped` and returns early — no new
        // notification should fire.
        service.startAlarmSound(soundID: "y")
        XCTAssertEqual(emissionCount, afterFirstStart,
                       "Re-entrant start must not republish the same state")

        service.stopAlarmSound()
    }

    // MARK: - Thread safety (#202)

    /// `startAlarmSound` may be called from a UN-delegate background thread
    /// (AppDelegate's `willPresent` is not guaranteed main). The serial-queue
    /// hop must make the call fully synchronous and leave the service in a
    /// consistent state observable from the main thread.
    func testStartAlarmSound_fromBackgroundThread_reachesPlayingState() {
        let service = AudioService.shared
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)

        let alarmID = UUID()
        let started = expectation(description: "background start completed")
        DispatchQueue.global(qos: .userInitiated).async {
            service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarmID)
            started.fulfill()
        }
        wait(for: [started], timeout: 5)

        XCTAssertEqual(service.state, .playing,
                       "Background-thread start must land in .playing like a main-thread start")
        XCTAssertEqual(service.currentAlarmID, alarmID)

        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID)
    }

    /// TSan-style stress test: hammer start/stop/reads from many threads at
    /// once. Before the serial queue, `state` / `currentAlarmID` /
    /// `audioPlayer` / `vibrationTimer` were mutated without synchronization
    /// and could land in inconsistent combinations (e.g. `.playing` with a
    /// nil player). With the queue this must never crash and must end in a
    /// coherent state after the final stop.
    func testConcurrentStartStop_doesNotCorruptState() {
        let service = AudioService.shared
        service.stopAlarmSound()

        let iterations = 50
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            if index.isMultiple(of: 2) {
                service.startAlarmSound(soundID: "stress_sound", alarmID: UUID())
            } else {
                service.stopAlarmSound()
            }
            // Interleave reads — these raced with the writers before #202.
            _ = service.state
            _ = service.isPlaying
            _ = service.currentAlarmID
        }

        // Whatever interleaving happened, the snapshot must be one of the
        // legal states — and a final stop must always win.
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID)
        XCTAssertFalse(service.isPlaying)

        // Service must remain usable after the stress run.
        service.startAlarmSound(soundID: "nonexistent_test_sound")
        XCTAssertTrue(service.isPlaying)
        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
    }

    /// Pause/resume (#141) mutate the same queue-confined fields — calling
    /// them from a background thread while the main thread reads must keep
    /// state coherent (`.playing` is intentionally retained across pause).
    func testPauseResume_fromBackgroundThread_keepsStateCoherent() {
        let service = AudioService.shared
        service.stopAlarmSound()
        service.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: UUID())
        XCTAssertEqual(service.state, .playing)

        let cycled = expectation(description: "background pause/resume completed")
        DispatchQueue.global(qos: .userInitiated).async {
            service.pauseAlarmSound()
            service.resumeAlarmSound()
            cycled.fulfill()
        }
        wait(for: [cycled], timeout: 5)

        XCTAssertEqual(service.state, .playing,
                       "pause+resume must preserve .playing (session ownership intact)")

        service.stopAlarmSound()
        XCTAssertEqual(service.state, .stopped)
    }
}
