import os
import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class ExternalActionDiagnosticTests: XCTestCase {
    private typealias OpenCompletion = @MainActor @Sendable (Bool) -> Void

    func testSettingsOpen_refusalLogsOnlyWhenTheActualCompletionArrives() throws {
        var urls: [URL] = []
        var callback: OpenCompletion?
        var messages: [String] = []

        try AppLogger.withTestSink({ category, level, message in
            XCTAssertEqual(category, .ui)
            XCTAssertEqual(level, .error)
            messages.append(message)
        }, perform: {
            AlarmsListViewController.openSystemSettings { url, completion in
                urls.append(url)
                callback = completion
            }
            XCTAssertTrue(messages.isEmpty, "opening has no outcome before completion")
            let complete = try XCTUnwrap(callback)
            complete(false)
        })

        XCTAssertEqual(urls, [try XCTUnwrap(URL(string: UIApplication.openSettingsURLString))])
        XCTAssertEqual(messages, ["failed to open the Settings deeplink for the alarm-backend guard"])
    }

    func testSettingsOpen_successLeavesNoRefusalDiagnostic() throws {
        var urls: [URL] = []
        var callback: OpenCompletion?
        var messages: [String] = []

        try AppLogger.withTestSink({ _, _, message in messages.append(message) }, perform: {
            AlarmsListViewController.openSystemSettings { url, completion in
                urls.append(url)
                callback = completion
            }
            let complete = try XCTUnwrap(callback)
            complete(true)
        })

        XCTAssertEqual(urls, [try XCTUnwrap(URL(string: UIApplication.openSettingsURLString))])
        XCTAssertTrue(messages.isEmpty)
    }

    func testShareCompletion_errorTakesPriorityOverACompletedFlag() throws {
        let activity = StreakModalViewController.makeShareActivity(
            streakDays: 7, savedAmount: 350, currency: .legacyDefault
        )
        let complete = try XCTUnwrap(activity.completionWithItemsHandler)
        let error = NSError(domain: "ShareCompletionFixture", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "injected share failure"
        ])
        var messages: [String] = []

        AppLogger.withTestSink({ category, level, message in
            XCTAssertEqual(category, .ui)
            XCTAssertEqual(level, .error)
            messages.append(message)
        }, perform: { complete(.copyToPasteboard, true, nil, error) })

        XCTAssertEqual(messages, [
            "streak share failed via \(UIActivity.ActivityType.copyToPasteboard.rawValue): injected share failure"
        ])
    }

    func testShareCompletion_reportsCompletedOrCancelledWithoutAnError() throws {
        for completed in [true, false] {
            let activity = StreakModalViewController.makeShareActivity(
                streakDays: 7, savedAmount: 350, currency: .legacyDefault
            )
            let complete = try XCTUnwrap(activity.completionWithItemsHandler)
            let channel: UIActivity.ActivityType? = completed ? .copyToPasteboard : nil
            var messages: [String] = []

            AppLogger.withTestSink({ category, level, message in
                XCTAssertEqual(category, .ui)
                XCTAssertEqual(level, .info)
                messages.append(message)
            }, perform: { complete(channel, completed, nil, nil) })

            let outcome = completed ? "completed" : "cancelled"
            XCTAssertEqual(messages, ["streak share via \(channel?.rawValue ?? "unknown") \(outcome)"])
        }
    }
}
