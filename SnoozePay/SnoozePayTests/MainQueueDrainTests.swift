import Foundation
import XCTest

// Cover for the shared drain helper itself (#698).

/// Records the order blocks actually ran in. A reference type, not a captured
/// `var`, because it is written from `DispatchQueue.main.async` blocks.
private final class OrderRecorder {
    var order: [Int] = []
}

/// Keeps the main queue permanently busy: each block occupies the queue for
/// longer than the drain's quiet threshold and then queues its successor.
///
/// Sleeping rather than spinning on purpose — the drain is measuring how long a
/// probe takes to come back, and a sleeping block delays it exactly as a slow
/// piece of real UIKit work would, without taking CPU from a runner that has
/// three cores to begin with.
///
/// Internal rather than `private` because `MainQueueDrainXCTFailDefaultTests`
/// needs the same busy queue to reach the failure path (#716), and two hogs
/// that drift apart would make the two suites test different conditions while
/// reading as if they tested one.
final class QueueHog {

    /// Comfortably over the 0.1 s threshold, so every probe round trip counts
    /// as "still spending" rather than depending on how loaded the runner is.
    private let occupancy: TimeInterval = 0.2
    private var keepGoing = true

    func start() {
        enqueue()
    }

    /// Must be called before the test returns, or the hog outlives it and the
    /// next class pays — the exact cross-suite backlog this helper exists to
    /// stop. Safe to call synchronously: the pending block cannot run until the
    /// run loop turns again, and by then the flag is false.
    func stop() {
        keepGoing = false
    }

    private func enqueue() {
        DispatchQueue.main.async { [self] in
            guard keepGoing else { return }
            Thread.sleep(forTimeInterval: occupancy)
            enqueue()
        }
    }
}

