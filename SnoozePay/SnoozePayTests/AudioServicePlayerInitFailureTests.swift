import AVFoundation
import os
import XCTest
@testable import SnoozePay

/// Pins the `catch` branch of `resolveAlarmPlayer`: the lookup found a file,
/// `AVAudioPlayer` refused to open it (#775).
///
/// Its own file rather than another case in `AudioServiceTests`, which is
/// already past 900 lines.
final class AudioServicePlayerInitFailureTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    /// A file that exists under an audio extension but holds text, so the
    /// lookup succeeds and `AVAudioPlayer(contentsOf:)` throws.
    private var unplayableURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        unplayableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios775-not-audio-\(UUID().uuidString).caf")
        try Data("this is not audio".utf8).write(to: unplayableURL)
    }

    override func tearDownWithError() throws {
        if let unplayableURL {
            try? FileManager.default.removeItem(at: unplayableURL)
        }
        unplayableURL = nil
        try super.tearDownWithError()
    }

    func testResolveAlarmPlayer_fileThePlayerCannotOpen_logsAndFallsBackToTheTone() {
        let url: URL = unplayableURL
        var lines: [LoggedLine] = []
        let player = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            AudioService.shared.resolveAlarmPlayer(soundID: "radar") { name, ext in
                name == "radar" && ext == "caf" ? url : nil
            }
        })

        XCTAssertNotNil(player, "the synthetic tone is the last resort when the player cannot be built")
        // `generateAlarmTone` builds its player from in-memory data, so it has
        // no `url`; a player carrying one came from a file.
        XCTAssertNil(player?.url, "the unopenable file must not come back as the player")

        let traces = lines.filter { $0.message.contains(AudioService.playerInitFailedErrorID) }
        XCTAssertEqual(
            traces.count, 1,
            "a file the player rejected must leave exactly one trace; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(traces.first?.category, .audio, "a sound-resolution failure belongs to the Audio category")
        XCTAssertEqual(traces.first?.level, .error, "falling back to the tone is an error, not a notice")
        XCTAssertTrue(
            traces.first?.message.contains(url.lastPathComponent) == true,
            "the line must name the file that failed to open; it reads «\(traces.first?.message ?? "")»"
        )
        XCTAssertTrue(
            lines.allSatisfy {
                !$0.message.contains(AudioService.missingSoundErrorID)
                    && !$0.message.contains(AudioService.missingFallbackSoundErrorID)
            },
            "the requested sound was found, so neither lookup-failure ID applies; "
            + "the sink saw \(lines.map(\.message))"
        )
    }

    /// Checked as substrings, because support greps for these IDs: one that
    /// contains another would match both branches.
    func testPlayerInitFailedErrorID_doesNotOverlapTheLookupIDs() {
        let initFailed = AudioService.playerInitFailedErrorID
        for other in [AudioService.missingSoundErrorID, AudioService.missingFallbackSoundErrorID] {
            XCTAssertFalse(initFailed.contains(other), "\(initFailed) contains \(other)")
            XCTAssertFalse(other.contains(initFailed), "\(other) contains \(initFailed)")
        }
    }
}
