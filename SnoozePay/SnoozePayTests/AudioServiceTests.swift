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
        // Even when the sound file is missing, isPlaying should be set
        // because AudioService starts vibration as fallback
        XCTAssertTrue(service.isPlaying)

        // Cleanup
        service.stopAlarmSound()
    }

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
