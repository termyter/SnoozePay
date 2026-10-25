import AVFoundation
import os
import XCTest
@testable import SnoozePay

final class AudioPlayerFallbackDiagnosticTests: XCTestCase {

    private struct LoggedLine {
        let category: AppLogCategory
        let level: OSLogType
        let message: String
    }
    private let service = AudioService.shared

    override func setUp() {
        super.setUp()
        service.overrideSessionActivation {}
        service.overrideSessionDeactivation {}
        service.stopAlarmSound()
        service.overrideAlarmPlayerResolution(nil)
    }

    override func tearDown() {
        service.stopAlarmSound()
        service.overrideAlarmPlayerResolution(nil)
        service.overrideSessionActivation(nil)
        service.overrideSessionDeactivation(nil)
        super.tearDown()
    }

    func testSyntheticPlayer_rejectionReturnsNilAndLogsItsOriginalPublicReason() {
        let failure = NSError(domain: "TonePlayerFixture", code: 31)
        var factoryCalls = 0
        var lines: [LoggedLine] = []
        var player: AVAudioPlayer?

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            player = AudioService.generateAlarmTone { data in
                factoryCalls += 1
                XCTAssertEqual(Array(data.prefix(4)), [0x52, 0x49, 0x46, 0x46])
                throw failure
            }
        })

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertNil(player)
        assertLine(lines, level: .error, message: "generateAlarmTone: AVAudioPlayer init failed: \(failure)")
    }

    func testSyntheticPlayer_successReturnsTheConstructedPlayerWithoutAnError() throws {
        let expected = try makePlayer()
        var factoryCalls = 0
        var lines: [LoggedLine] = []
        var player: AVAudioPlayer?

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            player = AudioService.generateAlarmTone { data in
                factoryCalls += 1
                XCTAssertGreaterThan(data.count, 44, "the factory must receive generated PCM, not an empty seam")
                return expected
            }
        })

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(player === expected)
        XCTAssertTrue(lines.isEmpty)
    }

    func testStart_withoutAPlayerRetainsTheOwnerAndReportsVibrationOnly() {
        let alarmID = UUID()
        var requestedSounds: [String] = []
        service.overrideAlarmPlayerResolution { soundID in
            requestedSounds.append(soundID)
            return nil
        }
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            service.startAlarmSound(soundID: "default_alarm", alarmID: alarmID)
        })

        XCTAssertEqual(requestedSounds, ["default_alarm"])
        XCTAssertEqual(service.state, .vibrationOnly)
        XCTAssertEqual(service.currentAlarmID, alarmID)
        XCTAssertNil(service.currentPlayerVolume)
        assertLine(lines, level: .default, message: "startAlarmSound: no audio source available, vibration only")
    }

    func testStart_prepareAndPlayResultsControlTheDiagnosticAndFallbackState() throws {
        for prepared in [false, true] {
            for started in [false, true] {
                service.stopAlarmSound()
                let player = try makePlayer()
                player.prepareResult = prepared
                player.playResults = [started]
                service.overrideAlarmPlayerResolution { _ in player }
                let alarmID = UUID()
                var lines: [LoggedLine] = []

                AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
                    service.startAlarmSound(soundID: "default_alarm", alarmID: alarmID)
                })

                XCTAssertEqual(player.prepareCalls, 1)
                XCTAssertEqual(player.playCalls, 1, "play remains attempted even when preparation refuses")
                XCTAssertEqual(service.currentAlarmID, alarmID)
                if prepared && started {
                    XCTAssertEqual(service.state, .playing)
                    XCTAssertNotNil(service.currentPlayerVolume)
                    XCTAssertTrue(lines.isEmpty)
                } else {
                    XCTAssertEqual(service.state, .vibrationOnly)
                    XCTAssertNil(service.currentPlayerVolume, "a refused start must release the owned player")
                    assertLine(
                        lines, level: .error,
                        message: "AVAudioPlayer play() rejected (prepared=\(prepared), started=\(started))"
                    )
                }
            }
        }
    }

    func testResume_playRefusalReportsVibrationOnlyAfterReactivatingTheSession() throws {
        let player = try makePlayer()
        player.playResults = [true, false]
        service.overrideAlarmPlayerResolution { _ in player }
        var activations = 0
        var activationsAtPlay: [Int] = []
        service.overrideSessionActivation { activations += 1 }
        player.onPlay = { activationsAtPlay.append(activations) }
        let alarmID = UUID()
        service.startAlarmSound(soundID: "default_alarm", alarmID: alarmID)
        XCTAssertEqual(service.state, .playing)
        service.pauseAlarmSound()
        XCTAssertTrue(service.isPaused)
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            service.resumeAlarmSound()
        })

        XCTAssertEqual(activations, 2)
        XCTAssertEqual(activationsAtPlay, [1, 2], "each play must follow its own successful activation")
        XCTAssertEqual(player.prepareCalls, 1)
        XCTAssertEqual(player.playCalls, 2)
        XCTAssertEqual(service.state, .vibrationOnly)
        XCTAssertEqual(service.currentAlarmID, alarmID)
        XCTAssertFalse(service.isPaused)
        XCTAssertNotNil(service.currentPlayerVolume, "resume retains its player as before")
        assertLine(lines, level: .error, message: "resumePlaybackLocked: AVAudioPlayer.play() returned false")
    }

    private func makePlayer() throws -> ControlledPlayer {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "default_alarm", withExtension: "caf"))
        return try ControlledPlayer(contentsOf: url)
    }

    private func assertLine(
        _ lines: [LoggedLine], level: OSLogType, message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(lines.count, 1, file: file, line: line)
        XCTAssertEqual(lines.first?.category, .audio, file: file, line: line)
        XCTAssertEqual(lines.first?.level, level, file: file, line: line)
        XCTAssertEqual(lines.first?.message, message, file: file, line: line)
    }
}

private final class ControlledPlayer: AVAudioPlayer {
    var prepareResult = true
    var playResults = [true]
    var onPlay: (() -> Void)?
    private(set) var prepareCalls = 0
    private(set) var playCalls = 0

    override func prepareToPlay() -> Bool {
        prepareCalls += 1
        return prepareResult
    }

    override func play() -> Bool {
        playCalls += 1
        onPlay?()
        return playResults.isEmpty ? false : playResults.removeFirst()
    }
}
