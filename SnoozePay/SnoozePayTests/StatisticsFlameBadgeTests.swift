import UIKit
import XCTest
@testable import SnoozePay

/// The statistics hero card's 56×56 flame badge must keep its fill under a
/// resize and through a theme flip (#529).
///
/// The badge used to be a plain `UIView` with a `CAGradientLayer` sublayer
/// whose frame was assigned exactly once:
///
/// ```swift
/// container.layoutIfNeeded()
/// DispatchQueue.main.async { gradient.frame = container.bounds }
/// ```
///
/// That renders today purely by coincidence — the badge is pinned to a fixed
/// 56×56 and gets that `layoutIfNeeded()` first — but a sublayer does not
/// auto-size, and the frame is never assigned again for the rest of the
/// layer's life. Any later resize leaves the gradient stale and the flame on
/// bare card. The same shape already shipped an invisible badge in the streak
/// modal (#516): the layer stayed at `.zero` and the glyph measured 1.01:1
/// dark / 1.16:1 light on the sheet fill.
///
/// **Why the obvious test would not catch it.** Asserting that the badge
/// renders on first layout passes against the broken code — that is the one
/// case the `layoutIfNeeded()` hop covers. So the geometry test below resizes
/// the badge *after* the initial pass, which is the actual defect.
///
/// **The window is load-bearing.** A detached view never receives the
/// trait-change callback, keeps its `init`-time resolution, and both themes
/// measure identical — the theme test would then pass against frozen colours.
/// The badge is a plain view, so the override goes on the WINDOW, and both
/// directions are skip-guarded so a harness that silently fails to flip cannot
/// assert the same theme twice. Since #520 the warn ramp itself no longer
/// differs per theme, so "both themes measure identical" stopped being a signal
/// *here* — see the theme test's own doc comment.
final class StatisticsFlameBadgeTests: XCTestCase {

    /// A deliberately different size to lay the badge out at — stands in for
    /// Dynamic Type, rotation, or a future adaptive badge.
    private let resizedSide: CGFloat = 96

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { window in window.subviews.forEach { $0.removeFromSuperview() } }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The defect: a gradient nobody re-sizes

    /// The fill still covers the badge after it is laid out at a new size.
    ///
    /// The fixed 56×56 constraints are what mask the bug in production, so the
    /// test drops them and pins the badge at a different size — the resize the
    /// `DispatchQueue.main.async` assignment can never follow. Written against
    /// "a gradient layer, wherever it lives" so it keeps measuring the defect
    /// rather than the shape of the fix.
    func testFlameBadgeFill_tracksTheBadgeAfterAResize() throws {
        let (badge, window) = makeHostedBadge(style: .dark)

        // Initial pass — the one case the old code got right.
        let firstPass = try XCTUnwrap(gradientLayer(of: badge), "the badge owns no gradient layer")
        XCTAssertEqual(
            fillRect(of: firstPass, in: badge), badge.bounds,
            "the fill does not cover the badge even on the first layout pass"
        )

        resize(badge, in: window, to: resizedSide)

        XCTAssertEqual(
            badge.bounds.size,
            CGSize(width: resizedSide, height: resizedSide),
            "the harness failed to resize the badge — a harness fact, not a component one"
        )
        let gradient = try XCTUnwrap(gradientLayer(of: badge), "the badge lost its gradient layer")
        let fill = fillRect(of: gradient, in: badge)
        XCTAssertFalse(
            fill.isEmpty,
            "the gradient measures \(fill.size) after the resize"
        )
        XCTAssertEqual(
            fill, badge.bounds,
            "the gradient kept its \(fill.size) frame while the badge became "
            + "\(badge.bounds.size) — a CAGradientLayer added as a sublayer does not auto-size, "
            + "and a one-shot DispatchQueue.main.async assignment never runs again"
        )

        // The point of the fill is to be under the ink.
        let glyph = try XCTUnwrap(glyphView(in: badge), "the badge lost its flame glyph")
        XCTAssertTrue(
            fill.contains(glyph.center),
            "the fill (\(fill)) is not under the glyph (\(glyph.frame)) — "
            + "the ink is landing on the bare card"
        )
        XCTAssertFalse(
            (gradient.colors ?? []).isEmpty,
            "the gradient is sized but carries no stops"
        )
    }

    // MARK: - Surviving a theme flip

