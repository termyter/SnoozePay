import UIKit
import XCTest
@testable import SnoozePay

/// The "alarm off" warning sheet's 80×80 hero badge must keep its fill under a
/// resize and through a theme flip (#536).
///
/// The badge used to be a plain `UIView` with a `CAGradientLayer` sublayer
/// whose frame was assigned exactly once, and not even synchronously:
///
/// ```swift
/// badge.layer.insertSublayer(gradient, at: 0)
/// DispatchQueue.main.async { gradient.frame = badge.bounds }
/// ```
///
/// A sublayer does not auto-size. The hop happened to land on the first frame
/// on device — the badge is pinned to a fixed 80×80 — but the frame was never
/// assigned again for the rest of the layer's life, so any later resize left
/// the fill stale and the flame on the bare sheet. The identical shape already
/// shipped an invisible badge twice: the streak modal (#516, measured 1.01:1
/// dark / 1.16:1 light on the sheet fill) and the statistics hero card (#529).
///
/// **Why the obvious tests would not hold.**
///
/// - Asserting the *first* render is worth something here only by accident of
///   the async hop: a synchronous test never turns the main run loop, so on the
///   old code the block would not have run at all and the layer would measure
///   `.zero`. That is a true red, but it is red for a timing reason, not for
///   the resize reason the issue is about — so the geometry test below lays the
///   badge out at a *different* size after the first pass, which is the defect
///   proper.
/// - `layer.frame` is stated in SUPERlayer coordinates. For an `SPGradientView`
///   the gradient IS the view's layer, so its frame is the badge's position
///   inside its parent and would never equal `bounds`. A naive
///   `gradient.frame == badge.bounds` is therefore falsely red on correct code;
///   `fillRect(of:in:)` converts into the badge's own space instead.
/// - The window is load-bearing. A detached controller never receives the
///   trait-change callback, keeps its `viewDidLoad`-time resolution, and both
///   themes measure identical — the theme test would then pass against frozen
///   colours. Every flip is skip-guarded so a harness that silently fails to
///   flip cannot assert the same theme twice.
final class AlarmOffWarningHeroBadgeTests: XCTestCase {

    /// iPhone 15 Pro portrait — the reference frame the other layout suites in
    /// this target use.
    private let referenceSize = CGSize(width: 393, height: 852)
    /// The badge's design size, straight from `makeHero()`.
    private let designSide: CGFloat = 80
    /// A deliberately different size to lay the badge out at — stands in for
    /// Dynamic Type, rotation, or a future adaptive hero.
    private let resizedSide: CGFloat = 120

    /// Windows are retained for the lifetime of the test: a `UIWindow` nothing
    /// holds is free to deallocate mid-assertion and take the hierarchy with it.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.rootViewController = nil }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The defect: a gradient nobody re-sizes

