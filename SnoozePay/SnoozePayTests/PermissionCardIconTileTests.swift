import UIKit
import XCTest
@testable import SnoozePay

/// The permissions screen's icon tile must actually render its fill (#553).
///
/// Like #516 this is not a colour bug. `AppColors.fgOnMoney` is the right ink
/// for a solid money tile in both themes; what never appeared was the tile.
/// `PermissionCardView` keeps its money ramp in a `CAGradientLayer` inserted as
/// a sublayer of `iconHost`, and frames it from the *card's* `layoutSubviews`.
/// `iconHost` is a grandchild (card → SPCard → iconHost), so when that callback
/// runs Auto Layout has only pushed geometry down one level and
/// `iconHost.bounds` is still `.zero`. The layer is unhidden and empty, the
/// `#052016` glyph lands on the card fill `bg1 #0E1320`, and the audit measured
/// **1.09:1** — the granted row reads emptier than the unavailable one.
///
/// **Why the obvious test would not have caught it.** Asserting that the
/// granted state unhides the layer, or that `fgOnMoney` clears 4.5:1 on
/// `money400`, passes against the broken code — the tokens and the `isHidden`
/// flag were right the whole time. So these tests mount a real card in a
/// `UIWindow`, run one honest layout pass, measure geometry first, and only
/// then read contrast off *whatever surface is actually behind the glyph*,
/// compositing translucent fills up the ancestor chain the way the screen does.
///
/// **One layout pass is load-bearing.** Laying out twice would hand the
/// sublayer a size it never receives in the app and turn this file green
/// against the defect.
final class PermissionCardIconTileTests: XCTestCase {

