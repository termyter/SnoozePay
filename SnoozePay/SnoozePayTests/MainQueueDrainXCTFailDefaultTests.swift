import Foundation
import XCTest

// Cover for the one part of the drain seam that assertions cannot reach (#716).

/// Pins the *binding* of `drainMainQueue`'s `reportFailure` default, not its
/// body.
///
/// The body is already safe by type: `$1` is `StaticString` and can only go to
/// `file:`, `$2` is `UInt` and can only go to `line:`. What nothing checked was
/// that the default is `XCTFail` at all. Replacing it with `{ _, _, _ in }`
/// left the whole run green — the two tests in `MainQueueDrainTests` that touch
/// the failure path either pass their own sink or go through the silent
/// outcome API, and the only two callers that use the default sit in `setUp` of
/// the tour suites, where the queue is quiet and the sink is never reached.
/// That mutation puts #698 back exactly as it was: `UITourWarningRoutesTests`
/// and `UITourConfirmDeleteRouteTests` burning up to 60 s per `setUp` with not
/// one line saying why.
///
/// Done by intercepting `record(_:)` rather than with `XCTExpectFailure`, for
/// two reasons that are checkable rather than stylistic:
///
/// - `XCTExpectFailure` absorbs *every* failure raised inside its block, so it
///   cannot tell "the default sink fired" from "one of my own assertions in
///   that block failed". Intercepting hands over the `XCTIssue` itself, so the
///   count, the wording and the reported location can each be asserted, and any
///   assertion of this test's own still fails it the normal way.
/// - `override func record` keeps this target's `XCTExpectFailure` count at
///   zero, which is what the seam's own doc comment claims about it. Overriding
///   a nonisolated `XCTestCase` method from a `@MainActor` class has ~30
///   precedents here (every `override func setUp()` in the suite, including the
///   one in `MainQueueDrainTests` that calls the `@MainActor` drain), so the
///   isolation shape is known to compile on a lane that cannot compile locally.
///
/// Named to sort after `MainQueueDrainTests` and before both `UITour*` suites:
/// classes run in alphabetical order, and `MainQueueDrainTests` documents that
/// it performs the first drain in the target and absorbs the backlog of
/// everything from A to L. Sorting ahead of it would quietly move that job here.
///
/// The name is not what makes these tests correct, though, and it must not be
/// asked to. Nothing red-flags a rename, and the scheme sets no ordering, so
/// review pointed out that this class was leaning on its neighbour twice over:
/// for the A-to-L backlog, and — worse — at half its cap, since the drains
/// below pass `cap: 1` and `cap: 30` where the sibling's `setUp` uses 60. Run
/// out of order, `testTheDefaultSinkSaysNothingWhenTheQueueGoesQuiet` would
/// assert a quiet queue against an unabsorbed backlog with half the budget,
/// and read as a broken drain rather than as a sort order. So it drains in its
/// own `setUp` instead: three lines that hold whatever the order turns out to
/// be, rather than a paragraph that holds only while someone is reading it.
///
/// `@MainActor` is spelled out rather than inherited from
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for the same reason as in the
/// sibling suite: these tests hold the main thread, and that is load-bearing.
@MainActor
final class MainQueueDrainXCTFailDefaultTests: XCTestCase {

    /// Issues recorded while `captureIssues` runs. Outside that window `record`
    /// forwards to `super`, so this class can still go red the ordinary way —
    /// a class that swallowed unconditionally could not fail at all, which is
    /// the same defect as the one under test one level up.
    private var capturedIssues: [XCTIssue] = []
    private var isCapturing = false

    /// Absorbs whatever earlier suites left queued, exactly as the sibling
    /// suite does (#618) — the first test here to spin the run loop would
    /// otherwise pay for all of it. Uses the default sink deliberately: if the
    /// backlog cannot be drained in 60 s, that is a failure worth seeing here
    /// rather than a confusing one inside a test about the sink itself.
    override func setUp() {
        super.setUp()
        drainMainQueue()
    }

    override func record(_ issue: XCTIssue) {
        guard isCapturing else {
            super.record(issue)
            return
        }
        capturedIssues.append(issue)
    }

    /// Runs `body` with XCTest's reporting chain intercepted and returns what
    /// it recorded. Every assertion belongs *outside* the window; only the call
    /// whose failure is the subject goes inside.
    private func captureIssues(during body: () -> Void) -> [XCTIssue] {
        capturedIssues = []
        isCapturing = true
        defer { isCapturing = false }
        body()
        return capturedIssues
    }

    /// A burned cap must reach XCTest through the default sink, i.e. it must
    /// fail the calling test rather than merely return `false`.
    ///
    /// This is the test that the mutation "`reportFailure` default →
    /// `{ _, _, _ in }`" turns red: no issue is recorded, and the count below
    /// is 0 instead of 1.
    func testTheDefaultSinkIsAnActualXCTestFailure() {
        let hog = QueueHog()
        hog.start()

        var quiet = true
        let issues = captureIssues { quiet = drainMainQueue(cap: 1) }
        hog.stop()

        XCTAssertFalse(quiet, "precondition: the hog must hold the queue busy past the 1 s cap")
        XCTAssertEqual(
            issues.count, 1,
            """
            a burned cap must be recorded as a test failure exactly once through the \
            default sink — 0 means the default no longer reaches XCTFail, and both tour \
            suites are back to burning their cap in silence (#698).
            """
        )
        guard let issue = issues.first else { return }

        XCTAssertTrue(
            issue.isFailure,
            "the default sink must record something that fails the test, not a note beside it"
        )
        let text = issue.compactDescription + " " + (issue.detailedDescription ?? "")
        XCTAssertTrue(
            text.contains("never went quiet"),
            "the recorded failure must carry the drain's diagnosis, got: \(text)"
        )
        XCTAssertEqual(
            issue.sourceCodeContext.location?.fileURL.lastPathComponent,
            "MainQueueDrainXCTFailDefaultTests.swift",
            """
            the failure must land on the caller, not inside MainQueueDrain.swift — that is \
            what the file/line defaults are for, and a report pointing at the helper tells \
            nobody which setUp spent the cap.
            """
        )
    }

    /// The other half, and the canary for the interceptor above: a drain that
    /// settles must record nothing at all. Without this, an interceptor that
    /// invented issues — or a sink that reported on the quiet path too — would
    /// look the same from the test above.
    func testTheDefaultSinkSaysNothingWhenTheQueueGoesQuiet() {
        var quiet = false
        let issues = captureIssues { quiet = drainMainQueue(cap: 30) }

        XCTAssertTrue(quiet, "precondition: an unhogged queue must go quiet inside 30 s")
        XCTAssertTrue(
            issues.isEmpty,
            "a quiet drain must be silent, got: \(issues.map(\.compactDescription))"
        )
    }
}
