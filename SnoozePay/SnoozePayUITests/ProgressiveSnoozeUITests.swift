import XCTest

/// E2e for the progressive-snooze price ladder (each snooze costs more, with a
/// «N-й раз» indicator pill).
///
/// SKIPPED for now. `-uitour firing` mounts the standard (non-progressive)
/// sample alarm, so there is no tour entry point that fires a `progressiveScale`
/// alarm — the escalating price + indicator chrome never installs, leaving
/// nothing to assert. The progressive indicator pill / price ticker also lack
/// stable accessibility ids.
///
/// To enable: add a `-uitour firing-progressive` mount in `UITourLauncher`
/// that fires an alarm with `progressiveScale: true` (mirror the seeded
/// «Спортзал» alarm), add ids to the progressive indicator pill and the
/// snooze price, then assert the price grows across consecutive snoozes.
final class ProgressiveSnoozeUITests: XCTestCase {

    func testProgressiveSnoozeLadderGrows() throws {
        throw XCTSkip("""
            Needs harness support: no -uitour mount fires a progressiveScale \
            alarm, and the progressive chrome lacks stable ids. See the file \
            header for the enablement steps (#340).
            """)
    }
}
