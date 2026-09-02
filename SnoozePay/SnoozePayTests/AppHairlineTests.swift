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
    /// that asymmetry is the entire reason it exists. 0.5pt is one pixel at
    /// @2x and half a pixel at @3x; anything ≥ 1pt reads as a deliberate rule.
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
    /// about: whether a view built outside a window reports a usable scale.
    ///
    /// It is load-bearing rather than trivia. `width(for:)` traps on a zero
    /// scale, and production builds views detached all the time, so if this
    /// ever goes red the `assertionFailure` is a landmine across the app and
    /// every detached construction site needs the provisional width instead.
    func testADetachedView_reportsAUsableDisplayScale() {
        let scale = UIView().traitCollection.displayScale
        XCTAssertGreaterThan(
            scale, 0,
            """
            a detached UIView reports displayScale \(scale) — the app resolves hairlines \
            from views built outside a window, so every such site has to switch to \
            AppHairline.provisionalWidth
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
        assertScale(otherScale, of: view)

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
        assertScale(2, of: parent)
        assertScale(3, of: child)

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
        assertScale(2, of: view)
        let atTwo = view.hairlineWidth

        view.traitOverrides.displayScale = 3
        assertScale(3, of: view)
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
        // @3x, so the expected value (1/3) differs from the provisional 0.5 —
        // on an @2x host the two coincide and the assertion would pass without
        // the upgrade ever happening.
        row.traitOverrides.displayScale = 3
        assertScale(3, of: row)
        row.setNeedsLayout()
        window.layoutIfNeeded()

        let height = try XCTUnwrap(dividerHeightConstraint(of: row))
        XCTAssertEqual(
            height.constant, 1.0 / 3.0, accuracy: 0.0001,
            """
            the hosted row kept a \(height.constant)pt divider where its own traits call \
            for \(1.0 / 3.0)pt — the provisional constant was never re-read
            """
        )
        XCTAssertNotEqual(
            height.constant, AppHairline.provisionalWidth, accuracy: 0.0001,
            "the divider is still sitting at the pre-screen width"
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

    /// The harness guard, deliberately fatal rather than a skip: if trait
    /// overrides stop propagating, these tests measure nothing and have to say
    /// so in red instead of quietly not running.
    private func assertScale(
        _ expected: CGFloat,
        of view: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
