import UIKit
import XCTest
@testable import SnoozePay

/// ``AppHairline`` is the single place that turns a display scale into a
/// line width. Twelve sites used to spell that arithmetic out by hand (#689).
///
/// The value itself is trivial; what these tests pin is *where the scale comes
/// from*. A hairline resolved once against `UIScreen.main` looks right on the
/// only display a simulator has and is wrong everywhere else — the same shape
/// of defect this project already hit with `cgColor`s baked from another
/// screen's traits. So the contract asserted here is that the width follows
/// the trait collection it is handed, including one overridden per-view.
final class AppHairlineTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - The value

    /// One device pixel, expressed in points, at each scale UIKit ships.
    func testWidth_isExactlyOneDevicePixel_atEveryScale() {
        for scale in [CGFloat(1), 2, 3] {
            let trait = UITraitCollection { mutableTraits in mutableTraits.displayScale = scale }
            XCTAssertEqual(
                AppHairline.width(for: trait), 1.0 / scale, accuracy: 0.0001,
                "a hairline at @\(scale)x has to be 1/\(scale)pt"
            )
        }
    }

    /// A trait collection that has never met a screen reports `displayScale`
    /// of 0. Dividing by it yields infinity, so the guard has to produce a
    /// line that is *drawable* — 1pt, thicker than intended but visible —
    /// rather than one that is absent or infinite.
    func testWidth_fallsBackToADrawableLine_whenTheTraitCarriesNoScale() {
        let width = AppHairline.width(for: UITraitCollection { mutableTraits in mutableTraits.displayScale = 0 })
        XCTAssertEqual(width, 1, accuracy: 0.0001, "no scale must degrade to a plain 1pt line")
        XCTAssertTrue(width.isFinite, "a hairline width of \(width) draws nothing")
    }

    // MARK: - Where the scale comes from

    /// The property reads the view's own traits, not a global. Asserted by
    /// overriding the scale on a hosted view to something the host screen is
    /// not: a helper wired to `UIScreen.main` returns the window's scale here
    /// and fails.
    func testHairlineWidth_followsTheViewsOwnScale_notTheScreens() throws {
        let view = hostedView()
        let screenScale = view.traitCollection.displayScale
        let otherScale: CGFloat = screenScale == 2 ? 3 : 2

        view.traitOverrides.displayScale = otherScale
        try XCTSkipUnless(
            view.traitCollection.displayScale == otherScale,
            "the trait override did not propagate — a harness fact, not a component one"
        )

        XCTAssertEqual(
            view.hairlineWidth, 1.0 / otherScale, accuracy: 0.0001,
            """
            the view reports a \(view.hairlineWidth)pt hairline while its own traits say \
            @\(otherScale)x — the width is coming from somewhere other than this view
            """
        )
        XCTAssertNotEqual(
            view.hairlineWidth, 1.0 / screenScale, accuracy: 0.0001,
            "the width still tracks the screen's @\(screenScale)x"
        )
    }

    /// Subviews inherit the scale, so a card's chrome and a divider nested
    /// inside it can never disagree by construction.
    func testHairlineWidth_isInheritedBySubviews() throws {
        let parent = hostedView()
        let child = UIView()
        parent.addSubview(child)

        parent.traitOverrides.displayScale = 3
        try XCTSkipUnless(
            child.traitCollection.displayScale == 3,
            "the trait override did not reach the subview — a harness fact"
        )
        XCTAssertEqual(
            child.hairlineWidth, parent.hairlineWidth, accuracy: 0.0001,
            "a nested view draws a different hairline than the surface around it"
        )
    }

    /// The property is computed, never cached: moving between displays of
    /// different scale has to change what the next themed pass reads.
    func testHairlineWidth_isRecomputed_whenTheScaleChanges() throws {
        let view = hostedView()

        view.traitOverrides.displayScale = 2
        try XCTSkipUnless(view.traitCollection.displayScale == 2, "override did not propagate")
        let atTwo = view.hairlineWidth

        view.traitOverrides.displayScale = 3
        try XCTSkipUnless(view.traitCollection.displayScale == 3, "override did not propagate")
        let atThree = view.hairlineWidth

        XCTAssertEqual(atTwo, 0.5, accuracy: 0.0001)
        XCTAssertEqual(atThree, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertNotEqual(atTwo, atThree, accuracy: 0.0001, "the width was baked, not read")
    }

    // MARK: - Fixtures

    /// A real window, because a detached view's trait collection is not the
    /// one it will draw with.
    private func hostedView() -> UIView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        hostWindows.append(window)

        let view = UIView(frame: CGRect(x: 0, y: 0, width: 343, height: 52))
        host.view.addSubview(view)
        window.layoutIfNeeded()
        return view
    }
}