    /// WCAG 2.1 non-text floor. The tile glyph is a 20pt symbol, not text —
    /// #553 asks for 3:1, which the money ramp clears where the glyph sits.
    private let nonTextFloor: CGFloat = 3.0
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02
    /// The tile's design size — 40×40, 12pt corners (`AppRadius.sm`).
    private let tileSide: CGFloat = 40

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.rootViewController = nil }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The defect: a gradient layer nobody sized

    /// The granted tile has a real size after layout, covers the glyph drawn
    /// on it, and carries stops.
    ///
    /// Written against "a gradient, wherever it lives" — the host's own layer
    /// via `layerClass`, or a sublayer — so it keeps measuring the defect
    /// rather than the shape of the fix.
    func testGrantedIconTile_isSizedAndCoversTheGlyph_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            for status in [PermissionStatus.granted, .enabled] {
                let (card, _) = try makeHostedCard(status: status, style: style)
                let host = try XCTUnwrap(iconHostView(of: card), "the card lost its icon host")
                let label = "\(style.name)/\(Self.name(of: status))"

                XCTAssertEqual(
                    host.bounds.size,
                    CGSize(width: tileSide, height: tileSide),
                    "the icon host itself did not lay out in \(label)"
                )

                let gradient = try XCTUnwrap(
                    gradientLayer(of: host),
                    "the icon host owns no gradient layer at all in \(label)"
                )
                XCTAssertFalse(gradient.isHidden, "the granted tile's gradient is hidden in \(label)")

                let tile = tileRect(of: gradient, in: host)
                XCTAssertFalse(
                    tile.isEmpty,
                    "the tile's gradient measures \(tile.size) in \(label) — a CAGradientLayer "
                    + "added as a sublayer does not auto-size, and the card's layoutSubviews fires "
                    + "before its grandchild iconHost has a size"
                )
                XCTAssertEqual(tile, host.bounds, "the tile does not fill the icon host in \(label)")

                let glyph = try XCTUnwrap(glyphView(in: host), "the tile lost its glyph")
                XCTAssertFalse(glyph.frame.isEmpty, "the tile glyph did not lay out in \(label)")
                XCTAssertTrue(
                    tile.contains(glyph.center),
                    "the tile (\(tile)) is not under the glyph (\(glyph.frame)) in \(label) — "
                    + "the ink is landing on the card fill, not on the money tile"
                )

                XCTAssertFalse(
                    (gradient.colors ?? []).isEmpty,
                    "the tile is sized but has no stops in \(label)"
                )
            }
        }
    }

    // MARK: - What the user sees

    /// Every status clears the non-text bar against the surface actually
    /// behind the glyph, in both themes.
    ///
    /// `backdropUnderGlyph` is the whole point: when the tile fails to paint,
    /// the walk composites down to the card fill — which is what the audit
    /// sampled — so this fails on the original code with the real 1.09:1, not
    /// with a geometry complaint.
    func testIconGlyph_clearsTheNonTextBar_onWhateverIsActuallyBehindIt() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            for status in Self.allStatuses {
                let (card, _) = try makeHostedCard(status: status.value, style: style)
                let host = try XCTUnwrap(iconHostView(of: card), "the card lost its icon host")
                let glyph = try XCTUnwrap(glyphView(in: host), "the tile lost its glyph")
                let ink = glyph.tintColor.resolvedColor(with: host.traitCollection)

                let backdrop = backdropUnderGlyph(glyph: glyph, style: style)
                let ratio = contrast(ink, backdrop.color)
                XCTAssertGreaterThanOrEqual(
                    ratio, nonTextFloor - tolerance,
                    "the \(status.name) glyph reads \(ratio.ratioText):1 on \(backdrop.what) in "
                    + "\(style.name) — #553 measured 1.09:1 for granted/enabled there"
                )
            }
        }
    }

    /// The measurement that makes the failure mode concrete: `fgOnMoney` on
    /// the bare card fill is indistinguishable from the card in both themes.
    /// The audit sampled `#0E1320` under `#052016` and got 1.09:1; on light the
    /// card fill is pure white and so is `fgOnMoney`, i.e. 1.00:1 — the same
    /// defect, one notch worse.
    func testCardFill_underMoneyInk_isTheNonContrastTheBugShipped() {
        let expected: [(style: UIUserInterfaceStyle, ratio: CGFloat)] = [
            (.dark, 1.08),
            (.light, 1.00)
        ]
        for entry in expected {
            let ink = AppColors.fgOnMoney.resolved(entry.style)
            let fill = AppColors.bg1.resolved(entry.style)
            let ratio = contrast(ink, fill)
            XCTAssertEqual(
                ratio, entry.ratio, accuracy: 0.05,
                "fgOnMoney on bg1 measures \(ratio.ratioText):1 in \(entry.style.name) — if this "
                + "moved, re-derive the number quoted in #553 rather than deleting the pin"
            )
        }
    }

    // MARK: - Surviving a theme flip

    /// `CAGradientLayer.colors` holds plain `CGColor`, which never re-resolves
    /// itself. Stops taken from `SPSupport.moneyGradientColors` in a stored
    /// property initializer freeze whichever theme `UITraitCollection.current`
    /// happened to be, so the tile has to re-apply the ramp on a trait change
    /// — and land on the ramp the design system defines for the new theme.
    func testIconTileRamp_reresolvesOnAThemeFlip() throws {
        let (card, window) = try makeHostedCard(status: .granted, style: .dark)
        let controller = try XCTUnwrap(window.rootViewController)
        let host = try XCTUnwrap(iconHostView(of: card), "the card lost its icon host")

        let inDark = stops(of: host)
        try XCTSkipUnless(!inDark.isEmpty, "the tile installed no gradient stops at all")

        controller.overrideUserInterfaceStyle = .light
        layOut(controller, in: window)
        try XCTSkipUnless(
            host.traitCollection.userInterfaceStyle == .light,
            "controller override did not propagate — a harness fact, not a component one"
        )

        let inLight = stops(of: host)
        XCTAssertNotEqual(
            inDark, inLight,
            "the tile kept its dark stops after the flip — a CGColor in "
            + "CAGradientLayer.colors never re-resolves itself"
        )
        XCTAssertEqual(
            inLight,
            SPSupport.moneyGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
                .map { hex($0) },
            "the tile re-tinted to something other than the light money ramp"
        )

        controller.overrideUserInterfaceStyle = .dark
        layOut(controller, in: window)
        try XCTSkipUnless(
            host.traitCollection.userInterfaceStyle == .dark,
            "controller override did not propagate — a harness fact, not a component one"
        )
        XCTAssertEqual(stops(of: host), inDark, "the tile did not return to the dark ramp")
    }

    // MARK: - Fixtures

    private struct NamedStatus {
        let value: PermissionStatus
        let name: String
    }

    private static let allStatuses: [NamedStatus] = [
        NamedStatus(value: .granted, name: "granted"),
        NamedStatus(value: .enabled, name: "enabled"),
        NamedStatus(value: .actionable, name: "actionable"),
        NamedStatus(value: .unavailable, name: "unavailable")
    ]

    private static func name(of status: PermissionStatus) -> String {
        allStatuses.first { $0.value == status }?.name ?? "?"
    }

    private typealias Hosted = (card: PermissionCardView, window: UIWindow)

    /// A real card, in a real window, laid out exactly once.
    ///
    /// `apply(status:)` runs *before* the layout pass because that is the order
    /// `PermissionsViewController` uses (cards are built and stamped from
    /// `viewDidLoad`, geometry arrives afterwards) — and it is the order that
    /// exposes #553.
    private func makeHostedCard(
        kind: PermissionKind = .notifications,
        status: PermissionStatus,
        style: UIUserInterfaceStyle
    ) throws -> Hosted {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let controller = UIViewController()
        // On the CONTROLLER, not the window: this window is never made visible,
        // and a controller override propagates into its own view subtree
        // whether or not the window ever renders.
        controller.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        hostWindows.append(window)

        controller.loadViewIfNeeded()
        controller.view.backgroundColor = AppColors.bg0
        let card = PermissionCardView(kind: kind)
        controller.view.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 100)
        ])
        card.apply(status: status)

        layOut(controller, in: window)
        try XCTSkipUnless(
            card.traitCollection.userInterfaceStyle == style,
            "controller override did not propagate — a harness fact, not a component one"
        )
        return (card, window)
    }

    /// One full top-down layout pass, and only one. A second pass would hand
    /// the sublayer a size it never receives in the app.
    private func layOut(_ controller: UIViewController, in window: UIWindow) {
        controller.view.frame = window.bounds
        window.setNeedsLayout()
        window.layoutIfNeeded()
    }

    // MARK: - Reading the rendered card

    /// The 40×40 tile behind the leading glyph, found by shape rather than by
    /// name so the test survives a rename of the private property.
    private func iconHostView(of card: PermissionCardView) -> UIView? {
        var queue: [UIView] = card.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            let hasGlyph = view.subviews.contains { $0 is UIImageView }
            if hasGlyph, view.subviews.count == 1, view.layer.cornerRadius > 0 {
                return view
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// The tile's gradient, whether it is the view's own layer or a sublayer.
    private func gradientLayer(of view: UIView) -> CAGradientLayer? {
        if let own = view.layer as? CAGradientLayer { return own }
        return view.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
    }

    /// The gradient's rect in the host's own coordinate space, so it can be
    /// compared against the glyph's frame in either arrangement.
    private func tileRect(of gradient: CAGradientLayer, in host: UIView) -> CGRect {
        guard gradient !== host.layer else { return host.bounds }
        return host.layer.convert(gradient.bounds, from: gradient)
    }

    private func glyphView(in host: UIView) -> UIImageView? {
        host.subviews.compactMap { $0 as? UIImageView }.first
    }

    private func stops(of host: UIView) -> [UInt32] {
        guard let gradient = gradientLayer(of: host), !gradient.isHidden else { return [] }
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

    /// What is painted directly behind the glyph's centre, composited the way
    /// the screen composites it.
    ///
    /// Walks up from the glyph's host: the first *visible, non-empty* gradient
    /// covering the point wins outright; otherwise every ancestor's
    /// `backgroundColor` is blended in source-over order until the stack is
    /// opaque. `whiteOverlay08` is translucent, so the unavailable tile only
    /// reads correctly when composited over the card fill — which is exactly
    /// what the audit's `#212632` sample is.
    private func backdropUnderGlyph(glyph: UIView, style: UIUserInterfaceStyle) -> Backdrop {
        var accumulated: UIColor?
        var seen: [String] = []
        var node: UIView? = glyph.superview

        while let current = node {
            let centre = CGPoint(x: glyph.bounds.midX, y: glyph.bounds.midY)
            let point = current.convert(centre, from: glyph)
            if
                let gradient = gradientLayer(of: current),
                !gradient.isHidden,
                !(gradient.colors ?? []).isEmpty,
                tileRect(of: gradient, in: current).contains(point),
                let sampled = sampleGradient(gradient, at: point, in: current.bounds)
            {
                seen.append("the money tile under its centre")
                let blended = composite(over: sampled, accumulated) ?? sampled
                return Backdrop(color: blended, what: describe(stack: seen))
            }
            if
                let fill = current.backgroundColor?.resolvedColor(with: current.traitCollection),
                alpha(of: fill) > 0 {
                seen.append(name(of: fill, style: style))
                accumulated = composite(over: fill, accumulated)
                if let accumulated, alpha(of: accumulated) >= 0.999 {
                    return Backdrop(color: accumulated, what: describe(stack: seen))
                }
            }
            node = current.superview
        }

        let base = AppColors.bg0.resolved(style)
        seen.append("bg0")
        return Backdrop(color: composite(over: base, accumulated) ?? base, what: describe(stack: seen))
    }

    private func describe(stack: [String]) -> String {
        stack.reversed().joined(separator: " under ")
    }

    /// Name a fill by the token it matches, so failure messages read like the
    /// audit table rather than like hex soup.
    private func name(of color: UIColor, style: UIUserInterfaceStyle) -> String {
        let tokens: [(name: String, color: UIColor)] = [
            ("bg0", AppColors.bg0),
            ("bg1", AppColors.bg1),
            ("bg2", AppColors.bg2),
            ("whiteOverlay08", AppColors.whiteOverlay08)
        ]
        let hexText = String(format: "#%06X", hex(color))
        for token in tokens where matches(token.color.resolved(style), color) {
            return "\(token.name) (\(hexText))"
        }
        return hexText
    }

    private func matches(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        let left = rgba(lhs)
        let right = rgba(rhs)
        return abs(left.red - right.red) < 0.004
            && abs(left.green - right.green) < 0.004
            && abs(left.blue - right.blue) < 0.004
            && abs(left.alpha - right.alpha) < 0.004
    }

    /// Source-over: whatever was already gathered above, painted on `bottom`.
    private func composite(over bottom: UIColor, _ top: UIColor?) -> UIColor? {
        guard let top else { return bottom }
        let over = rgba(top)
        let under = rgba(bottom)
        let outAlpha = over.alpha + under.alpha * (1 - over.alpha)
        guard outAlpha > 0 else { return top }
        func channel(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
            (lhs * over.alpha + rhs * under.alpha * (1 - over.alpha)) / outAlpha
        }
        return UIColor(
            red: channel(over.red, under.red),
            green: channel(over.green, under.green),
            blue: channel(over.blue, under.blue),
            alpha: outAlpha
        )
    }

    /// Evaluate a linear `CAGradientLayer` at `point` (host coordinates).
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

    private func hex(_ color: CGColor) -> UInt32 { hex(UIColor(cgColor: color)) }

    private func hex(_ color: UIColor) -> UInt32 {
        let parts = rgba(color)
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(parts.red) << 16) | (toByte(parts.green) << 8) | toByte(parts.blue)
    }

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func rgba(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return Channels(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func alpha(of color: UIColor) -> CGFloat { rgba(color).alpha }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        let parts = rgba(color)
        func value(_ raw: CGFloat) -> CGFloat {
            raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * value(parts.red) + 0.7152 * value(parts.green) + 0.0722 * value(parts.blue)
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