/// `drainMainQueue` is load-bearing for two suites and is the fix for a class of
/// failure this project has hit twice (#618, #693) — yet it had no test of its
/// own. That matters more than usual here: if someone "simplifies" it into a
/// no-op, both suites keep passing on a quiet machine and the flake comes back
/// only in the nightly clean build, off the PR path, where nobody looks at it
/// for weeks. These tests fail on the spot instead.
///
/// Note on ordering: "M" sorts ahead of the "U" of both `UITour*` suites, so
/// this class now performs the first drain in the whole target and absorbs the
/// backlog of everything from A to L. That is the right place for it, and it
/// does mean a genuinely stuck queue surfaces here first.
///
/// `@MainActor` is spelled out rather than inherited from
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, because the strictness of the
/// no-op canary below rests on it: "this test body holds the main thread" is
/// what makes an empty `order` proof rather than a race. Left implicit, a
/// change to that build setting would degrade the canary quietly instead of
/// failing to compile.
@MainActor
final class MainQueueDrainTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The suite runs hundreds of tests before this one, and the first test
        // that spins the run loop pays for every block they left queued (#618).
        // That backlog belongs to nobody's assertion here, least of all the
        // timing one, so spend it before the tests start rather than inside one.
        drainMainQueue()
    }

    // MARK: - Draining

    /// The property the two suites actually rely on: when the call returns, the
    /// work that was already queued has run.
    ///
    /// This is the test that goes red if `drainMainQueue` is reduced to a no-op,
    /// and the reason it must is exact rather than probabilistic: this test body
    /// holds the main thread from the first `async` to the assertion, so a main
    /// queue block physically cannot run until something spins the run loop. If
    /// the drain stops doing that, `order` is still empty on the line below.
    func testDrainRunsEveryAlreadyQueuedBlockBeforeReturning() {
        let recorder = OrderRecorder()
        let blockCount = 25
        for index in 0..<blockCount {
            DispatchQueue.main.async { recorder.order.append(index) }
        }
        XCTAssertTrue(
            recorder.order.isEmpty,
            "precondition: nothing may run while this test holds the main thread"
        )

        XCTAssertTrue(
            drainMainQueue(cap: 30),
            "the backlog was finite, so the drain must report the queue went quiet"
        )

        XCTAssertEqual(
            recorder.order, Array(0..<blockCount),
            """
            drainMainQueue returned with queued work still pending, which is the \
            whole thing the two tour suites call it for.
            """
        )
    }

    /// A drain that no longer recognises a quiet queue is not a wrong answer,
    /// it is a 60 s bill on every `setUp` that calls it — ~600 s across the ten
    /// tests of `UITourWarningRoutesTests`.
    ///
    /// The `Bool` above is what catches a drain that burns its whole cap; this
    /// assertion is narrower and covers what the `Bool` cannot — a drain that
    /// reports quiet but takes its time getting there. The budget is loose on
    /// purpose. `setUp` already drained, so the honest expectation is one round
    /// trip, i.e. single-digit milliseconds; the 0.5 s the issue suggested sits
    /// inside the noise of a three-core CI runner, where one scheduling hiccup
    /// over the 0.1 s quiet threshold forces another turn of the loop and would
    /// redden this with no defect behind it.
    func testDrainOfAQuietQueueReturnsWithoutSpendingTheCap() {
        let started = Date()
        XCTAssertTrue(drainMainQueue(cap: 30), "an already quiet queue must drain immediately")
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(
            elapsed, 5,
            "draining an already quiet queue took \(elapsed) s — that is not one round trip"
        )
    }

    /// The whole point of #698: running out of cap must not be silent.
    ///
    /// Asserted through the injected sink rather than `XCTExpectFailure`, which
    /// has no precedent in this target. Deleting the report from
    /// `drainMainQueue` — the exact regression that put this issue on the board
    /// one level down — turns this red.
    func testDrainReportsACapItBurnedInsteadOfReturningQuietly() {
        let hog = QueueHog()
        hog.start()
        var reports: [String] = []

        let quiet = drainMainQueue(cap: 1) { message, _, _ in reports.append(message) }
        hog.stop()

        XCTAssertFalse(quiet, "a queue that never settled must not be reported as quiet")
        XCTAssertEqual(reports.count, 1, "a burned cap must be reported exactly once")
        XCTAssertTrue(
            reports.first?.contains("never went quiet") ?? false,
            "the report must name what happened, got: \(reports.first ?? "<nothing>")"
        )
    }

    /// And the outcome behind that report has to carry the numbers, because
    /// "queue was busy" and "runner was starved of CPU" both land here and only
    /// the turn count and round trip tell them apart.
    func testCapExhaustionOutcomeCarriesTheTurnCountAndTheLastRoundTrip() {
        let hog = QueueHog()
        hog.start()

        let outcome = drainMainQueueOutcome(cap: 1)
        hog.stop()

        guard case let .capExhausted(turns, lastProbe, _, cap) = outcome else {
            return XCTFail("a permanently busy queue must exhaust the cap, got \(outcome)")
        }
        XCTAssertFalse(outcome.isQuiet)
        XCTAssertGreaterThan(turns, 0, "the drain must count the turns it spent")
        XCTAssertGreaterThan(
            lastProbe, 0,
            "the last probe's duration is half the evidence for telling starvation from backlog"
        )
        XCTAssertEqual(cap, 1, accuracy: 0.001, "the outcome must report the cap it was given")
        XCTAssertTrue(outcome.diagnosis.contains("probe"), "the diagnosis must describe the probe")
    }

    /// A probe that outlived the deadline has no round trip to report, and one
    /// that came back late has nothing outstanding — a single noun for both
    /// puts the wrong one on half the failures.
    ///
    /// Constructed directly, like the interrupted case below, because which of
    /// the two paths a real busy queue takes is a race on its final turn.
    /// Hardcoding `lastProbeReturned: true` at either construction site in
    /// `drainMainQueueOutcome` turns this red; without it that mutation is
    /// green and "round trip" quietly goes back to describing a probe that
    /// never returned.
    ///
    /// Each half asserts the ABSENCE of the other's wording as well as the
    /// presence of its own: a mutation that welded both sentences into one
    /// would survive presence-only assertions.
    func testCapExhaustionDistinguishesALateProbeFromOneThatNeverCameBack() {
        let cameBackLate = MainQueueDrainOutcome.capExhausted(
            turns: 5, lastProbe: 0.2, lastProbeReturned: true, cap: 1
        ).diagnosis
        let neverCameBack = MainQueueDrainOutcome.capExhausted(
            turns: 5, lastProbe: 0.98, lastProbeReturned: false, cap: 1
        ).diagnosis

        XCTAssertTrue(
            cameBackLate.contains("round trip"),
            "a probe that did come back must be reported as a round trip, got: \(cameBackLate)"
        )
        XCTAssertFalse(
            cameBackLate.contains("still outstanding"),
            "a probe that came back is not outstanding, got: \(cameBackLate)"
        )

        XCTAssertTrue(
            neverCameBack.contains("still outstanding"),
            "a probe that never returned must be reported as outstanding, got: \(neverCameBack)"
        )
        XCTAssertFalse(
            neverCameBack.contains("round trip"),
            """
            a probe that never came back has no round trip to report — this is the exact \
            wording that had the diagnosis claim a late arrival where there was none. \
            Got: \(neverCameBack)
            """
        )
    }

    /// A wait cut short is not a timeout, and saying "never went quiet within
    /// 60 s" about it would be false. Constructed directly because
    /// `.interrupted` needs nested waiters to occur naturally.
    func testAWaitThatEndedEarlyDoesNotBlameTheCap() {
        let outcome = MainQueueDrainOutcome.waitEndedEarly(
            turns: 2, waiterResult: .interrupted, cap: 60
        )

        XCTAssertFalse(outcome.isQuiet)
        XCTAssertTrue(
            outcome.diagnosis.contains("not a timeout"),
            "an interrupted wait must not be reported as a burned cap, got: \(outcome.diagnosis)"
        )
    }

    func testAQuietOutcomeHasNothingToSay() {
        XCTAssertTrue(MainQueueDrainOutcome.quiet(turns: 1).isQuiet)
        XCTAssertEqual(MainQueueDrainOutcome.quiet(turns: 1).diagnosis, "")
    }
}