    /// `CAGradientLayer.colors` holds plain `CGColor`, which never re-resolves
    /// itself. The badge has to land on the ramp the design system defines,
    /// through a flip in both directions.
    ///
    /// **This test got weaker in #520 and it is worth knowing why.** It used to
    /// assert `inDark != inLight`, which was the whole point: a frozen ramp is
    /// observable exactly when the correct ramps differ. Splitting warn into ink
    /// and fill made the fill ramp the canon amber in BOTH themes, so this
    /// badge's stops are now legitimately identical and there is nothing left
    /// here to freeze. The flip assertions below are kept — they still catch a
    /// badge that re-tints to the *wrong* thing — but the CGColor-baking class
    /// itself is now measured by the money/pain cases in
    /// `SPCardGradientThemeTests`, not here.
    func testFlameBadgeRamp_staysOnTheDesignSystemRampAcrossAFlip() throws {
        let (badge, window) = makeHostedBadge(style: .dark)
        try XCTSkipUnless(
            badge.traitCollection.userInterfaceStyle == .dark,
            "window override did not propagate — a harness fact, not a component one"
        )

        let inDark = stops(of: badge)
        try XCTSkipUnless(!inDark.isEmpty, "the badge installed no gradient stops at all")

        window.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        try XCTSkipUnless(
            badge.traitCollection.userInterfaceStyle == .light,
            "window override did not propagate — a harness fact, not a component one"
        )

        XCTAssertEqual(
            inDark,
            SPSupport.warnGradientColors(for: UITraitCollection(userInterfaceStyle: .dark))
                .map { hex($0) },
            "the badge built itself off something other than the dark warn ramp"
        )

        let inLight = stops(of: badge)
        XCTAssertEqual(
            inLight,
            SPSupport.warnGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
                .map { hex($0) },
            "the badge re-tinted to something other than the light warn ramp"
        )

        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        try XCTSkipUnless(
            badge.traitCollection.userInterfaceStyle == .dark,
            "window override did not propagate — a harness fact, not a component one"
        )
        XCTAssertEqual(stops(of: badge), inDark, "the badge did not return to the dark ramp")
    }

    // MARK: - Fixtures

    /// The badge exactly as the statistics card builds it, hosted in a window
    /// so trait changes actually reach it.
    private func makeHostedBadge(style: UIUserInterfaceStyle) -> (badge: UIView, window: UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        // On the WINDOW: the badge is a plain view, not a controller's root,
        // and it is added straight to the window so nothing sits between the
        // override and the trait-change callback under test.
        window.overrideUserInterfaceStyle = style
        hostWindows.append(window)

        // Typed as `UIView` on purpose: every assertion below reads the badge
        // through the plain-view surface, so the test cannot start depending
        // on the concrete type the fix happens to use.
        let badge: UIView = StatisticsViewController().makeFlameBadge()
        window.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: window.centerYAnchor)
        ])
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return (badge, window)
    }

    /// Lay the badge out at `side` instead of its design size.
    ///
    /// The 56×56 constraints the badge owns are exactly what hides the bug in
    /// production, so they are dropped rather than fought with — a conflicting
    /// required constraint resolves arbitrarily and would make the assertion
    /// mean nothing.
    private func resize(_ badge: UIView, in window: UIWindow, to side: CGFloat) {
        let fixedSize = badge.constraints.filter {
            ($0.firstAttribute == .width || $0.firstAttribute == .height) && $0.secondItem == nil
        }
        NSLayoutConstraint.deactivate(fixedSize)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: side),
            badge.heightAnchor.constraint(equalToConstant: side)
        ])
        window.setNeedsLayout()
        window.layoutIfNeeded()
        badge.setNeedsLayout()
        badge.layoutIfNeeded()
    }

    // MARK: - Reading the rendered badge

    /// The badge's gradient, whether it is the view's own layer or a sublayer.
    private func gradientLayer(of view: UIView) -> CAGradientLayer? {
        if let own = view.layer as? CAGradientLayer { return own }
        return view.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
    }

    /// The painted rect expressed in the badge's own coordinate space, so both
    /// arrangements are comparable against `bounds` and against the glyph.
    ///
    /// `layer.frame` is stated in SUPERlayer coordinates: for the view's own
    /// layer that is the badge's position inside the window, which would never
    /// equal `bounds`. For a sublayer it is already badge-space, and a stale
    /// one reports the size it was frozen at — which is the whole defect.
    private func fillRect(of gradient: CAGradientLayer, in badge: UIView) -> CGRect {
        guard gradient !== badge.layer else { return badge.bounds }
        return badge.layer.convert(gradient.bounds, from: gradient)
    }

    private func glyphView(in badge: UIView) -> UIImageView? {
        badge.subviews.compactMap { $0 as? UIImageView }.first
    }

    private func stops(of badge: UIView) -> [UInt32] {
        guard let gradient = gradientLayer(of: badge) else { return [] }
        var found: [UInt32] = []
        for case let color as CGColor in gradient.colors ?? [] {
            found.append(hex(color))
        }
        return found
    }

    private func hex(_ color: CGColor) -> UInt32 {
        let uiColor = UIColor(cgColor: color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(uiColor)")
            return 0
        }
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(red) << 16) | (toByte(green) << 8) | toByte(blue)
    }
}
