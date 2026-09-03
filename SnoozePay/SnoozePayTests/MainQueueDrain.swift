import Foundation
import XCTest

/// The probe is enqueued *behind* whatever is already on the queue, so by FIFO
/// all of that runs ahead of it. A round trip under this threshold therefore
/// means the standing backlog was **spent**, not that there was none: the 25
/// blocks in `MainQueueDrainTests` all run ahead of the probe and still come
/// back in milliseconds. What the threshold separates is "spent" from "still
/// spending".
///
/// It is a threshold on *latency*, and that cuts both ways: a runner starved of
/// CPU can push even an empty queue over it. That ambiguity is why the failure
/// text below prints the numbers rather than naming a single cause.
private let mainQueueQuietRoundTrip: TimeInterval = 0.1

/// How a drain ended. Separate from the reporting so the outcome can be
/// asserted by tests without a failure being recorded (#698).
enum MainQueueDrainOutcome {

    /// A probe came back inside the threshold after `turns` attempts.
    case quiet(turns: Int)

    /// The cap ran out with the queue still busy — either because a probe kept
    /// coming back late, or because the last probe outlived the deadline.
    ///
    /// `lastProbeReturned` says which of those two happened, and the diagnosis
    /// leans on it: a probe that never came back has no round trip to report,
    /// and calling its wait one anyway would tell the reader it arrived late
    /// when it did not arrive at all.
    case capExhausted(
        turns: Int, lastProbe: TimeInterval, lastProbeReturned: Bool, cap: TimeInterval
    )

    /// The wait ended for a reason that is not a timeout (`.interrupted`,
    /// `.incorrectOrder`). Kept apart from `capExhausted` on purpose: claiming
    /// "never went quiet within 60 s" for a wait that was cut short after two
    /// seconds is a false statement, and false diagnostics cost more than none.
    case waitEndedEarly(turns: Int, waiterResult: XCTWaiter.Result, cap: TimeInterval)

    var isQuiet: Bool {
        if case .quiet = self { return true }
        return false
    }

    /// Empty for `quiet`; otherwise the sentence a failing test should print.
    var diagnosis: String {
        switch self {
        case .quiet:
            return ""
        case let .capExhausted(turns, lastProbe, lastProbeReturned, cap):
            let lastProbeText = lastProbeReturned
                ? """
                    the last a \(seconds(lastProbe)) round trip against a \
                    \(seconds(mainQueueQuietRoundTrip)) threshold
                    """
                : "the last still outstanding after \(seconds(lastProbe)), never coming back at all"
            return """
                main queue never went quiet within its \(seconds(cap)) cap: \(turns) probe \
                turns, \(lastProbeText). Read both numbers before picking a cause — many \
                turns that each only just miss the \(seconds(mainQueueQuietRoundTrip)) \
                threshold is a runner starved of CPU, while a few long turns is a genuinely \
                deep queue. Either way, whatever this test asserts next was going to be \
                measured through it.
                """
        case let .waitEndedEarly(turns, waiterResult, cap):
            return """
                main queue probe stopped waiting after \(turns) turns with result \
                \(waiterResult) — not a timeout, so the \(seconds(cap)) cap is NOT the \
                explanation and the queue was never shown to be busy. Something cut the \
                wait short.
                """
        }
    }

    private func seconds(_ value: TimeInterval) -> String {
        return String(format: "%.2f s", value)
    }
}

