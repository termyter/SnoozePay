import Foundation
import UIKit
import XCTest

// Cover for the shared presentation diagnostics (#698).

/// Lets the chain be built without presenting anything. A real
/// `present(_:animated:)` into a scene-less window is at UIKit's discretion,
/// which would make this test a coin flip; overriding the one property the
/// walk reads keeps it deterministic and still exercises the real walk.
private final class StubPresenter: UIViewController {
    var stubPresented: UIViewController?
    override var presentedViewController: UIViewController? { stubPresented }
}

/// A controller whose class name is unmistakable in a diagnostics string.
private final class ProbeViewController: UIViewController {}

/// This string is the only thing that tells the next reader which of two bugs
/// they are looking at when a tour route fails to present (#618, #693), so the
/// parts that carry that meaning — the walk down the chain, the separator, and
/// the per-node attachment — are each pinned here.
///
/// `@MainActor` spelled out rather than inherited from
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: these tests build and touch
/// view controllers, and that has to stay a compile-time guarantee rather than
/// a property of the build settings.
@MainActor
final class PresentationDiagnosticsTests: XCTestCase {

    func testAnEmptyHierarchyIsNamedInWords() {
        XCTAssertEqual(
            presentationDiagnostics(rootedAt: nil),
            "presentation chain: no root view controller"
        )
    }

    /// A controller whose view was never loaded cannot be on screen, and the
    /// string has to say so rather than leave the reader guessing.
    func testAnUnloadedControllerIsReportedAsDetached() {
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

    /// The test the first round of this PR was missing: without it, deleting
    /// the `current = node.presentedViewController` step leaves every other
    /// assertion green while "presentation chain" stops describing a chain.
    ///
    /// It also covers the two states side by side — a presenter that IS in a
    /// window and a sheet that is loaded but attached to nothing, which is the
    /// scenario the docblock calls "UIKit dropped it on the floor", rather than
    /// the weaker "its view was never loaded".
    func testTheWalkFollowsThePresentationChainAndReportsEachNodesAttachment() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = StubPresenter()
        window.addSubview(root.view)
        let sheet = ProbeViewController()
        // Loaded, then deliberately left out of any window.
        sheet.loadViewIfNeeded()
        root.stubPresented = sheet

        let text = presentationDiagnostics(rootedAt: root)

        XCTAssertEqual(
            text,
            "presentation chain: \(type(of: root))(window: set) → \(type(of: sheet))(window: nil)",
            "the walk must reach the presented controller and score attachment per node"
        )
    }
}
