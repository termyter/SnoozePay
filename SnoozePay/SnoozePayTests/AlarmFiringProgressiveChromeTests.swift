import XCTest
@testable import SnoozePay

/// Tests for the firing-screen progressive indicator pill copy + visibility
/// (#288). The pill reads «Прогрессив · {n}-й поспать ещё» and stays hidden
/// until the first snooze. Both rules are pure functions, so they're exercised
/// without loading the view hierarchy.
@MainActor
final class AlarmFiringProgressiveChromeTests: XCTestCase {

    func testPillCopy_firstStep() {
        XCTAssertEqual(
            AlarmFiringViewController.progressivePillText(snoozeCount: 0),
            "Прогрессив · 1-й поспать ещё"
        )
    }

    func testPillCopy_countsUp() {
        XCTAssertEqual(
            AlarmFiringViewController.progressivePillText(snoozeCount: 2),
            "Прогрессив · 3-й поспать ещё"
        )
    }

    func testPillHidden_beforeFirstSnooze() {
        XCTAssertFalse(
            AlarmFiringViewController.progressivePillVisible(snoozeCount: 0),
            "Indicator pill is hidden until the first snooze (SPDawnV3.jsx:216)"
        )
    }

    func testPillVisible_afterFirstSnooze() {
        XCTAssertTrue(AlarmFiringViewController.progressivePillVisible(snoozeCount: 1))
    }
}
