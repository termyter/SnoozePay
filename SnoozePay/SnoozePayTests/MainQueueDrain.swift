import UIKit
import XCTest

// Shared support for the handful of suites that spin the main run loop. Both
// helpers here exist because a second private copy is how the two suites start
// drifting apart (#618 and #693 are the same failure in different classes).

/// A probe round trip faster than this means nothing that was already queued
/// ran ahead of it.
private let mainQueueQuietRoundTrip: TimeInterval = 0.1

/// Runs the main queue until a freshly enqueued block comes back promptly, i.e.
/// until the work that was *already queued* has been spent. The queue is FIFO,
/// so one prompt round trip is proof the standing backlog is gone.
///
/// What it does not cover, stated plainly because the previous wording was
/// wider than the truth: a block sitting on a timer is not in the queue until
/// its deadline arrives, so `asyncAfter` work scheduled for later is invisible
/// to a FIFO probe and will still be delivered into the next wait. The backlog
/// behind #618 and #693 was queued work, not timers, so the drain does hit what
/// it is aimed at — it just is not a barrier against everything.
///
/// The loop repeats only when a round trip came back slow, which is exactly the
/// case where the backlog was still being spent and could have queued more work
/// in turn. Once a turn is prompt the drain stops, so a block enqueued *by* that
/// last prompt turn is left for the caller — by then there is no backlog to
/// confuse it with.
///
/// Why any test needs this (#618, #693): the suite is ~1000 mostly synchronous
/// tests, and the handful of classes that spin the main run loop inherit every
/// piece of deferred UIKit work the preceding ones left queued. That backlog
/// gets spent inside the *first* wait that runs the loop, so a route that
/// presents on a 0.8 s beat can be delivered ten seconds late — and the wait
/// measuring it fails for a reason that has nothing to do with the route.
///
/// Call it from `setUp`, before anything is mounted. The point is to take the
/// backlog OUT of what the wait measures. The alternative — a wider timeout —
/// would have to be wide enough to hold the whole backlog, and a window that
/// wide no longer notices the routing regression the wait exists to catch.
///
/// Capped rather than unbounded: a main queue that never goes quiet is a
/// finding, and running out of cap fails the calling test **by name** instead of
/// returning quietly. Silence was the old behaviour and it was the worst of both
/// worlds — up to 60 s spent per `setUp`, and not one line in the log saying
/// where they went. The `Bool` is there for the helper's own tests; callers can
/// ignore it, because the `XCTFail` has already spoken.
///
/// Not `@MainActor`, deliberately: `UITourConfirmDeleteRouteTests` is a
/// non-isolated `XCTestCase`, and annotating this function would force an
/// isolation change on that suite for a bug that does not exist — both callers
/// are on the main thread. The misuse the annotation would have prevented is
/// instead caught below, at runtime, where it also names itself.
@discardableResult
func drainMainQueue(
    cap: TimeInterval = 60,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Bool {
    guard Thread.isMainThread else {
        XCTFail(
            """
            drainMainQueue was called off the main thread, where it blocks on \
            the queue instead of draining it.
            """,
            file: file,
            line: line
        )
        return false
    }
    let deadline = Date().addingTimeInterval(cap)
    while deadline.timeIntervalSinceNow > 0 {
        let turn = XCTestExpectation(description: "main queue turn")
        let enqueuedAt = Date()
        DispatchQueue.main.async { turn.fulfill() }
        guard XCTWaiter.wait(
            for: [turn], timeout: deadline.timeIntervalSinceNow
        ) == .completed else { break }
        if Date().timeIntervalSince(enqueuedAt) < mainQueueQuietRoundTrip { return true }
    }
    XCTFail(
        """
        main queue never went quiet within \(cap) s: a probe block kept taking \
        longer than \(mainQueueQuietRoundTrip) s to come back, so something is \
        still feeding the queue. Whatever this test asserts next was going to be \
        measured through that backlog.
        """,
        file: file,
        line: line
    )
    return false
}

/// Describes the presentation chain hanging off `root`, printed on failure so
/// the next red run names the missing link instead of only saying one is
/// missing. A chain of just `UITabBarController` means the route never
/// presented at all; a chain that reaches the sheet with `window: nil` means it
/// fired at a presenter that had left the hierarchy and UIKit dropped it on the
/// floor — two different bugs behind one message otherwise (#618, #693).
///
/// One copy on purpose: this was duplicated across the two tour suites, with
/// the only difference being how each of them reaches its root controller, so
/// the parameter is that root.
func presentationDiagnostics(rootedAt root: UIViewController?) -> String {
    var chain: [String] = []
    var current = root
    while let node = current {
        let attached = node.viewIfLoaded?.window == nil ? "window: nil" : "window: set"
        chain.append("\(type(of: node))(\(attached))")
        current = node.presentedViewController
    }
    return "presentation chain: "
        + (chain.isEmpty ? "no root view controller" : chain.joined(separator: " → "))
}
