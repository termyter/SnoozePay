import Foundation

/// Timestamp arithmetic for one sampled source's delivery (#728).
///
/// Missing Timer fires measure a source-delivery gap, not the cause: another
/// run-loop mode can suppress a default-mode Timer while GCD/UIKit still run.
/// `UIWaitProgress` supplies independent modes/queue/actor observations.
/// Timer coalescing can omit missed fires; no claim about whole-loop progress
/// should be inferred from this source's tick count alone.
///
/// Injected timestamps keep arithmetic tests deterministic, independent of
/// the runner's scheduling and mode selection.
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

    /// The longest observed source-delivery gap, as offsets from
    /// `started`.
    ///
    /// The stretch before the first tick and the one after the last count as
    /// delivery gaps too. That is not tidiness: a loop that dies right after the wait
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
    /// It names what these numbers cannot prove; a single source cannot
    /// distinguish main-thread blockage from run-loop mode suppression.
    func summary(now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(started)
        let stall = longestStall(now: now)
        return """
            run loop census: \(ticks.count) of ~\(expectedTicks(now: now)) expected \
            \(seconds(interval)) polls over \(seconds(elapsed)), longest delivery gap \
            \(seconds(stall.to - stall.from)) (+\(seconds(stall.from)) → +\(seconds(stall.to))). \
            These are delivery gaps for the sampled source, not proof that the whole run loop \
            or main queue stopped. A default-mode Timer may be suppressed by another run-loop mode. \
            Compare common-mode, GCD, and MainActor evidence before naming a mechanism; even \
            regular ticks do not prove the presentation callbacks ran.
            """
    }

    private func seconds(_ value: TimeInterval) -> String {
        return String(format: "%.2f s", value)
    }
}
