import os
import XCTest
@testable import SnoozePay

/// Pins the edge from `startAlarmSound` to `resolveAlarmPlayer` (#774).
///
/// The #765 diagnostics are covered in `AudioServiceTests`, but every case
/// there calls `resolveAlarmPlayer` itself. That leaves the call inside
/// `startAlarmSoundLocked` unheld: replacing it with `Self.generateAlarmTone()`
/// keeps the alarm audible, so the state assertions elsewhere stay green, while
/// the missing-sound line stops being emitted on the path a real firing alarm
/// takes — the one path where anyone would go looking for it.
///
/// Reading the line from here needs no waiting: `startAlarmSound` hops through
/// `queue.sync`, which returns only once the body has run, and `withTestSink`
/// keeps its sink installed for the whole synchronous call.
///
/// Its own file rather than another case in `AudioServiceTests`, which is
/// already past 900 lines.
final class AudioServiceStartWiringTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    /// `AudioService.shared` is shared with the rest of the suite and
    /// `startAlarmSoundLocked` returns early unless the state is `.stopped`, so
    /// the call is bracketed by `stopAlarmSound()` — which resets the state
    /// from any branch — on both sides.
    func testStartAlarmSound_withASoundTheBundleLacks_leavesTheDowngradeTrace() {
        let service = AudioService.shared
        service.stopAlarmSound()
        defer { service.stopAlarmSound() }

        var lines: [LoggedLine] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            service.startAlarmSound(soundID: "vanished_sound", alarmID: UUID(), volume: 1, fadeIn: false)
        })

        // Asserted first because the audio-session branch returns before the
        // lookup: without it, a red count below would not say whether the
        // wiring went missing or the session refused to activate.
        XCTAssertNotEqual(
            service.state, .silentBecauseConfigFailed,
            "the audio session did not activate, so this run never reached the sound lookup at all"
        )

        let traces = lines.filter { $0.message.contains(AudioService.missingSoundErrorID) }
        XCTAssertEqual(
            traces.count, 1,
            """
            a firing alarm whose chosen sound the bundle no longer has must leave the #765 \
            downgrade trace, and on this path only startAlarmSoundLocked's call to \
            resolveAlarmPlayer can produce it. The sink saw \(lines.map(\.message)).
            """
        )
        XCTAssertTrue(
            traces.first?.message.contains("vanished_sound") == true,
            "the trace must name the soundID the caller asked for, not one fixed inside the "
            + "lookup; it reads «\(traces.first?.message ?? "")»"
        )
    }

    // MARK: - Which player ends up playing (#806)
    //
    // The trace above proves `resolveAlarmPlayer` ran, not that its player is
    // the one kept: `_ = resolveAlarmPlayer(...)` followed by
    // `Self.generateAlarmTone()` still logs the line and still reaches
    // `.playing`. The file name of the owned player is what tells them apart —
    // the tone is built from data, so its URL is nil.

    func testStartAlarmSound_withASoundTheBundleLacks_playsTheBundledFallbackFile() {
        XCTAssertEqual(
            playingFileName(afterStarting: "vanished_sound"), "default_alarm.caf",
            "a missing sound must ring the bundled fallback file, not the synthetic tone "
            + "and not some other sound"
        )
    }

    func testStartAlarmSound_withABundledSound_playsThatFile() throws {
        _ = try XCTUnwrap(
            Bundle.main.url(forResource: "radar", withExtension: "caf"),
            "precondition: the app bundle ships radar.caf"
        )
        XCTAssertEqual(
            playingFileName(afterStarting: "radar"), "radar.caf",
            "the player kept must be the one resolved for the soundID the caller asked for"
        )
    }

    /// Starts `soundID` on the shared service, bracketed by `stopAlarmSound()`
    /// like the case above, and returns the file name of the player it kept.
    /// `.playing` is asserted first: on every other outcome this call ends
    /// without a player of its own, and a nil name would then say nothing
    /// about which player was chosen.
    private func playingFileName(
        afterStarting soundID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String? {
        let service = AudioService.shared
        service.stopAlarmSound()
        defer { service.stopAlarmSound() }

        service.startAlarmSound(soundID: soundID, alarmID: UUID(), volume: 1, fadeIn: false)
        XCTAssertEqual(
            service.state, .playing,
            "start did not reach .playing, so no player is owned to inspect",
            file: file, line: line
        )
        return service.currentPlayerURL?.lastPathComponent
    }
}
