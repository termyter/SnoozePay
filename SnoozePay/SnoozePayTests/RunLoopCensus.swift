import Foundation

/// A record of when a fixed-interval poll *actually* got to run during a wait.
///
/// Why this exists (#728). `UITourConfirmDeleteRouteTests` times out waiting for
/// a route to present, and two very different failures produce that one symptom:
///
///   1. the run loop was starved, so the wait's own poll — and the route's
///      `asyncAfter` beat with it — never got a turn. Nothing could have been
///      observed, whatever the route did;
///   2. the loop turned normally throughout and the route still never presented.
///
/// The CI log of the red attempt cannot tell them apart, because a wait that
/// ends empty looks identical either way. A poll that leaves a trail can.
///
/// The premise — stated as a premise, because this target does not test
/// Foundation and a test that did would be slow and flaky for no gain — is that
/// a repeating `Timer` coalesces rather than queues up the fires it missed. On
/// that premise a stalled loop shows as ticks that are simply absent, and the
/// gap between the surviving ones measures the stall directly. If it ever turned
/// out that missed fires are replayed instead, this would under-report stalls;
/// it would not invent one that did not happen, and the elapsed-versus-budget
/// figure alongside it is independent of the premise either way.
///
/// Deliberately a value type with injected timestamps: every number it reports
/// is arithmetic over `Date`s handed to it, so its own tests are exact instead
/// of racing the machine they run on.
struct RunLoopCensus {

    /// The interval the poll was scheduled at, kept so the summary can say how
    /// many ticks the wait *should* have seen.
    let interval: TimeInterval

    /// When the wait began — the head of the timeline, and the left edge of the
    /// first gap.
    let started: Date

    private(set) var ticks: [Date] = []

    init(interval: TimeInterval, started: Date = Date()) {
        self.interval = interval
        self.started = started
    }

    mutating func record(at moment: Date = Date()) {
        ticks.append(moment)
    }

    /// How many ticks a loop that never stalled would have delivered by `now`.
    ///
    /// Rounded rather than truncated: `0.6 / 0.05` is 11.999999999999998 in
    /// binary floating point, and a figure the reader compares a tick count
    /// against must not be off by one because of that.
    func expectedTicks(now: Date = Date()) -> Int {
        guard interval > 0 else { return 0 }
        return max(0, Int((now.timeIntervalSince(started) / interval).rounded()))
    }

    /// The longest stretch the loop went without turning, as offsets from
    /// `started`.
    ///
    /// The stretch before the first tick and the one after the last count as
    /// stalls too. That is not tidiness: a loop that dies right after the wait
    /// starts and one that dies just before it ends are two shapes this failure
    /// could take, and measuring only the gaps *between* ticks reports both as
    /// "no stall".
    func longestStall(now: Date = Date()) -> (from: TimeInterval, to: TimeInterval) {
        let end = max(now, ticks.last ?? now)
        let boundaries = [started] + ticks + [end]
        var widest = (from: 0.0, to: 0.0)
        for (earlier, later) in zip(boundaries, boundaries.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            guard gap > widest.to - widest.from else { continue }
            widest = (
                from: earlier.timeIntervalSince(started),
                to: later.timeIntervalSince(started)
            )
        }
        return widest
    }

    /// The sentence a timed-out wait should print.
    ///
    /// It states both readings rather than picking one, for the same reason
    /// `MainQueueDrainOutcome.diagnosis` does: the threshold between "starved"
    /// and "merely nothing to find" is a judgement about a specific run, and
    /// baking a guess into the message would hand the next reader a verdict
    /// where the numbers are what they need.
    func summary(now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(started)
        let stall = longestStall(now: now)
        return """
            run loop census: \(ticks.count) of ~\(expectedTicks(now: now)) expected \
            \(seconds(interval)) polls over \(seconds(elapsed)), longest stall \
            \(seconds(stall.to - stall.from)) (+\(seconds(stall.from)) → +\(seconds(stall.to))). \
            Far fewer polls than expected, or one stall covering most of the wait, means the \
            run loop was not turning: the route's own beat could not have been delivered \
            either, and a drain in setUp does not reach a backlog that accrues inside the \
            test (#618, #728). Polls arriving on schedule mean the opposite — the loop \
            turned the whole time, the beat was delivered, and the presentation is what \
            never happened.
            """
    }

    private func seconds(_ value: TimeInterval) -> String {
        return String(format: "%.2f s", value)
    }
}
