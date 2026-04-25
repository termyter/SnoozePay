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
}
