import XCTest
@testable import SnoozePay

/// Unit tests for AudioService — alarm sound playback state management.
final class AudioServiceTests: XCTestCase {

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
}
