import AVFoundation
import os
import XCTest
@testable import SnoozePay

/// #861: `radar` left the picker (its file was a byte copy of
/// `default_alarm.caf`), and `bell.caf` was trimmed under the 30 s cap that
/// iOS puts on alarm and notification sounds. Reads the real bundle: the test
/// host is the app.
final class SoundCatalogueRetiredRadarTests: XCTestCase {

    private func decodedRadarAlarm() throws -> Alarm {
        let persisted = try JSONEncoder().encode(Alarm(name: "saved before #861", soundID: "radar"))
        return try JSONDecoder().decode(Alarm.self, from: persisted)
    }

    func testPickerNoLongerOffersRadar() {
        XCTAssertFalse(SoundCatalogue.ids.contains("radar"))
        XCTAssertFalse(SoundCatalogue.entries.contains { $0.id == "radar" })
        XCTAssertTrue(SoundCatalogue.ids.contains(SoundCatalogue.defaultID))
        XCTAssertEqual(SoundCatalogue.selectableID(for: "radar"), SoundCatalogue.defaultID)
        XCTAssertEqual(SoundCatalogue.selectableID(for: "bell"), "bell")
        XCTAssertEqual(SoundCatalogue.selectableID(for: "custom-file"), "custom-file")
    }

    /// The literal in `retiredFileIDs` stands for the fallback sound of both
    /// lookups; it is a literal only because the ring runs off the main actor.
    func testRadarMapsToTheFallbackSoundOfBothLookups() {
        XCTAssertEqual(SoundCatalogue.retiredFileIDs["radar"], AudioService.fallbackSoundID)
        XCTAssertEqual(SoundCatalogue.retiredFileIDs["radar"], AlarmScheduler.fallbackSoundID)
    }

    /// The saved alarm keeps its id and rings `default_alarm.caf` through the
    /// mapping, not through the missing-sound branch: the sink stays empty.
    func testSavedRadarAlarmRingsTheDefaultSoundInAppAndInAlarmKit() throws {
        let alarm = try decodedRadarAlarm()
        XCTAssertEqual(alarm.soundID, "radar")

        var lines: [String] = []
        AppLogger.withTestSink({ _, _, message in lines.append(message) }, perform: {
            XCTAssertEqual(AlarmScheduler.shared.alarmSoundFileName(for: alarm.soundID), "default_alarm.caf")
            XCTAssertEqual(
                AudioService.shared.resolveAlarmPlayer(soundID: alarm.soundID)?.url?.lastPathComponent,
                "default_alarm.caf"
            )
        })
        XCTAssertTrue(lines.isEmpty, "radar went through the missing-sound fallback: \(lines)")
    }

    /// Kept on purpose: an AlarmKit alarm registered before the update names
    /// `radar.caf` until the app re-arms it on its next launch.
    func testRadarFileStaysBundledForAlarmsRegisteredBeforeTheUpdate() {
        XCTAssertNotNil(Bundle.main.url(forResource: "radar", withExtension: "caf"))
    }

    /// Read straight from the file, not through `SoundCatalogue.fileDuration`,
    /// so a wrong reader cannot agree with itself.
    func testEveryCatalogueSoundIsShorterThanTheThirtySecondCap() throws {
        for soundID in SoundCatalogue.ids {
            let url = try XCTUnwrap(Bundle.main.url(forResource: soundID, withExtension: "caf"), soundID)
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertLessThan(seconds, 30, "'\(soundID)' runs \(seconds) s; iOS cuts or rejects sounds over 30 s")
        }
    }

    /// The trim kept the format the bundle ships: 44.1 kHz mono 16-bit PCM.
    func testBellKeepsItsFormatAfterTheTrim() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "bell", withExtension: "caf"))
        let settings = try AVAudioFile(forReading: url).fileFormat.settings
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 44_100)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertEqual(settings[AVLinearPCMIsFloatKey] as? Bool, false)
    }
}
