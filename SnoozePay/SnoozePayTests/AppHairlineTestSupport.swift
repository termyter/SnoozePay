import UIKit
import XCTest
@testable import SnoozePay

extension AppHairlineTests {

    /// A real window, because a detached view's trait collection is not the
    /// one it will draw with.
    func hostedView() -> UIView {
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

    /// Overrides the scale on a view that has **no window**, lays it out
    /// through its container, and asserts the divider followed.
    ///
    /// The `XCTAssertEqual` on `before` is not padding: everything below
    /// measures the difference an upgrade makes, so a fixture that has
    /// already been laid out would compare two identical numbers and blame
    /// the production code for it.
    func assertOffWindowLayoutUpgradesTheDivider<View: UIView>(
        of view: View,
        laidOutBy container: UIView,
        constraint: (View) -> NSLayoutConstraint?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNil(
            container.window,
            "the container is in a window, so a restored `window != nil` guard would pass here "
                + "and this would measure nothing",
            file: file, line: line
        )

        let before = try XCTUnwrap(constraint(view), file: file, line: line).constant
        XCTAssertEqual(
            before, AppHairline.provisionalWidth, accuracy: 0.0001,
            "fixture broken: the view was laid out already, so there is no upgrade left to measure",
            file: file, line: line
        )

        let scale = scaleWhoseHairlineDiffersFromTheProvisionalWidth
        view.traitOverrides.displayScale = scale
        applyTraitOverrides(expecting: scale, on: view)
        container.setNeedsLayout()
        container.layoutIfNeeded()

        let height = try XCTUnwrap(constraint(view), file: file, line: line)
        XCTAssertEqual(
            height.constant, 1.0 / scale, accuracy: 0.0001,
            """
            an off-window layout pass left the divider at \(height.constant)pt where the \
            view's own traits call for \(1.0 / scale)pt — a `window != nil` guard is back in \
            layoutSubviews, and never-hosted views keep the provisional width in silence
            """,
            file: file, line: line
        )
    }

    /// A display scale whose hairline is *not* the provisional width, so an
    /// upgrade from one to the other is observable.
    ///
    /// Derived rather than written down: the answer flips whenever
    /// `AppHairline.provisionalWidth` changes, and a hard-coded scale is how
    /// an upgrade test quietly stops testing the upgrade. Both scales iOS
    /// ships are candidates; one of them always differs, because two distinct
    /// hairlines cannot both equal one constant.
    var scaleWhoseHairlineDiffersFromTheProvisionalWidth: CGFloat {
        let atTwo = AppHairline.width(
            for: UITraitCollection { mutableTraits in mutableTraits.displayScale = 2 }
        )
        return abs(atTwo - AppHairline.provisionalWidth) > 0.0001 ? 2 : 3
    }

    /// The cell's divider is private too. It is the one view *flush* with the
    /// bottom of `contentView` — an equality pin at zero. The text stack also
    /// carries a bottom constraint (`lessThanOrEqualTo`, −14), so the relation
    /// and the constant are part of the predicate rather than left to the
    /// type filter: swap that stack for a plain container in some future
    /// refactor and a type-only filter would hand back the wrong view.
    ///
    /// Discriminating this way rather than on the tile's 36pt size also keeps
    /// a production literal out of the test — resizing the tile would
    /// otherwise redden this with a wrong diagnosis. Then look for the height
    /// constraint in both places a single-item constraint can be filed.
    func dividerHeightConstraint(of cell: SoundPickerRowCell) -> NSLayoutConstraint? {
        let plainViews = cell.contentView.subviews.filter {
            !($0 is UIStackView) && !($0 is UIImageView)
        }
        guard let divider = plainViews.first(where: { view in
            cell.contentView.constraints.contains {
                ($0.firstItem as? UIView) === view
                    && $0.firstAttribute == .bottom
                    && $0.relation == .equal
                    && abs($0.constant) < 0.0001
                    && ($0.secondItem as? UIView) === cell.contentView
            }
        }) else { return nil }
        let candidates = divider.constraints + cell.contentView.constraints
        return candidates.first {
            ($0.firstItem as? UIView) === divider
                && $0.firstAttribute == .height
                && $0.secondItem === nil
        }
    }

    /// `divider` is private, so find its height constraint the way the row
    /// declares it: a constant-height constraint on the one subview that is
    /// not the content stack. A single-item constraint is installed on that
    /// view itself, not on the row, so look in both places rather than
    /// assuming where UIKit filed it.
    func dividerHeightConstraint(of row: SPRow) -> NSLayoutConstraint? {
        guard let divider = row.subviews.first(where: { !($0 is UIStackView) }) else { return nil }
        let candidates = divider.constraints + row.constraints
        return candidates.first {
            ($0.firstItem as? UIView) === divider
                && $0.firstAttribute == .height
                && $0.secondItem === nil
        }
    }

    /// Applies a pending `traitOverrides` write and asserts it landed.
    ///
    /// **Not an optional check — the tests do not work without it.** None of
    /// the callers run a layout pass after writing the override, so this call
    /// is the only thing that applies it; delete it as a redundant assertion
    /// and the tests below go back to measuring the pre-override scale, in
    /// silence. Hence the imperative name.
    ///
    /// The assertion half is deliberately fatal rather than a skip: if trait
    /// overrides stop propagating for some other reason, these tests measure
    /// nothing and have to say so in red instead of quietly not running.
    ///
    /// `updateTraitsIfNeeded()` is not defensive padding — it is the whole
    /// reason this file used to be skipped. A write to `traitOverrides` is
    /// applied on the next update cycle, not at assignment, so reading
    /// `traitCollection` on the next line returns the *old* scale. On a @3x
    /// simulator an override to @3x is indistinguishable from no override at
    /// all, which is why one test in this file passed while three failed:
    /// only the three overriding *downward* could see the difference. The
    /// original `XCTSkipUnless` read that as "this harness cannot override
    /// scales" and stepped aside; it was a missing update call.
    func applyTraitOverrides(
        expecting expected: CGFloat,
        on view: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        view.updateTraitsIfNeeded()
        XCTAssertEqual(
            view.traitCollection.displayScale, expected, accuracy: 0.0001,
            """
            fixture broken: traitOverrides.displayScale did not propagate \
            (view reports @\(view.traitCollection.displayScale)x, expected @\(expected)x). \
            Nothing below this line is being measured.
            """,
            file: file, line: line
        )
    }
}
