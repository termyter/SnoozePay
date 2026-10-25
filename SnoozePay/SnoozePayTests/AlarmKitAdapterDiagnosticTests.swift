import AlarmKit
import Foundation
import os
import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
@MainActor
final class AlarmKitAdapterDiagnosticTests: XCTestCase {

    private struct LoggedLine {
        let category: AppLogCategory
        let level: OSLogType
        let message: String
    }

    private struct Resolution {
        let state: AlarmManager.AuthorizationState
        let granted: Bool
        let label: String
    }

    func testAlertingIDs_readFailureReturnsNilAndLogsTheOriginalError() {
        var reads = 0
        let backend = AlarmKitScheduler(readAlarms: {
            reads += 1
            throw NSError(domain: "NativeReadFixture", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "injected native read failure"
            ])
        })
        var lines: [LoggedLine] = []
        var result: Set<UUID>?

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            result = backend.alertingAlarmIDs
        })

        XCTAssertEqual(reads, 1)
        XCTAssertNil(result, "unreadable native state is not evidence of an empty set")
        assertLine(
            lines, level: .error,
            message: "currency refresh skipped: AlarmKit state unreadable: injected native read failure"
        )
    }

    func testAlertingIDs_successfulEmptyReadIsAnEmptySetWithoutAnError() {
        var reads = 0
        let backend = AlarmKitScheduler(readAlarms: { reads += 1; return [] })
        var lines: [LoggedLine] = []
        var result: Set<UUID>?

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            result = backend.alertingAlarmIDs
        })

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(result, Set<UUID>())
        XCTAssertTrue(lines.isEmpty)
    }

    func testAuthorization_knownStatesMapWithoutAFalseDiagnostic() {
        let cases: [(AlarmManager.AuthorizationState, AlarmKitAuthorization)] = [
            (.notDetermined, .notDetermined), (.denied, .denied), (.authorized, .authorized)
        ]
        for (native, expected) in cases {
            var reads = 0
            let backend = AlarmKitScheduler(readAuthorization: { reads += 1; return native })
            var lines: [LoggedLine] = []
            AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
                XCTAssertEqual(backend.authorization, expected)
            })
            XCTAssertEqual(reads, 1)
            XCTAssertTrue(lines.isEmpty)
        }
    }

    func testRequest_decidedStateCompletesSynchronouslyWithoutRequestingAgain() async {
        let cases: [(AlarmManager.AuthorizationState, Bool)] = [(.authorized, true), (.denied, false)]
        for (state, granted) in cases {
            let unexpectedRequest = expectation(description: "cached decision must not start a native request")
            unexpectedRequest.isInverted = true
            let completed = expectation(description: "cached authorization completion")
            completed.assertForOverFulfill = true
            var requests = 0
            let backend = AlarmKitScheduler(
                readAuthorization: { state },
                requestNativeAuthorization: {
                    requests += 1
                    unexpectedRequest.fulfill()
                    return .notDetermined
                }
            )
            var results: [Bool] = []
            var lines: [LoggedLine] = []
            await AppLogger.withAsyncTestSink({
                lines.append(LoggedLine(category: $0, level: $1, message: $2))
            }, perform: {
                backend.requestAuthorization {
                    MainActor.assertIsolated()
                    results.append($0)
                    completed.fulfill()
                }
                XCTAssertEqual(results, [granted], "cached decisions must complete before the call returns")
                await fulfillment(of: [completed, unexpectedRequest], timeout: 2)
            })
            XCTAssertEqual(requests, 0)
            XCTAssertEqual(results, [granted])
            XCTAssertTrue(lines.isEmpty)
        }
    }

    func testRequest_resolutionLogsTheNativeStateAndReportsTheActualGrant() async {
        let cases = [
            Resolution(state: .authorized, granted: true, label: "authorized"),
            Resolution(state: .denied, granted: false, label: "denied"),
            Resolution(state: .notDetermined, granted: false, label: "notDetermined")
        ]
        for resolution in cases {
            var requests = 0
            let backend = AlarmKitScheduler(
                readAuthorization: { .notDetermined },
                requestNativeAuthorization: { requests += 1; return resolution.state }
            )
            let completed = expectation(description: "native authorization completion")
            completed.assertForOverFulfill = true
            var results: [Bool] = []
            var lines: [LoggedLine] = []
            await AppLogger.withAsyncTestSink({
                lines.append(LoggedLine(category: $0, level: $1, message: $2))
            }, perform: {
                backend.requestAuthorization {
                    MainActor.assertIsolated()
                    results.append($0)
                    completed.fulfill()
                }
                await fulfillment(of: [completed], timeout: 2)
            })
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(results, [resolution.granted])
            assertLine(lines, level: .default, message: "AlarmKit authorization resolved=\(resolution.label)")
        }
    }

    func testRequest_failureLogsItsReasonAndCompletesWithFalse() async {
        var requests = 0
        let backend = AlarmKitScheduler(
            readAuthorization: { .notDetermined },
            requestNativeAuthorization: {
                requests += 1
                throw NSError(domain: "NativeAuthorizationFixture", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "injected native request failure"
                ])
            }
        )
        let completed = expectation(description: "failed native authorization completion")
        completed.assertForOverFulfill = true
        var results: [Bool] = []
        var lines: [LoggedLine] = []
        await AppLogger.withAsyncTestSink({
            lines.append(LoggedLine(category: $0, level: $1, message: $2))
        }, perform: {
            backend.requestAuthorization {
                MainActor.assertIsolated()
                results.append($0)
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 2)
        })
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(results, [false])
        assertLine(lines, level: .error, message: "AlarmKit authorization failed: injected native request failure")
    }

    private func assertLine(
        _ lines: [LoggedLine], level: OSLogType, message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(lines.count, 1, file: file, line: line)
        XCTAssertEqual(lines.first?.category, .scheduler, file: file, line: line)
        XCTAssertEqual(lines.first?.level, level, file: file, line: line)
        XCTAssertEqual(lines.first?.message, message, file: file, line: line)
    }
}
