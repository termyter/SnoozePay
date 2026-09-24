import AVFoundation
import os
import XCTest
@testable import SnoozePay

/// Pins `AudioService.beginPreviewSession` / `endPreviewSession` (#850): a
/// sound-picker preview mixes with the user's audio and hands the session back
/// afterwards, and neither call touches a session an alarm is ringing on.
///
/// Both session calls are swapped for recorders through
/// `overridePreviewSession`, and the ring's activation through
/// `overrideSessionActivation`, so nothing here reaches `AVAudioSession`.
final class AudioServicePreviewSessionTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)

    /// Reference box: the recorders run on the service's queue, not here.
    private final class SessionLog {
        var events: [String] = []
    }

    private let service = AudioService.shared
    private var log: SessionLog!

    override func setUp() {
        super.setUp()
        service.stopAlarmSound()
        log = SessionLog()
        let log = self.log!
        service.overridePreviewSession(
            setCategory: { log.events.append("ambient") },
            deactivate: { log.events.append("deactivate") }
        )
    }

    override func tearDown() {
        service.overridePreviewSession(setCategory: nil, deactivate: nil)
        service.overrideSessionActivation(nil)
        service.stopAlarmSound()
        super.tearDown()
    }

    func testWithNoAlarmRingingThePreviewMixesAndThenHandsTheSessionBack() {
        service.beginPreviewSession()
        XCTAssertEqual(log.events, ["ambient"])
        service.endPreviewSession()
        XCTAssertEqual(log.events, ["ambient", "deactivate"])
    }

    /// `.ambient` mid-ring would mute the alarm under the silent switch, and
    /// deactivating would cut it off: a ringing alarm's session is left alone.
    func testWhileAnAlarmRingsThePreviewSessionCallsDoNothing() {
        service.overrideSessionActivation {}
        service.startAlarmSound(soundID: "radar")
        XCTAssertEqual(service.state, .playing, "precondition: an alarm is ringing")

        service.beginPreviewSession()
        service.endPreviewSession()

        XCTAssertEqual(log.events, [], "the preview touched the ringing alarm's session")
        XCTAssertEqual(service.state, .playing)
    }

    /// The ring after a preview still sets up its own session: the start path
    /// runs the session activator (in production `playbackSessionActivator`,
    /// which sets `.playback`) rather than inheriting the preview's `.ambient`.
    func testAnAlarmAfterAPreviewStillActivatesItsOwnSession() {
        var activations = 0
        service.overrideSessionActivation { activations += 1 }

        service.beginPreviewSession()
        service.endPreviewSession()
        service.startAlarmSound(soundID: "radar")

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(service.state, .playing)
    }

    func testSessionFailuresAreLoggedNotThrown() {
        service.overridePreviewSession(
            setCategory: { throw NSError(domain: "preview.category", code: 1) },
            deactivate: { throw NSError(domain: "preview.deactivate", code: 2) }
        )
        var lines: [LoggedLine] = []
        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            service.beginPreviewSession()
            service.endPreviewSession()
        })
        let messages = lines.map(\.message)
        XCTAssertEqual(messages.count, 2, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains(AudioService.previewCategoryFailedErrorID) }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains(AudioService.previewDeactivateFailedErrorID) }, "\(messages)")
    }
}