    /// The fill still covers the badge after it is laid out at a new size.
    ///
    /// The fixed 80×80 constraints are exactly what masked the bug in
    /// production, so the test drops them and pins the badge at a different
    /// size rather than fighting them — a conflicting required constraint
    /// resolves arbitrarily and would make the assertion mean nothing.
    ///
    /// Written against "a gradient layer, wherever it lives" so it keeps
    /// measuring the defect rather than the shape of the fix.
    func testHeroBadgeFill_tracksTheBadgeAfterAResize() throws {
        let (sut, window) = try makeHostedSheet(style: .dark)
        let badge: UIView = sut.heroBadge

        // The initial pass — the one case the old async hop covered on device.
        XCTAssertEqual(
            badge.bounds.size,
            CGSize(width: designSide, height: designSide),
            "the badge itself did not lay out at its design size"
        )
        let firstPass = try XCTUnwrap(gradientLayer(of: badge), "the badge owns no gradient layer")
        XCTAssertEqual(
            fillRect(of: firstPass, in: badge), badge.bounds,
            "the fill does not cover the badge even on the first layout pass"
        )

        resize(badge, of: sut, in: window, to: resizedSide)

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
            + "the ink is landing on the bare sheet"
        )
        XCTAssertFalse(
            (gradient.colors ?? []).isEmpty,
            "the gradient is sized but carries no stops"
        )
    }

    /// The badge renders in both themes on the first pass.
    ///
    /// This is the cheap net, and on the pre-fix code it is red for its own
    /// reason: the frame came from a `DispatchQueue.main.async` block, and a
    /// synchronous test never turns the main run loop, so the layer would still
    /// measure `.zero` here.
    func testHeroBadgeFill_isSizedAndCoversTheGlyph_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let (sut, _) = try makeHostedSheet(style: style)
            let badge: UIView = sut.heroBadge

            let gradient = try XCTUnwrap(
                gradientLayer(of: badge),
                "the badge owns no gradient layer at all in \(style.name)"
            )
            let fill = fillRect(of: gradient, in: badge)
            XCTAssertFalse(
                fill.isEmpty,
                "the badge's gradient measures \(fill.size) in \(style.name) — "
                + "a sublayer frame set from a DispatchQueue.main.async hop is never assigned "
                + "in a synchronous test, and never re-assigned at all afterwards"
            )
            XCTAssertEqual(fill, badge.bounds, "the fill does not cover the badge in \(style.name)")

            let glyph = try XCTUnwrap(glyphView(in: badge), "the badge lost its flame glyph")
            XCTAssertFalse(glyph.frame.isEmpty, "the flame glyph did not lay out in \(style.name)")
            XCTAssertTrue(
                fill.contains(glyph.center),
                "the fill (\(fill)) is not under the glyph (\(glyph.frame)) in \(style.name)"
            )
        }
    }

    // MARK: - Surviving a theme flip

    /// `CAGradientLayer.colors` holds plain `CGColor`, which never re-resolves
    /// itself. The sheet has to re-apply the ramp from its trait-change
    /// registration — and land on the ramp the design system defines for the
    /// new theme, not merely on something different.
    func testHeroBadgeRamp_reresolvesOnAThemeFlip() throws {
        let (sut, window) = try makeHostedSheet(style: .dark)
        let badge: UIView = sut.heroBadge

        let inDark = stops(of: badge)
        try XCTSkipUnless(!inDark.isEmpty, "the badge installed no gradient stops at all")

        try flip(sut, in: window, to: .light)
        let inLight = stops(of: badge)
        XCTAssertNotEqual(
            inDark, inLight,
            "the badge kept its dark stops after the flip — a CGColor in "
            + "CAGradientLayer.colors never re-resolves itself"
        )
        XCTAssertEqual(
            inLight,
            SPSupport.painGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
                .map { hex($0) },
            "the badge re-tinted to something other than the light pain ramp"
        )

        try flip(sut, in: window, to: .dark)
        XCTAssertEqual(stops(of: badge), inDark, "the badge did not return to the dark ramp")
    }

    /// The pain-tinted drop shadow is the badge's other cached `cgColor`, and
    /// it is re-resolved by the same callback. Pinned separately so a fix that
    /// re-applies only the gradient does not read as complete.
    func testHeroBadgeShadow_reresolvesOnAThemeFlip() throws {
        let (sut, window) = try makeHostedSheet(style: .dark)
        let badge: UIView = sut.heroBadge

        let inDark = try XCTUnwrap(badge.layer.shadowColor, "the badge carries no shadow colour")
        try flip(sut, in: window, to: .light)

        let inLight = try XCTUnwrap(badge.layer.shadowColor, "the badge lost its shadow colour")
        XCTAssertEqual(
            hex(inLight),
            hex(AppColors.pain500.resolved(.light).cgColor),
            "the badge's shadow is not the light pain500 after the flip"
        )
        XCTAssertNotEqual(
            hex(inDark), hex(inLight),
            "the badge kept its dark shadow tint — #F4523F stays put where light pain500 "
            + "is #9F3529 unless the CGColor is re-resolved"
        )
    }

    // MARK: - Fixtures

    private typealias Hosted = (sut: AlarmOffWarningViewController, window: UIWindow)

    /// The sheet mounted in a sized window, laid out down to the badge.
    private func makeHostedSheet(style: UIUserInterfaceStyle) throws -> Hosted {
        let window = UIWindow(frame: CGRect(origin: .zero, size: referenceSize))
        let sut = AlarmOffWarningViewController()
        // On the CONTROLLER, not the window: this window is never made visible,
        // and a controller override propagates into its own view subtree
        // whether or not the window ever renders.
        sut.overrideUserInterfaceStyle = style
        window.rootViewController = sut
        hostWindows.append(window)
        layOut(sut, in: window)
        try XCTSkipUnless(
            sut.heroBadge.traitCollection.userInterfaceStyle == style,
            "controller override did not propagate — a harness fact, not a component one"
        )
        return (sut, window)
    }

    /// Force a full layout pass down to the badge.
    ///
    /// The frame is set explicitly because a window that is never made visible
    /// is not guaranteed to have sized its root view yet, and a root view at
    /// `.zero` would leave the badge at `.zero` for reasons unrelated to #536.
    private func layOut(_ sut: UIViewController, in window: UIWindow) {
        sut.loadViewIfNeeded()
        sut.view.frame = window.bounds
        window.setNeedsLayout()
        window.layoutIfNeeded()
        sut.view.setNeedsLayout()
        sut.view.layoutIfNeeded()
    }

    private func flip(
        _ sut: AlarmOffWarningViewController,
        in window: UIWindow,
        to style: UIUserInterfaceStyle
    ) throws {
        sut.overrideUserInterfaceStyle = style
        layOut(sut, in: window)
        try XCTSkipUnless(
            sut.heroBadge.traitCollection.userInterfaceStyle == style,
            "controller override did not propagate — a harness fact, not a component one"
        )
    }

    /// Lay the badge out at `side` instead of its design size.
    ///
    /// The 80×80 constraints the badge owns are dropped rather than overridden:
    /// they are required, and a second required constraint of a different
    /// constant resolves arbitrarily.
    private func resize(
        _ badge: UIView,
        of sut: UIViewController,
        in window: UIWindow,
        to side: CGFloat
    ) {
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
        sut.view.setNeedsLayout()
        sut.view.layoutIfNeeded()
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
    /// layer that is the badge's position inside its parent, which would never
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

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var name: String { self == .light ? "light" : "dark" }
}
