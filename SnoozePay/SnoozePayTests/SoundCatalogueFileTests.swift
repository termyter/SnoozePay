import AVFoundation
import os
import XCTest
@testable import SnoozePay

/// Pins the bundle side of the sound catalogue (#850): every id in
/// `SoundCatalogue.ids` has a file of its own, and the picker preview, the
/// in-app ring (`AudioService.resolveAlarmPlayer`) and the AlarmKit sound
/// (`AlarmScheduler.alarmSoundFileName`) all land on that same file rather
/// than on `default_alarm`.
///
/// Reads the real bundle on purpose: the test host IS the app (`TEST_HOST`),
/// so a `.caf` that never reached the target turns this suite red. Nothing here
/// plays audio — the preview's playback is `CreateAlarmViewModelSoundTests`'.
final class SoundCatalogueFileTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    /// Length of each bundled file in seconds, from `afinfo` on the files as
    /// committed. Written out rather than read back through
    /// `SoundCatalogue.fileDuration(for:)`, so a wrong reader cannot agree with
    /// itself. It is also how long the picker's preview rail now runs.
    private static let durationsBySoundID: [String: TimeInterval] = [
        "dawn": 10.81, "radar": 2.00, "drops": 2.14, "piano": 2.14, "guitar": 5.09,
        "bell": 48.13, "waves": 2.55, "birds": 2.22, "classic": 9.87, "jazz": 23.34,
        "hawk": 2.67, "morning": 4.11, "sirena": 17.99, "spaceship": 25.76
    ]

    func testEveryCatalogueSoundResolvesToItsOwnBundledFile() throws {
        for soundID in SoundCatalogue.ids {
            let url = try XCTUnwrap(
                SoundCatalogue.fileURL(for: soundID),
                "'\(soundID)' has no file in the app bundle — the row would preview nothing"
            )
            XCTAssertEqual(url.lastPathComponent, "\(soundID).caf")
        }
    }

    /// The ring's two lookups pick the preview's file, and none of them falls
    /// back: the sink would see `ALARM-749-SOUND-MISSING` or
    /// `AUDIO-765-SOUND-MISSING` if one did.
    func testRingAndAlarmKitPickTheFileThePreviewPlays() {
        var lines: [LoggedLine] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            for soundID in SoundCatalogue.ids {
                let previewURL = SoundCatalogue.fileURL(for: soundID)
                XCTAssertEqual(
                    AlarmScheduler.shared.alarmSoundFileName(for: soundID), "\(soundID).caf",
                    "AlarmKit would ring something other than '\(soundID)'"
                )
                XCTAssertEqual(
                    AudioService.shared.resolveAlarmPlayer(soundID: soundID)?.url, previewURL,
                    "the in-app ring and the preview disagree about '\(soundID)'"
                )
            }
        })
        XCTAssertTrue(lines.isEmpty, "a catalogue sound fell back: \(lines.map(\.message))")
    }

    func testPreviewDurationIsTheLengthOfTheFile() throws {
        XCTAssertEqual(Set(Self.durationsBySoundID.keys), Set(SoundCatalogue.ids))
        for (soundID, expected) in Self.durationsBySoundID {
            let duration = try XCTUnwrap(SoundCatalogue.fileDuration(for: soundID), soundID)
            XCTAssertEqual(duration, expected, accuracy: 0.01, "'\(soundID)' length")
        }
    }

    /// `birds` kept its id when the PM's recording replaced the file, so an
    /// alarm persisted before the update needs no migration. What proves it is
    /// the new recording and not the old one is the format: the original was
    /// a 2.5 s mono file, the replacement is 2.2 s stereo.
    func testAlarmSavedWithBirdsBeforeTheUpdateRingsTheNewRecording() throws {
        let persisted = try JSONEncoder().encode(Alarm(name: "saved before #850", soundID: "birds"))
        let alarm = try JSONDecoder().decode(Alarm.self, from: persisted)

        XCTAssertEqual(AlarmScheduler.shared.alarmSoundFileName(for: alarm.soundID), "birds.caf")
        let url = try XCTUnwrap(SoundCatalogue.fileURL(for: alarm.soundID))
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.channelCount, 2, "birds.caf is still the mono original")
        XCTAssertEqual(SoundCatalogue.fileDuration(for: alarm.soundID) ?? 0, 2.22, accuracy: 0.01)
    }

    /// Unlike the ring, the preview has no `default_alarm` fallback: playing
    /// another sound under this row's name would hide the missing file. Also
    /// pins that the probe follows the ring's extension order (`caf` first).
    func testFileURLProbesLikeTheRingButNeverFallsBack() {
        let onlyDefault: (String, String) -> URL? = { name, ext in
            name == AudioService.fallbackSoundID ? URL(fileURLWithPath: "/\(name).\(ext)") : nil
        }
        XCTAssertNil(SoundCatalogue.fileURL(for: "vanished_sound", resourceURL: onlyDefault))
        XCTAssertNil(SoundCatalogue.fileDuration(for: "vanished_sound"))
        // An empty name means "any file" to `Bundle.url(forResource:…)`.
        XCTAssertNil(SoundCatalogue.fileURL(for: ""), "an empty id found some other sound's file")

        let wavAndCaf: (String, String) -> URL? = { name, ext in
            ["wav", "caf"].contains(ext) ? URL(fileURLWithPath: "/\(name).\(ext)") : nil
        }
        XCTAssertEqual(
            SoundCatalogue.fileURL(for: "hawk", resourceURL: wavAndCaf)?.lastPathComponent,
            "hawk.caf"
        )
    }
}
