import os
import XCTest
@testable import SnoozePay

/// Pins what `CreateAlarmViewModel.previewSound` plays and how it lets go
/// (#850). The observable is `previewingURL`, the file the preview player was
/// opened from: an AudioToolbox system sound (the pre-#850 `systemSoundMap`)
/// and the ring path (`AudioService.startAlarmSound`) both leave it `nil`, so
/// either one coming back into the preview turns these tests red.
///
/// The session side goes through `AudioService.overridePreviewSession`
/// recorders, so no test here reaches `AVAudioSession`. The sound itself does
/// play; tearDown stops it.
final class CreateAlarmViewModelPreviewTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    /// Reference box: the recorders run on the audio service's queue.
    private final class SessionLog {
        var events: [String] = []
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var viewModel: CreateAlarmViewModel!
    private var sessionLog: SessionLog!

    override func setUp() {
        super.setUp()
        AudioService.shared.stopAlarmSound()
        suiteName = "test.createAlarm.preview.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        viewModel = CreateAlarmViewModel(repository: AlarmRepository(defaults: defaults))
        sessionLog = SessionLog()
        let log = sessionLog!
        AudioService.shared.overridePreviewSession(
            setCategory: { log.events.append("ambient") },
            deactivate: { log.events.append("deactivate") }
        )
    }

    override func tearDown() {
        viewModel.stopPreviewSound()
        AudioService.shared.overridePreviewSession(setCategory: nil, deactivate: nil)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Every picker row previews its own bundled file, and only through the
    /// preview player: the ring never starts.
    func testEveryRowPreviewsItsOwnBundledFile() {
        for sound in viewModel.availableSounds {
            XCTAssertTrue(viewModel.previewSound(sound.id), "'\(sound.id)' did not start a preview")
            XCTAssertNotNil(viewModel.previewingURL, "'\(sound.id)' played something other than a file")
            XCTAssertEqual(viewModel.previewingURL, SoundCatalogue.fileURL(for: sound.id), sound.id)
            XCTAssertEqual(AudioService.shared.state, .stopped, "'\(sound.id)' went through the ring path")
        }
    }

    func testStopReleasesThePlayerAndHandsTheSessionBack() {
        XCTAssertTrue(viewModel.previewSound("hawk"))
        viewModel.stopPreviewSound()

        XCTAssertNil(viewModel.previewingURL)
        XCTAssertEqual(sessionLog.events, ["ambient", "deactivate"])

        // Stopping with nothing playing leaves the session alone.
        viewModel.stopPreviewSound()
        XCTAssertEqual(sessionLog.events, ["ambient", "deactivate"])
    }

    /// A second tap replaces the first preview: the first is stopped and its
    /// session handed back before the second starts, and one player is left.
    func testASecondPreviewReplacesTheFirst() {
        XCTAssertTrue(viewModel.previewSound("hawk"))
        XCTAssertTrue(viewModel.previewSound("spaceship"))

        XCTAssertEqual(viewModel.previewingURL, SoundCatalogue.fileURL(for: "spaceship"))
        XCTAssertEqual(sessionLog.events, ["ambient", "deactivate", "ambient"])
        viewModel.stopPreviewSound()
        XCTAssertNil(viewModel.previewingURL, "something of the first preview is still held")
    }

    /// A row without a file reports it (`false` + a greppable line) and never
    /// touches the session.
    func testAMissingFileIsReportedAndLeavesTheSessionAlone() {
        var lines: [LoggedLine] = []
        let started = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            viewModel.previewSound("vanished_sound")
        })

        XCTAssertFalse(started)
        XCTAssertNil(viewModel.previewingURL)
        XCTAssertEqual(sessionLog.events, [])
        XCTAssertEqual(lines.count, 1, "\(lines.map(\.message))")
        XCTAssertTrue(
            lines.first?.message.contains(CreateAlarmViewModel.previewFileMissingErrorID) ?? false,
            "\(lines.map(\.message))"
        )
    }
}
