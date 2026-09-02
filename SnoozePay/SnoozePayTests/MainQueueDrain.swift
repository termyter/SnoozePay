import XCTest

/// Runs the main queue until a freshly enqueued block comes back promptly,
/// i.e. until nothing of anyone else's is still queued ahead of it. The queue
/// is FIFO, so one prompt round trip is proof the backlog is gone; the loop
/// only exists because draining it can enqueue more work in turn.
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
/// finding, and it should surface as the calling class timing out — not as the
/// whole suite hanging with no output.
///
/// Shared rather than copied: #618 fixed one class this way and #693 is the
/// same failure in the next one, so a second private copy would have been the
/// start of drift between them.
func drainMainQueue(cap: TimeInterval = 60) {
    let deadline = Date().addingTimeInterval(cap)
    while deadline.timeIntervalSinceNow > 0 {
        let turn = XCTestExpectation(description: "main queue turn")
        let enqueuedAt = Date()
        DispatchQueue.main.async { turn.fulfill() }
        guard XCTWaiter.wait(
            for: [turn], timeout: deadline.timeIntervalSinceNow
        ) == .completed else { return }
        if Date().timeIntervalSince(enqueuedAt) < 0.1 { return }
    }
}
