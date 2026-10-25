import os
import XCTest
@testable import SnoozePay

@MainActor
final class SceneDelegateDiagnosticTests: XCTestCase {
    func testTransitionToMainApp_withoutAWindowLeavesTheExistingError() {
        let delegate = SceneDelegate()
        XCTAssertNil(delegate.window, "precondition: this delegate has no connected scene")
        var messages: [String] = []

        AppLogger.withTestSink({ category, level, message in
            XCTAssertEqual(category, .appDelegate)
            XCTAssertEqual(level, .error)
            messages.append(message)
        }, perform: {
            delegate.transitionToMainApp()
        })

        XCTAssertEqual(messages, ["transitionToMainApp: window nil — user stuck on onboarding"])
        XCTAssertNil(delegate.window, "the diagnostic must not invent a window or a root")
    }
}
