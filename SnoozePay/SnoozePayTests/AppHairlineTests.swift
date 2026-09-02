import UIKit
import XCTest
@testable import SnoozePay

/// ``AppHairline`` is the single place that turns a display scale into a line
/// width. Twelve sites used to spell that arithmetic out by hand (#689), and
/// no test in this target pinned the resulting value anywhere — the nearest
/// ones (`CreateAlarmLightThemeTests`) assert only that a border exists and
/// that its colour differs by theme.
///
/// Two things are pinned here, and neither is the arithmetic:
///
/// 1. **Where the scale comes from.** A hairline resolved once against
///    `UIScreen.main` looks right on the only display a simulator has and is
///    wrong everywhere else — the same shape of defect this project already
///    hit with `cgColor`s baked from another screen's traits. So the width has
///    to follow the trait collection it is handed, including one overridden
///    per view.
/// 2. **That nothing freezes a full point.** `SPRow` builds its divider
///    constraint from `init`, before the row has a window; a fallback of 1pt
///    frozen there is two to three device pixels, which on a screenshot is
///    indistinguishable from a divider drawn on purpose.
///
/// No `XCTSkipUnless` here on purpose (#568): a guard that fires on every run
/// is indistinguishable from a test that was never written, and `ci.yml`
/// discards `TestResults.xcresult` on green runs, so nobody would ever see the
/// skip counter. A harness that stops propagating trait overrides has to say
/// so in red.
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

    /// The degenerate branch is asserted by its constant rather than by
    /// calling it: `width(for:)` traps on `displayScale == 0` by design, so
    /// invoking it here would abort the suite instead of measuring anything.
    /// What matters is that the value it would return is drawable at all.
    func testDegenerateWidth_isADrawableLine() {
        XCTAssertTrue(AppHairline.degenerateWidth.isFinite, "an infinite width draws nothing")
        XCTAssertGreaterThan(AppHairline.degenerateWidth, 0)
        XCTAssertEqual(AppHairline.degenerateWidth, 1, accuracy: 0.0001)
    }

    /// The pre-screen width may never be *thicker* than a real hairline —
    /// that asymmetry is the entire reason it exists. 1/3pt is one device
    /// pixel at @3x and two thirds of one at @2x, so it errs thin on every
    /// display iOS ships; anything ≥ 1pt reads as a deliberate rule.
    ///
    /// Round 2 of #689 shipped 0.5 here with a docstring calling it "half a
    /// pixel at @3x". It is one and a half, and this test is what said so.
    func testProvisionalWidth_isNeverThickerThanARealHairline() {
        XCTAssertLessThan(
            AppHairline.provisionalWidth, 1.0,
            "a provisional hairline of \(AppHairline.provisionalWidth)pt is a visible divider"
        )
        for scale in [CGFloat(2), 3] {
            let real = AppHairline.width(
                for: UITraitCollection { mutableTraits in mutableTraits.displayScale = scale }
            )
            XCTAssertLessThanOrEqual(
                AppHairline.provisionalWidth, real + 0.0001,
                "the provisional width is thicker than a true hairline at @\(scale)x"
            )
        }
    }

    // MARK: - Where the scale comes from

    /// Settles, in code, the fact two comments in this repository disagreed
    /// about: what a view built outside a window reports as its scale. The
    /// deleted comment at `SPRow` said "`displayScale` is `0` until the view
    /// is in a window"; this pins the answer instead of asserting around it.
    ///
    /// `> 0` alone was not enough. Two live decisions rest on the stronger
    /// statement, and neither survives if a detached view answers differently
    /// from a hosted one:
    ///
    /// - `layoutSubviews` in ``SPRow`` and `SoundPickerRowCell` re-reads the
    ///   width **unconditionally**. A `window != nil` guard there would leave
    ///   the provisional value frozen with no log and no assertion; it is
    ///   omitted precisely because this test says the off-window read is the
    ///   same read.
    /// - `width(for:)` traps on a zero scale, and production builds views
    ///   detached all the time. Red here means that `assertionFailure` is a
    ///   landmine across the app.
    ///
    /// What it does *not* underwrite is the value of `provisionalWidth`: that
    /// follows from "never thicker than a real hairline" alone, and is pinned
    /// by `testProvisionalWidth_isNeverThickerThanARealHairline`.
    func testADetachedView_reportsTheSameScaleAsAHostedOne() {
        let detached = UIView().traitCollection.displayScale
        XCTAssertGreaterThan(
            detached, 0,
            """
            a detached UIView reports displayScale \(detached) — `layoutSubviews` in SPRow \
            and SoundPickerRowCell now re-reads the width unconditionally, so the very next \
            off-window layout pass hits AppHairline.width(for:)'s degenerate branch and its \
            assertionFailure takes down the whole test host. Restore the `window != nil` \
            guards before anything else.
            """
        )

        let hosted = hostedView().traitCollection.displayScale
        XCTAssertEqual(
            detached, hosted, accuracy: 0.0001,
            """
            a detached view reports @\(detached)x while a hosted one reports @\(hosted)x — \
            reading a hairline before a view has a window is no longer equivalent to reading \
            it after, so `layoutSubviews` in SPRow and SoundPickerRowCell has to go back to \
            skipping the off-window pass, and every detached construction site needs \
            AppHairline.provisionalWidth rather than the view's own traits
            """
        )
    }

    /// The property reads the view's own traits, not a global. Asserted by
    /// overriding the scale on a hosted view to something the host screen is
    /// not: an implementation wired to `UIScreen.main` returns the window's
    /// scale here and fails.
    func testHairlineWidth_followsTheViewsOwnScale_notTheScreens() {
        let view = hostedView()
        let screenScale = view.traitCollection.displayScale
        let otherScale: CGFloat = screenScale == 2 ? 3 : 2

        view.traitOverrides.displayScale = otherScale
        applyTraitOverrides(expecting: otherScale, on: view)

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

    /// Two views in one hierarchy, each carrying a different scale: each has
    /// to answer with its own. A shared global returns one number for both,
    /// and an implementation that reads the parent returns the parent's.
    func testHairlineWidth_isResolvedPerView_whenParentAndChildDisagree() {
        let parent = hostedView()
        let child = UIView()
        parent.addSubview(child)

        parent.traitOverrides.displayScale = 2
        child.traitOverrides.displayScale = 3
        applyTraitOverrides(expecting: 2, on: parent)
        applyTraitOverrides(expecting: 3, on: child)

        XCTAssertEqual(parent.hairlineWidth, 0.5, accuracy: 0.0001, "the parent answered @3x")
        XCTAssertEqual(
            child.hairlineWidth, 1.0 / 3.0, accuracy: 0.0001,
            "the child answered its parent's @2x instead of its own @3x"
        )
    }

    /// The property is computed, never cached: moving between displays of
    /// different scale has to change what the next themed pass reads.
    func testHairlineWidth_isRecomputed_whenTheScaleChanges() {
        let view = hostedView()

        view.traitOverrides.displayScale = 2
        applyTraitOverrides(expecting: 2, on: view)
        let atTwo = view.hairlineWidth

        view.traitOverrides.displayScale = 3
        applyTraitOverrides(expecting: 3, on: view)
        let atThree = view.hairlineWidth

        XCTAssertEqual(atTwo, 0.5, accuracy: 0.0001)
        XCTAssertEqual(atThree, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertNotEqual(atTwo, atThree, accuracy: 0.0001, "the width was baked, not read")
    }

    // MARK: - SPRow — the one site that builds its width before it has a screen

    /// Every production caller builds `SPRow` detached (`WalletViewController`,
    /// `ReferralViewController`, `WalletTransactionHistoryViewController`,
    /// `SoundPickerViewController`, `VolumePickerViewController`), and the row
    /// activates the divider constraint from `init`. Whatever that constant
    /// starts at is what a row that is never laid out in a window keeps, so it
    /// must not be a full point.
    func testDetachedRow_neverBuildsAPointThickDivider() throws {
        let row = SPRow(title: "Звук", divider: true)
        let height = try XCTUnwrap(
            dividerHeightConstraint(of: row),
            "the divider's height constraint is gone — this test no longer measures anything"
        )
        XCTAssertLessThan(
            height.constant, 1.0,
            """
            a row built outside a window froze a \(height.constant)pt divider — that is \
            2–3 device pixels and reads as a deliberate rule, not a hairline
            """
        )
    }

    /// …and once the row has a screen, the provisional value is replaced by
    /// the real one. A provisional width that is never re-read is just a wrong
    /// width with a nicer name.
    func testHostedRow_upgradesTheDividerToItsScreensHairline() throws {
        let row = SPRow(title: "Звук", divider: true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        hostWindows.append(window)
        host.view.addSubview(row)
        // `SPRow` owns its autoresizing flag (#584), so it needs real
        // constraints — a row with no width is never laid out and the upgrade
        // this test is about would not run.
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: host.view.topAnchor),
            row.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.view.trailingAnchor)
        ])
        // The override has to land on a scale whose hairline differs from the
        // provisional width, or "upgraded" and "never touched" are the same
        // number and the assertions pass without the upgrade happening. Which
        // scale that is depends on the constant, so derive it instead of
        // hard-coding: at 1/3 an @3x override is the no-op, at 0.5 an @2x one.
        let scale = scaleWhoseHairlineDiffersFromTheProvisionalWidth
        let before = try XCTUnwrap(dividerHeightConstraint(of: row)).constant
        XCTAssertEqual(
            before, AppHairline.provisionalWidth, accuracy: 0.0001,
            "fixture broken: the row was laid out already, so there is no upgrade left to measure"
        )
        row.traitOverrides.displayScale = scale
        applyTraitOverrides(expecting: scale, on: row)
        row.setNeedsLayout()
        window.layoutIfNeeded()

        let height = try XCTUnwrap(dividerHeightConstraint(of: row))
        XCTAssertEqual(
            height.constant, 1.0 / scale, accuracy: 0.0001,
            """
            the hosted row kept a \(height.constant)pt divider where its own traits call \
            for \(1.0 / scale)pt — the provisional constant was never re-read
            """
        )
        XCTAssertNotEqual(
            height.constant, before, accuracy: 0.0001,
            "the divider still holds the width it was built with (\(before)pt)"
        )
    }

    /// The off-window layout pass — the one a `window != nil` guard would
    /// skip, and the only thing that makes its absence observable.
    ///
    /// Without this, restoring `guard window != nil` leaves every other test
    /// in this file green: the hosted ones lay out inside a key window, where
    /// the guard passes, and the detached ones never lay out at all. Round 5
    /// removed those guards and claimed the hosted tests pinned the removal.
    /// They did not — this does.
    func testDetachedRow_upgradesTheDivider_whenLaidOutWithoutAWindow() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 343, height: 52))
        let row = SPRow(title: "Звук", divider: true)
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        try assertOffWindowLayoutUpgradesTheDivider(
            of: row, laidOutBy: container, constraint: { self.dividerHeightConstraint(of: $0) }
        )
    }

    // MARK: - SoundPickerRowCell — the same pattern, one screen over

    /// `SoundPickerRowCell` builds the identical divider constraint before it
    /// has a screen, and #689 folded it onto the same constant, so it gets the
    /// same tests as ``SPRow``. A full point frozen at construction is 2–3
    /// device pixels — a deliberate-looking rule rather than a hairline.
    func testDetachedCell_neverBuildsAPointThickDivider() throws {
        let cell = SoundPickerRowCell(style: .default, reuseIdentifier: SoundPickerRowCell.reuseID)
        let height = try XCTUnwrap(
            dividerHeightConstraint(of: cell),
            "the divider's height constraint is gone — this test no longer measures anything"
        )
        XCTAssertLessThan(
            height.constant, 1.0,
            """
            a cell built outside a window froze a \(height.constant)pt divider — that is \
            2–3 device pixels and reads as a deliberate rule, not a hairline
            """
        )
    }

    /// …and the re-read happens for the cell too. `layoutSubviews` there is
    /// deliberately not guarded on `window != nil`, so this also pins that the
    /// unguarded read returns a real number rather than tripping the
    /// degenerate branch of `AppHairline.width(for:)`.
    func testHostedCell_upgradesTheDividerToItsScreensHairline() throws {
        let cell = SoundPickerRowCell(style: .default, reuseIdentifier: SoundPickerRowCell.reuseID)
        cell.frame = CGRect(x: 0, y: 0, width: 343, height: 64)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        hostWindows.append(window)
        host.view.addSubview(cell)

        let scale = scaleWhoseHairlineDiffersFromTheProvisionalWidth
        let before = try XCTUnwrap(dividerHeightConstraint(of: cell)).constant
        XCTAssertEqual(
            before, AppHairline.provisionalWidth, accuracy: 0.0001,
            "fixture broken: the cell was laid out already, so there is no upgrade left to measure"
        )
        cell.traitOverrides.displayScale = scale
        applyTraitOverrides(expecting: scale, on: cell)
        cell.setNeedsLayout()
        window.layoutIfNeeded()

        let height = try XCTUnwrap(dividerHeightConstraint(of: cell))
        XCTAssertEqual(
            height.constant, 1.0 / scale, accuracy: 0.0001,
            """
            the hosted cell kept a \(height.constant)pt divider where its own traits call \
            for \(1.0 / scale)pt — the provisional constant was never re-read
            """
        )
        XCTAssertNotEqual(
            height.constant, before, accuracy: 0.0001,
            "the divider still holds the width it was built with (\(before)pt)"
        )
    }

    /// The same for the cell. `SoundPickerViewController` sets
    /// `rowHeight = .automaticDimension`, so the cell's height comes from a
    /// measuring pass; whether UIKit runs that pass before or after the cell
    /// joins the window is undocumented, which is the reason the re-read may
    /// not depend on it — and the reason this test exists.
    func testDetachedCell_upgradesTheDivider_whenLaidOutWithoutAWindow() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 343, height: 64))
        let cell = SoundPickerRowCell(style: .default, reuseIdentifier: SoundPickerRowCell.reuseID)
        cell.frame = container.bounds
        container.addSubview(cell)
        try assertOffWindowLayoutUpgradesTheDivider(
            of: cell, laidOutBy: container, constraint: { self.dividerHeightConstraint(of: $0) }
        )
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

    /// Overrides the scale on a view that has **no window**, lays it out
    /// through its container, and asserts the divider followed.
    ///
    /// The `XCTAssertEqual` on `before` is not padding: everything below
    /// measures the difference an upgrade makes, so a fixture that has
    /// already been laid out would compare two identical numbers and blame
    /// the production code for it.
    private func assertOffWindowLayoutUpgradesTheDivider<View: UIView>(
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
    private var scaleWhoseHairlineDiffersFromTheProvisionalWidth: CGFloat {
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
    private func dividerHeightConstraint(of cell: SoundPickerRowCell) -> NSLayoutConstraint? {
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
    private func dividerHeightConstraint(of row: SPRow) -> NSLayoutConstraint? {
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
    private func applyTraitOverrides(
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
