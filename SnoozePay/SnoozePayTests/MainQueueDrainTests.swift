import UIKit
import XCTest

// Cover for the shared test helpers themselves (#698).

/// Records the order blocks actually ran in. A reference type, not a captured
/// `var`: it is written from `DispatchQueue.main.async` blocks. Declared at file
/// scope so it inherits no actor isolation from the test class.
private final class OrderRecorder {
    var order: [Int] = []
}

/// A controller whose class name is unmistakable in a diagnostics string.
private final class ProbeViewController: UIViewController {}

/// `drainMainQueue` is load-bearing for two suites and is the fix for a class of
/// failure this project has hit twice (#618, #693) — yet it had no test of its
/// own. That matters more than usual here: if someone "simplifies" it into a
/// no-op, both suites keep passing on a quiet machine and the flake comes back
/// only in the nightly clean build, off the PR path, where nobody looks at it
/// for weeks. These tests fail on the spot instead.
@MainActor
final class MainQueueDrainTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The suite runs ~1000 tests before this one, and the first test that
        // spins the run loop pays for every block they left queued (#618). That
        // backlog belongs to nobody's assertion here, least of all the timing
        // one below, so spend it before the tests start rather than inside them.
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
    /// The budget is deliberately loose. `setUp` already drained, so the honest
    /// expectation is a single round trip, i.e. single-digit milliseconds; the
    /// 0.5 s the issue suggested is inside the noise of a three-core CI runner
    /// where one scheduling hiccup over the 0.1 s quiet threshold forces another
    /// turn of the loop, and that noise would show up as a flake with no defect
    /// behind it. What the assertion has to separate is "one round trip" from
    /// "burned the whole cap", and 5 s does that with a 6× margin on either side.
    func testDrainOfAQuietQueueReturnsWithoutSpendingTheCap() {
        let started = Date()
        XCTAssertTrue(drainMainQueue(cap: 30), "an already quiet queue must drain immediately")
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(
            elapsed, 5,
            "draining an already quiet queue took \(elapsed) s — it is spending the cap, not detecting quiet"
        )
    }

    // MARK: - Presentation diagnostics

    /// The failure text these tour suites print is the only thing that tells the
    /// next reader which of two different bugs they are looking at, so the empty
    /// case has to say so in words rather than print an empty chain.
    func testPresentationDiagnosticsNamesAnEmptyHierarchy() {
        XCTAssertEqual(
            presentationDiagnostics(rootedAt: nil),
            "presentation chain: no root view controller"
        )
    }

    /// Both halves matter: the concrete class (a chain of just the tab bar means
    /// the route never fired) and the attachment (`window: nil` means it fired
    /// at a presenter UIKit had already dropped).
    func testPresentationDiagnosticsNamesTheControllerAndItsAttachment() {
        let root = ProbeViewController()

        let text = presentationDiagnostics(rootedAt: root)

        XCTAssertTrue(
            text.contains("ProbeViewController"),
            "the chain must name the actual class, got: \(text)"
        )
        XCTAssertTrue(
            text.contains("window: nil"),
            "a controller outside any window must be reported as detached, got: \(text)"
        )
    }
}
