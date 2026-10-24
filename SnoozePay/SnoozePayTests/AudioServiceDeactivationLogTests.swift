import os
import XCTest
@testable import SnoozePay

/// Alarm teardown has no recovery UI: its error log is the evidence that the
/// session may still duck another app's audio (#744).
final class AudioServiceDeactivationLogTests: XCTestCase {

    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)
    private let service = AudioService.shared

    override func setUp() {
        super.setUp()
        service.overrideSessionDeactivation {}
        service.stopAlarmSound()
    }

    override func tearDown() {
        service.overrideSessionDeactivation {}
        service.stopAlarmSound()
        service.overrideSessionDeactivation(nil)
        super.tearDown()
    }

    func testStop_deactivationFailureLeavesExactlyOneAudioErrorWithItsReason() {
        var calls = 0
        service.overrideSessionDeactivation {
            calls += 1
            throw NSError(domain: "AudioDeactivationFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "injected deactivation failure"
            ])
        }
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            service.stopAlarmSound()
        })

        XCTAssertEqual(calls, 1, "stop must attempt to hand the audio session back")
        XCTAssertEqual(lines.count, 1, "a failed handoff needs exactly one diagnostic")
        XCTAssertEqual(lines.first?.category, .audio)
        XCTAssertEqual(lines.first?.level, .error)
        XCTAssertEqual(
            lines.first?.message,
            "failed to deactivate audio session: injected deactivation failure"
        )
        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.currentAlarmID)
    }

    func testStop_successfulDeactivationDoesNotReportAnError() {
        var calls = 0
        service.overrideSessionDeactivation { calls += 1 }
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            service.stopAlarmSound()
        })

        XCTAssertEqual(calls, 1, "an empty sink must not be explained by skipping deactivation")
        XCTAssertTrue(lines.isEmpty, "successful handoff must not produce a failure diagnostic")
    }
}
