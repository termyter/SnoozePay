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
///   colours.
///
/// **The mounting shape is measured, not assumed (#568).** This file shipped
/// with a window that was never unhidden and the override on the CONTROLLER,
/// on the theory that a controller override reaches its own subtree whether or
/// not the window renders. It does not — the same arrangement was compared side
/// by side in #565 and it neither lays out nor propagates. So the harness guard
/// fired on every run and **all four cases here reported `skipped`**: from the
/// day it was written (#540) this file pinned #536 with nothing at all. An
/// unhidden window with the override on the WINDOW, set *before*
/// `rootViewController` so `refreshHeroTheme()` runs from `viewDidLoad` in the
/// theme under test, both lays out and propagates.
///
/// **No `XCTSkip` anywhere in this file, on purpose.** A skip that fires on
/// every run is indistinguishable from a test nobody wrote, with the added cost
/// that it looks written. Harness guards are `XCTFail`, so a harness that stops
/// laying out or stops propagating fails loudly instead of hiding.
///
/// **One layout pass per theme state.** The defect's frame assignment came from
/// a `DispatchQueue.main.async` hop, so extra synchronous passes cannot revive
/// it here — but a pass driven from the badge downwards is exactly the shape
/// that hands a stale sublayer a size it never gets in the app (the trap #565
/// walked into), so every pass is driven top-down from the window and only
/// once.
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
        hostWindows.forEach {
            $0.isHidden = true
            $0.rootViewController = nil
        }
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
        let (sut, window) = makeHostedSheet(style: .dark)
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
            let (sut, _) = makeHostedSheet(style: style)
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
        let (sut, window) = makeHostedSheet(style: .dark)
        let badge: UIView = sut.heroBadge

        // The #536 pin, asserted before any stop is read. Without it this case
        // is green on the defect: #536 never touched the stops, it left the
        // layer carrying them at a size nobody can see, so a ramp read alone
        // would call an invisible badge correctly themed. This is the exact
        // hole found in the sibling file in #565.
        let disc = try discRect(ofBadge: badge)
        XCTAssertEqual(
            disc, badge.bounds,
            "the fill measures \(disc.size) inside a \(badge.bounds.size) badge — the stops "
            + "below would be read off a layer that paints nothing (#536)"
        )

        let inDark = stops(of: badge)
        XCTAssertFalse(inDark.isEmpty, "the badge installed no gradient stops at all")

        flip(sut, in: window, to: .light)
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

        flip(sut, in: window, to: .dark)
        XCTAssertEqual(stops(of: badge), inDark, "the badge did not return to the dark ramp")
    }

    /// The pain-tinted drop shadow is the badge's other cached `cgColor`, and
    /// it is re-resolved by the same callback. Pinned separately so a fix that
    /// re-applies only the gradient does not read as complete.
    func testHeroBadgeShadow_reresolvesOnAThemeFlip() throws {
        let (sut, window) = makeHostedSheet(style: .dark)
        let badge: UIView = sut.heroBadge

        let inDark = try XCTUnwrap(badge.layer.shadowColor, "the badge carries no shadow colour")
        flip(sut, in: window, to: .light)

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

    /// The sheet mounted in a window that actually lays out, themed before it
    /// is built.
    ///
    /// The override goes on the WINDOW and the window is unhidden — the two
    /// halves #565 measured to be necessary. It is set *before*
    /// `rootViewController` because `refreshHeroTheme()` runs from
    /// `viewDidLoad`: the badge is then painted in the theme it is asserted in
    /// rather than leaning on a later repaint, which is what the flip cases
    /// below exist to check separately.
    ///
    /// The guards are `XCTFail`, not `XCTSkip`: a harness that cannot reproduce
    /// the condition has to say so in red.
    private func makeHostedSheet(style: UIUserInterfaceStyle) -> Hosted {
        let window = UIWindow(frame: CGRect(origin: .zero, size: referenceSize))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        let sut = AlarmOffWarningViewController()
        window.rootViewController = sut
        hostWindows.append(window)

        layOut(sut, in: window)
        XCTAssertEqual(
            sut.heroBadge.traitCollection.userInterfaceStyle, style,
            "the harness stopped propagating the theme to the badge — fix the harness, "
            + "do not skip"
        )
        XCTAssertFalse(
            sut.view.frame.isEmpty,
            "the harness stopped laying the sheet out — fix the harness, do not skip"
        )
        return (sut, window)
    }

    /// One full top-down layout pass, and only one.
    ///
    /// The frame is set explicitly because a window that was never made key is
    /// not guaranteed to have sized its root view yet, and a root view at
    /// `.zero` would leave the badge at `.zero` for reasons unrelated to #536.
    /// Nothing is laid out a second time from the badge's own end: that is the
    /// pass which hands a stale sublayer a size it never receives in the app.
    private func layOut(_ sut: UIViewController, in window: UIWindow) {
        sut.loadViewIfNeeded()
        sut.view.frame = window.bounds
        window.setNeedsLayout()
        window.layoutIfNeeded()
    }

    private func flip(
        _ sut: AlarmOffWarningViewController,
        in window: UIWindow,
        to style: UIUserInterfaceStyle
    ) {
        window.overrideUserInterfaceStyle = style
        layOut(sut, in: window)
        XCTAssertEqual(
            sut.heroBadge.traitCollection.userInterfaceStyle, style,
            "the harness stopped propagating the flip to \(style.name) — fix the harness, "
            + "do not skip"
        )
    }

    /// Lay the badge out at `side` instead of its design size.
    ///
    /// The 80×80 constraints the badge owns are dropped rather than overridden:
    /// they are required, and a second required constraint of a different
    /// constant resolves arbitrarily.
    private func resize(_ badge: UIView, in window: UIWindow, to side: CGFloat) {
        let fixedSize = badge.constraints.filter {
            ($0.firstAttribute == .width || $0.firstAttribute == .height) && $0.secondItem == nil
        }
        NSLayoutConstraint.deactivate(fixedSize)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: side),
            badge.heightAnchor.constraint(equalToConstant: side)
        ])
        // Top-down from the window, once. Laying the badge out from its own end
        // afterwards is the pass that could hand a stale sublayer the size it
        // never receives in the app, which is how a file goes green on the
        // defect it was written for.
        window.setNeedsLayout()
        window.layoutIfNeeded()
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

    /// The painted rect of whatever gradient the badge owns, or a failure —
    /// never a skip.
    private func discRect(ofBadge badge: UIView) throws -> CGRect {
        let gradient = try XCTUnwrap(
            gradientLayer(of: badge),
            "the badge owns no gradient layer at all"
        )
        return fillRect(of: gradient, in: badge)
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
