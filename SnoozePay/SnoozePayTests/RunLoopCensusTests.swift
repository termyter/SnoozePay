import Foundation
import XCTest

/// Cover for the census itself (#728).
///
/// The census is only ever read from a failure message, which is the worst place
/// for a bug to live: nobody looks at it until a flake is already red, and a
/// wrong number there sends the reader after the wrong mechanism — the exact
/// cost this instrumentation exists to remove. Every case below feeds it fixed
/// timestamps, so a wrong answer is a defect and never the runner's load.
final class RunLoopCensusTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    // MARK: - Counting

    func testCensusCountsTheTicksItWasGiven() {
        var census = RunLoopCensus(interval: 0.05, started: start)
        census.record(at: start.addingTimeInterval(0.05))
        census.record(at: start.addingTimeInterval(0.10))

        XCTAssertEqual(census.ticks.count, 2)
    }

    /// The count on its own says nothing — 12 ticks is healthy in a 0.6 s wait
    /// and a catastrophe in a 10 s one. What names the mechanism is the ratio,
    /// so the expected figure has to come from the wait's own length.
    func testExpectedTicksComeFromTheElapsedWaitAndNotTheTickCount() {
        let census = RunLoopCensus(interval: 0.05, started: start)

        XCTAssertEqual(census.expectedTicks(now: start.addingTimeInterval(10)), 200)
        XCTAssertEqual(census.expectedTicks(now: start.addingTimeInterval(0.6)), 12)
    }

    // MARK: - Stalls

    func testLongestStallIsTheWidestGapBetweenTicks() {
        var census = RunLoopCensus(interval: 0.05, started: start)
        census.record(at: start.addingTimeInterval(0.05))
        census.record(at: start.addingTimeInterval(9.45))
        census.record(at: start.addingTimeInterval(9.50))

        let stall = census.longestStall(now: start.addingTimeInterval(9.55))

        XCTAssertEqual(stall.from, 0.05, accuracy: 0.001)
        XCTAssertEqual(stall.to, 9.45, accuracy: 0.001)
    }

    /// A loop that never turns at all is the reading that names starvation
    /// outright, and it is precisely the case with no gap *between* ticks to
    /// measure. Reporting zero here would describe the healthiest possible wait.
    func testAWaitWithNoTicksReportsItsWholeLengthAsOneStall() {
        let census = RunLoopCensus(interval: 0.05, started: start)

        let stall = census.longestStall(now: start.addingTimeInterval(10))

        XCTAssertEqual(stall.from, 0, accuracy: 0.001)
        XCTAssertEqual(stall.to, 10, accuracy: 0.001)
    }

    /// A stall that starts before the first tick is invisible to any
    /// tick-to-tick measurement, and it is the shape "the loop was busy when the
    /// wait began" takes.
    func testAStallBeforeTheFirstTickIsCounted() {
        var census = RunLoopCensus(interval: 0.05, started: start)
        census.record(at: start.addingTimeInterval(8))
        census.record(at: start.addingTimeInterval(8.05))

        let stall = census.longestStall(now: start.addingTimeInterval(8.10))

        XCTAssertEqual(stall.from, 0, accuracy: 0.001)
        XCTAssertEqual(stall.to, 8, accuracy: 0.001)
    }

    /// And the mirror image: the loop delivers ticks, then dies with the wait
    /// still running. Without the tail boundary this reads as a 0.05 s stall.
    func testAStallAfterTheLastTickIsCounted() {
        var census = RunLoopCensus(interval: 0.05, started: start)
        census.record(at: start.addingTimeInterval(0.05))
        census.record(at: start.addingTimeInterval(0.10))

        let stall = census.longestStall(now: start.addingTimeInterval(10))

        XCTAssertEqual(stall.from, 0.10, accuracy: 0.001)
        XCTAssertEqual(stall.to, 10, accuracy: 0.001)
    }

    // MARK: - Summary

    /// The summary is the only part anyone will actually read, so it has to
    /// carry both numbers the diagnosis turns on — how many polls survived out
    /// of how many were due, and the longest stall — plus the two readings they
    /// choose between.
    func testSummaryCarriesTheRatioTheStallAndBothReadings() {
        var census = RunLoopCensus(interval: 0.05, started: start)
        census.record(at: start.addingTimeInterval(0.05))

        let summary = census.summary(now: start.addingTimeInterval(10))

        XCTAssertTrue(summary.contains("1 of ~200"), "the ratio must be in the message, got: \(summary)")
        XCTAssertTrue(summary.contains("longest stall 9.95 s"), "the stall must be named, got: \(summary)")
        XCTAssertTrue(
            summary.contains("run loop was not turning"),
            "the starvation reading must be spelled out, got: \(summary)"
        )
        XCTAssertTrue(
            summary.contains("the presentation is what"),
            "the other reading must be spelled out too, got: \(summary)"
        )
    }
}
