import UIKit
import XCTest
@testable import SnoozePay

/// The streak modal's flame badge must actually render its disc (#516).
///
/// The bug this pins was not a colour bug. `AppColors.fgOnMoney` resolved
/// correctly in both themes — white on light, `#052016` on dark — and both are
/// the right ink for a solid money fill. What never appeared was the fill: the
/// badge's `CAGradientLayer` was a sublayer whose frame was assigned from the
/// controller's `viewDidLayoutSubviews`, and a sublayer does not auto-size.
/// That callback fires before `sheet → stack → badge` has a resolved size — the
/// same timing the file already documented for the money hero — so the layer
/// stayed at `.zero` forever and the glyph landed on the sheet fill instead.
/// Measured there it is ~1.0:1 dark / ~1.2:1 light: invisible in both themes.
///
/// **Why the obvious test would not have caught it.** An assertion that the
/// badge uses the money ramp, or that `fgOnMoney` clears 4.5:1 on `money400`,
/// passes against the broken code — the tokens were right the whole time. So
/// these tests measure geometry first (does the disc cover the glyph?) and only
/// then read the contrast off *whatever surface is actually behind the glyph*.
///
/// **The mounting shape is measured, not assumed.** The harness this file
/// shipped with hosted the modal in a window that was never unhidden and put
/// the override on the CONTROLLER, on the theory that a controller override
/// reaches its own view subtree whether or not the window renders. It does
/// not: compared side by side in run 33253446187, that arrangement lays out
/// nothing (`.zero` frames) and leaves the subtree on `.light`. So every
/// assertion below skipped itself, and this file reported three of its four
/// cases `skipped` on every run — #516 was pinned by nothing at all (run
/// 33254160373). An unhidden window with the override on the WINDOW both lays
/// out and propagates; that is what `StreakModalMoneyHeroThemeTests` already
/// uses against this same controller, and its flip cases have been executing
/// all along.
///
/// **No `XCTSkip` anywhere in this file, on purpose.** A guard that skips is a
/// guard that hides: a skip which fires on every run is indistinguishable from
/// a test that was never written. The harness guards are `XCTFail`, so a
/// harness that stops laying out or stops propagating the theme fails loudly.
///
/// **One layout pass is load-bearing.** #516 is a timing bug — the disc was
/// sized from `viewDidLayoutSubviews`, which fires before `sheet → stack →
/// badge` has a size. A second pass would hand that sublayer the size it never
/// receives in the app and turn this file green against the defect, so
/// `makeHostedModal` lays out exactly once.
final class StreakModalFlameBadgeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text. The flame is a bold 48pt glyph and
    /// would formally qualify for the 3:1 non-text bar; #516 asks for the
    /// stricter one, and the money ramp clears it where the glyph sits.
    private let normalTextFloor: CGFloat = 4.5
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02
    /// The badge's design size — 96×96, 28pt corners.
    private let badgeSide: CGFloat = 96

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach {
            $0.isHidden = true
            $0.rootViewController = nil
        }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The defect: a gradient layer nobody sized

    /// The disc has a real size after layout and covers the glyph drawn on it.
    ///
    /// Deliberately written against "a gradient layer, wherever it lives" —
    /// the view's own layer via `layerClass`, or a sublayer — so it keeps
    /// measuring the defect rather than the shape of the fix.
    func testFlameBadgeDisc_isSizedAndCoversTheGlyph_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let (modal, _) = try makeHostedModal(style: style)
            let badge = modal.flameBadge

            XCTAssertEqual(
                badge.bounds.size,
                CGSize(width: badgeSide, height: badgeSide),
                "the badge itself did not lay out in \(style.name)"
            )

            let gradient = try XCTUnwrap(
                gradientLayer(of: badge),
                "the badge owns no gradient layer at all in \(style.name)"
            )
            let disc = discRect(of: gradient, in: badge)
            XCTAssertFalse(
                disc.isEmpty,
                "the badge's gradient layer measures \(disc.size) in \(style.name) — "
                + "a CAGradientLayer added as a sublayer does not auto-size, and the "
                + "controller's viewDidLayoutSubviews fires before the badge has a size"
            )

            XCTAssertEqual(
                disc, badge.bounds,
                "the disc does not fill the badge in \(style.name)"
            )

            let glyph = try XCTUnwrap(glyphView(in: badge), "the badge lost its flame glyph")
            XCTAssertFalse(glyph.frame.isEmpty, "the flame glyph did not lay out")
            XCTAssertTrue(
                disc.contains(glyph.center),
                "the disc (\(disc)) is not under the glyph (\(glyph.frame)) in "
                + "\(style.name) — the ink is landing on the sheet, not on the fill"
            )

            XCTAssertFalse(
                (gradient.colors ?? []).isEmpty,
                "the disc is sized but has no stops in \(style.name)"
            )
        }
    }

    // MARK: - What the user sees

    /// The glyph clears the text bar against the surface actually behind it.
    ///
    /// `backdropUnderGlyph` is the whole point: when the disc fails to cover
    /// the glyph it returns the sheet fill, which is what the screenshots in
    /// #516 sampled. So this test fails on the original code with the real
    /// number, not with a geometry complaint.
    func testFlameGlyph_clearsTheTextBar_onWhateverIsActuallyBehindIt() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let (modal, _) = try makeHostedModal(style: style)
            let badge = modal.flameBadge
            let glyph = try XCTUnwrap(glyphView(in: badge), "the badge lost its flame glyph")
            let ink = glyph.tintColor.resolvedColor(with: badge.traitCollection)

            let backdrop = backdropUnderGlyph(badge: badge, glyph: glyph, style: style)
            let ratio = contrast(ink, backdrop.color)
            XCTAssertGreaterThanOrEqual(
                ratio, normalTextFloor - tolerance,
                "the flame glyph reads \(ratio.ratioText):1 on \(backdrop.what) in "
                + "\(style.name) — #516 measured 1.40:1 dark / 1.32:1 light there"
            )
        }
    }

    /// The measurement that makes the failure mode concrete, and pins why the
    /// screenshots looked the way they did: `fgOnMoney` on the *sheet* is
    /// indistinguishable from the sheet in both themes. The screenshot samples
    /// (`#152A35` / `#D9E2E7`, 1.40:1 / 1.32:1) read slightly higher than these
    /// because they include the badge's money-tinted drop shadow.
    func testSheetFill_underMoneyInk_isTheNonContrastTheBugShipped() {
        let expected: [(style: UIUserInterfaceStyle, ratio: CGFloat)] = [
            (.dark, 1.01),
            (.light, 1.16)
        ]
        for entry in expected {
            let ink = AppColors.fgOnMoney.resolved(entry.style)
            let sheet = AppColors.bg2.resolved(entry.style)
            let ratio = contrast(ink, sheet)
            XCTAssertEqual(
                ratio, entry.ratio, accuracy: tolerance,
                "fgOnMoney on bg2 measures \(ratio.ratioText):1 in \(entry.style.name) — "
                + "if this moved, re-derive the number quoted in #516 rather than deleting the pin"
            )
        }
    }

    // MARK: - Surviving a theme flip

    /// `CAGradientLayer.colors` holds plain `CGColor`, which never re-resolves
    /// itself. The badge has to re-apply the ramp from its trait-change
    /// registration — and land on the ramp the design system defines for the
    /// new theme, not merely on something different.
    func testFlameBadgeRamp_reresolvesOnAThemeFlip() throws {
        let (modal, window) = try makeHostedModal(style: .dark)
        let badge = modal.flameBadge

        // The #516 pin, asserted before the flip and after exactly one layout
        // pass. Without it this case is green on the defect: #516 never
        // touched the stops, it left the layer carrying them at `.zero`, so a
        // ramp read alone would call a disc nobody can see correct.
        let disc = try discRect(ofBadge: badge)
        XCTAssertEqual(
            disc, badge.bounds,
            "the disc measures \(disc.size) inside a \(badge.bounds.size) badge — the "
            + "stops below would be read off a layer that renders nothing (#516)"
        )

        let inDark = stops(of: badge)
        XCTAssertFalse(inDark.isEmpty, "the badge installed no gradient stops at all")

        window.overrideUserInterfaceStyle = .light
        layOut(modal, in: window)
        XCTAssertEqual(
            badge.traitCollection.userInterfaceStyle, .light,
            "the harness stopped propagating the flip to light — fix the harness, do not skip"
        )

        let inLight = stops(of: badge)
        XCTAssertNotEqual(
            inDark, inLight,
            "the badge kept its dark stops after the flip — a CGColor in "
            + "CAGradientLayer.colors never re-resolves itself"
        )
        XCTAssertEqual(
            inLight,
            SPSupport.moneyGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
                .map { hex($0) },
            "the badge re-tinted to something other than the light money ramp"
        )

        window.overrideUserInterfaceStyle = .dark
        layOut(modal, in: window)
        XCTAssertEqual(
            badge.traitCollection.userInterfaceStyle, .dark,
            "the harness stopped propagating the flip back to dark — fix the harness, do not skip"
        )
        XCTAssertEqual(stops(of: badge), inDark, "the badge did not return to the dark ramp")
    }

    // MARK: - Fixtures

    private typealias Hosted = (modal: StreakModalViewController, window: UIWindow)

    /// A real modal in a window that actually lays out, themed before it is
    /// built.
    ///
    /// The override goes on the WINDOW and the window is unhidden — the two
    /// halves the measurement in #565 found necessary. It is set *before*
    /// `rootViewController`, because `refreshLayerColors()` runs from
    /// `viewDidLoad`: that way the sheet is built in the theme it is shown in,
    /// instead of leaning on a later repaint that would hide a missing one.
    ///
    /// The guards are `XCTFail`, not `XCTSkip`. A harness that cannot
    /// reproduce the condition has to say so in red; skipping is how this file
    /// spent months reporting three cases that never ran.
    private func makeHostedModal(style: UIUserInterfaceStyle) throws -> Hosted {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        let modal = StreakModalViewController(streakDays: 7, savedAmount: 350)
        window.rootViewController = modal
        hostWindows.append(window)

        layOut(modal, in: window)
        XCTAssertEqual(
            modal.flameBadge.traitCollection.userInterfaceStyle, style,
            "the harness stopped propagating the theme — fix the harness, do not skip"
        )
        XCTAssertFalse(
            modal.view.frame.isEmpty,
            "the harness stopped laying the sheet out — fix the harness, do not skip"
        )
        return (modal, window)
    }

    /// One full top-down layout pass, and only one.
    ///
    /// The frame is set explicitly because a window that was never made key is
    /// not guaranteed to have sized its root view, and a root view at `.zero`
    /// would leave the badge at `.zero` for reasons that have nothing to do
    /// with #516. Nothing is laid out a second time on purpose: the callback
    /// #516 lived in runs again on every pass, and by the second one the badge
    /// has the size it lacked on the first.
    private func layOut(_ modal: StreakModalViewController, in window: UIWindow) {
        modal.loadViewIfNeeded()
        modal.view.frame = window.bounds
        window.setNeedsLayout()
        window.layoutIfNeeded()
    }

    // MARK: - Reading the rendered badge

    /// The badge's gradient, whether it is the view's own layer or a sublayer.
    private func gradientLayer(of view: UIView) -> CAGradientLayer? {
        if let own = view.layer as? CAGradientLayer { return own }
        return view.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
    }

    /// The gradient's rect expressed in the badge's own coordinate space, so
    /// it can be compared against the glyph's frame in either arrangement.
    private func discRect(of gradient: CAGradientLayer, in badge: UIView) -> CGRect {
        guard gradient !== badge.layer else { return badge.bounds }
        return badge.layer.convert(gradient.bounds, from: gradient)
    }

    /// The disc as rendered, or a failure — never a skip.
    private func discRect(ofBadge badge: UIView) throws -> CGRect {
        let gradient = try XCTUnwrap(
            gradientLayer(of: badge),
            "the badge owns no gradient layer at all"
        )
        return discRect(of: gradient, in: badge)
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

    private struct Backdrop {
        let color: UIColor
        let what: String
    }

    /// What is painted directly behind the glyph's centre.
    ///
    /// If the disc covers the glyph, that is the gradient sampled at the point
    /// the glyph's centre projects to along the 135° axis. If it does not —
    /// the #516 state — the glyph is over the sheet, and the sheet fill is the
    /// honest answer.
    private func backdropUnderGlyph(
        badge: UIView,
        glyph: UIView,
        style: UIUserInterfaceStyle
    ) -> Backdrop {
        guard
            let gradient = gradientLayer(of: badge),
            discRect(of: gradient, in: badge).contains(glyph.center),
            let sampled = sampleGradient(gradient, at: glyph.center, in: badge.bounds)
        else {
            return Backdrop(color: AppColors.bg2.resolved(style), what: "the bare sheet fill (bg2)")
        }
        return Backdrop(color: sampled, what: "the money disc under its centre")
    }

    /// Evaluate a linear `CAGradientLayer` at `point` (layer coordinates).
    ///
    /// `point` is projected onto the start → end axis, then the stop pair
    /// bracketing that parameter is interpolated. Sampling at the glyph's
    /// centre rather than the disc's far corner is deliberate: the deep end of
    /// the dark money ramp (`money700`, `#0B7A56`) reads 3.21:1 under
    /// `fgOnMoney`, but no part of the flame reaches it — the design's own
    /// artboard puts the glyph in the middle of the disc.
    private func sampleGradient(
        _ gradient: CAGradientLayer,
        at point: CGPoint,
        in bounds: CGRect
    ) -> UIColor? {
        var stops: [UIColor] = []
        for case let color as CGColor in gradient.colors ?? [] {
            stops.append(UIColor(cgColor: color))
        }
        guard !stops.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
        let locations = (gradient.locations?.map { CGFloat($0.doubleValue) })
            ?? stops.indices.map { CGFloat($0) / CGFloat(max(stops.count - 1, 1)) }
        guard locations.count == stops.count else { return nil }

        let unit = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
        let axis = CGPoint(
            x: gradient.endPoint.x - gradient.startPoint.x,
            y: gradient.endPoint.y - gradient.startPoint.y
        )
        let lengthSquared = axis.x * axis.x + axis.y * axis.y
        guard lengthSquared > 0 else { return nil }
        let offset = CGPoint(x: unit.x - gradient.startPoint.x, y: unit.y - gradient.startPoint.y)
        let position = (offset.x * axis.x + offset.y * axis.y) / lengthSquared

        return interpolate(stops: stops, locations: locations, at: position)
    }

    /// The colour a stop list resolves to at `position` along its axis.
    private func interpolate(stops: [UIColor], locations: [CGFloat], at position: CGFloat) -> UIColor {
        guard let first = stops.first, let last = stops.last, !locations.isEmpty else {
            return .clear
        }
        if position <= locations[0] { return first }
        if position >= locations[locations.count - 1] { return last }
        for index in 0..<(locations.count - 1) {
            let lower = locations[index]
            let upper = locations[index + 1]
            guard position >= lower, position <= upper else { continue }
            let span = upper - lower
            let progress = span > 0 ? (position - lower) / span : 0
            return SPSupport.lerpColor(stops[index], stops[index + 1], progress: Double(progress))
        }
        return last
    }

    // MARK: - Colour maths

    private func hex(_ color: CGColor) -> UInt32 {
        hex(UIColor(cgColor: color))
    }

    private func hex(_ color: UIColor) -> UInt32 {
        let rgb = channels(color)
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(rgb.red) << 16) | (toByte(rgb.green) << 8) | toByte(rgb.blue)
    }

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0)
        }
        return Channels(red: red, green: green, blue: blue)
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        let rgb = channels(color)
        func value(_ raw: CGFloat) -> CGFloat {
            raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * value(rgb.red) + 0.7152 * value(rgb.green) + 0.0722 * value(rgb.blue)
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs)
        let second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
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

private extension CGFloat {
    /// Two decimals — a failure message should carry the measurement.
    var ratioText: String { String(format: "%.2f", self) }
}