/// Runs the main queue until a freshly enqueued block comes back promptly, i.e.
/// until the work that was *already queued* has been spent, and reports how it
/// ended instead of failing anything. `drainMainQueue` is the version that
/// speaks up; this one is silent so its own failure paths can be tested.
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
/// Deliberately NOT `@discardableResult`: this function reports nothing, so a
/// caller that drops its result has silently reintroduced the exact defect
/// #698 is about. The compiler warning on the unused enum is the only thing
/// standing between the two, which is why adding the attribute "for symmetry
/// with `drainMainQueue`" would be a regression rather than a tidy-up.
@MainActor
func drainMainQueueOutcome(cap: TimeInterval = 60) -> MainQueueDrainOutcome {
    let deadline = Date().addingTimeInterval(cap)
    var turns = 0
    var lastProbe: TimeInterval = 0
    var lastProbeReturned = false
    while deadline.timeIntervalSinceNow > 0 {
        let turn = XCTestExpectation(description: "main queue turn")
        let enqueuedAt = Date()
        DispatchQueue.main.async { turn.fulfill() }
        let waiterResult = XCTWaiter.wait(for: [turn], timeout: deadline.timeIntervalSinceNow)
        turns += 1
        // Measured before the branch below on purpose: on the path where the
        // probe never came back, this is the only record of how long it was
        // out, and reading it afterwards would report zero.
        lastProbe = Date().timeIntervalSince(enqueuedAt)
        lastProbeReturned = waiterResult == .completed
        guard waiterResult == .completed else {
            // The inner wait is bounded by the cap's own deadline, so a timeout
            // here can only mean the cap ran out with the probe still out —
            // that IS cap exhaustion. Anything else is a different animal and
            // says so.
            guard waiterResult == .timedOut else {
                return .waitEndedEarly(turns: turns, waiterResult: waiterResult, cap: cap)
            }
            return .capExhausted(
                turns: turns, lastProbe: lastProbe, lastProbeReturned: false, cap: cap
            )
        }
        if lastProbe < mainQueueQuietRoundTrip {
            return .quiet(turns: turns)
        }
    }
    return .capExhausted(
        turns: turns, lastProbe: lastProbe, lastProbeReturned: lastProbeReturned, cap: cap
    )
}

/// Drains the main queue and, if it never settles, says so by name.
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
/// Capped rather than unbounded, and loud rather than silent: a main queue that
/// never goes quiet is a finding, and running out of cap now fails the calling
/// test by name. Silence was the old behaviour and it was the worst of both
/// worlds — up to 60 s spent per `setUp`, and not one line saying where they
/// went. `file`/`line` default to the call site, so the failure lands on the
/// caller's `setUp` rather than inside this file.
///
/// `reportFailure` exists so this function's own failure path is testable
/// without `XCTExpectFailure` (which has no precedent in this target); callers
/// leave it at its default and ignore the `Bool`, because by then the failure
/// has already been recorded. It is `@MainActor` for the same reason the
/// function is — under this target's default isolation every closure written at
/// a call site is main-actor isolated anyway, and saying so avoids an isolation
/// conversion that would otherwise be inferred silently.
///
/// That the default below is `XCTFail` — and not something that returns without
/// saying anything — is pinned by `MainQueueDrainXCTFailDefaultTests` (#716),
/// which reaches this path with the default in place and asserts on the
/// `XCTIssue` XCTest actually receives. Every other test passes its own sink,
/// so without that class this line could be replaced with `{ _, _, _ in }` and
/// the whole run would stay green while both tour suites went back to burning
/// their cap in silence.
///
/// The target is built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// (`project.pbxproj`, Debug and Release), so this — like every other
/// unannotated declaration in this target — is main-actor isolated whether or
/// not it is spelled out. It is spelled out because the whole point of the
/// function is that it runs the main run loop: called off the main actor it
/// would block on the queue instead of draining it, and an explicit annotation
/// makes that a compile error rather than a comment.
@MainActor
@discardableResult
func drainMainQueue(
    cap: TimeInterval = 60,
    file: StaticString = #filePath,
    line: UInt = #line,
    reportFailure: @MainActor (String, StaticString, UInt) -> Void = { _, _, _ in }
) -> Bool {
    let outcome = drainMainQueueOutcome(cap: cap)
    guard outcome.isQuiet else {
        reportFailure(outcome.diagnosis, file, line)
        return false
    }
    return true
}
