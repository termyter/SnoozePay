import UIKit

/// Shadow recipes from `tokens.css` (`--sp-shadow-1` / `--sp-shadow-2`). The
/// dark variant is a single drop shadow; the light variant is a two-stop
/// drop shadow (`0 1px 3px / 0 4px 14px rgba(8,14,30,.06)`) that fakes the
/// ambient + key light a flat single shadow can't reproduce.
///
/// CALayer can render only one shadow natively, so the wider key stop is
/// installed on the host layer via `apply(to:)` and the narrower ambient stop
/// is rendered through a dedicated sibling sublayer inserted at index 0 by
/// ``installAmbientShadow1Layer(on:cornerRadius:trait:corners:openEdges:)``. The sublayer is a
/// clear-filled `CAShapeLayer` masked to the region outside the card, so it
/// contributes the halo without washing the card's own surface.
///
/// Apply via `apply(to: layer)` from `traitCollectionDidChange` so the shadow
/// re-resolves on theme switch, and call
/// ``installAmbientShadow1Layer(on:cornerRadius:trait:corners:openEdges:)`` from both
/// `traitCollectionDidChange` (to install/remove on theme flip) and
/// `layoutSubviews` (so the ambient layer's frame stays in sync with the host).
struct AppShadow {
    let color: UIColor
    let opacity: Float
    let offset: CGSize
    let radius: CGFloat

    /// Sublayer name used to identify the ambient (narrow) shadow stop layer.
    /// Stored as a constant so callers can never spell it differently.
    static let ambientShadow1LayerName = "AppShadow.ambientShadow1"

    /// How far the ambient layer is outset past its host so the halo has room
    /// to render. The `0 1px 3px` stop can travel at most `offset + radius`
    /// = 4pt from the card edge; 8pt leaves slack without inflating the layer
    /// enough to matter.
    static let ambientShadow1Spread: CGFloat = 8

    /// Default card shadow — the wider/key stop only. Dark
    /// `0 2px 8px rgba(0,0,0,.35)`. Light is the dominant stop of
    /// `0 1px 3px / 0 4px 14px rgba(8,14,30,.06)` — we use the wider 14pt
    /// radius for legibility on near-white surfaces. Pair with
    /// ``installAmbientShadow1Layer(on:cornerRadius:trait:corners:openEdges:)`` to render the
    /// narrower ambient stop on light-mode surfaces.
    static func shadow1(for trait: UITraitCollection) -> AppShadow {
        if trait.userInterfaceStyle == .light {
            return AppShadow(
                color: UIColor(red: 8.0 / 255.0, green: 14.0 / 255.0, blue: 30.0 / 255.0, alpha: 1.0),
                opacity: 0.06,
                offset: CGSize(width: 0, height: 4),
                radius: 14
            )
        }
        return AppShadow(
            color: .black,
            opacity: 0.35,
            offset: CGSize(width: 0, height: 2),
            radius: 8
        )
    }

    /// Stronger card shadow — modal sheets, hero panels.
    /// Dark `0 8px 24px rgba(0,0,0,.45)`, Light `0 6px 20px rgba(8,14,30,.10)`.
    static func shadow2(for trait: UITraitCollection) -> AppShadow {
        if trait.userInterfaceStyle == .light {
            return AppShadow(
                color: UIColor(red: 8.0 / 255.0, green: 14.0 / 255.0, blue: 30.0 / 255.0, alpha: 1.0),
                opacity: 0.10,
                offset: CGSize(width: 0, height: 6),
                radius: 20
            )
        }
        return AppShadow(
            color: .black,
            opacity: 0.45,
            offset: CGSize(width: 0, height: 8),
            radius: 24
        )
    }

    /// Apply this shadow recipe to a `CALayer`. Caller must ensure
    /// `masksToBounds = false` and (ideally) provide a `shadowPath` so the
    /// rasterised shadow doesn't pay the offscreen pass cost.
    func apply(to layer: CALayer) {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowRadius = radius
    }

    /// Install / refresh / remove the narrow ambient stop of `shadow1` on a
    /// host layer.
    ///
    /// The two-stop spec is `0 1px 3px / 0 4px 14px rgba(8,14,30,.06)`. The
    /// wider stop is rendered by `shadow1(for:).apply(to: layer)` directly on
    /// the host layer; this method maintains a sibling `CAShapeLayer` named
    /// ``ambientShadow1LayerName`` inserted at sublayer index 0 to render the
    /// narrower `0 1px 3px` ambient stop.
    ///
    /// The ambient layer is outset past the host by ``ambientShadow1Spread``
    /// and masked to the region *outside* the card, so only the halo composites
    /// onto the page. Without that mask the stop also washes the card's own
    /// interior — see ``installHaloMask(on:cardRect:cornerRadius:corners:)`` (#515).
    ///
    /// Dark mode collapses back to a single stop, so this method removes the
    /// ambient layer if `trait.userInterfaceStyle == .dark`.
    ///
    /// Call from both `layoutSubviews` (so `frame` and `shadowPath` track
    /// host bounds) and `traitCollectionDidChange` (so the layer is added or
    /// removed when the user flips theme).
    static func installAmbientShadow1Layer(
        on hostLayer: CALayer,
        cornerRadius: CGFloat,
        trait: UITraitCollection,
        corners: CACornerMask = .allCorners,
        openEdges: UIRectEdge = []
    ) {
        let isLight = trait.userInterfaceStyle != .dark
        let existing = hostLayer.sublayers?.first { $0.name == ambientShadow1LayerName } as? CAShapeLayer

        guard isLight else {
            // Dark mode uses the single deep stop only — drop the ambient
            // sublayer so we don't carry stale state across a theme flip.
            existing?.removeFromSuperlayer()
            return
        }

        let ambient: CAShapeLayer
        if let layer = existing {
            ambient = layer
        } else {
            let layer = CAShapeLayer()
            layer.name = ambientShadow1LayerName
            // Insert at index 0 so it sits behind any gradient/content
            // sublayers a card might own.
            hostLayer.insertSublayer(layer, at: 0)
            ambient = layer
        }

        // Outset so the halo isn't cut off at the host's edge, and keep the
        // card's own footprint in the layer's coordinate space for the path,
        // the shadow and the mask.
        ambient.frame = hostLayer.bounds.insetBy(dx: -ambientShadow1Spread, dy: -ambientShadow1Spread)
        let cardRect = CGRect(
            origin: CGPoint(x: ambientShadow1Spread, y: ambientShadow1Spread),
            size: hostLayer.bounds.size
        ).grown(by: ambientShadow1Spread, on: openEdges)
        let path = cardPath(cardRect, cornerRadius: cornerRadius, corners: corners)
        ambient.path = path
        ambient.fillColor = UIColor.clear.cgColor
        // Narrow ambient stop: `0 1px 3px rgba(8,14,30,.06)`.
        ambient.shadowColor = UIColor(
            red: 8.0 / 255.0, green: 14.0 / 255.0, blue: 30.0 / 255.0, alpha: 1.0
        ).cgColor
        ambient.shadowOpacity = 0.06
        ambient.shadowOffset = CGSize(width: 0, height: 1)
        ambient.shadowRadius = 3
        // Pre-rasterise the ambient shadow against the rounded path for the
        // same offscreen-pass reasons as the wider stop.
        ambient.shadowPath = path
        ambient.masksToBounds = false
        installHaloMask(
            on: ambient,
            cardRect: cardRect,
            cornerRadius: cornerRadius,
            corners: corners
        )
    }

    /// Clip the ambient layer to the region *outside* the card it decorates.
    ///
    /// Core Animation draws a layer's shadow beneath that layer's own content
    /// but on top of everything already composited behind it — including the
    /// parent's `backgroundColor`. The ambient layer's content is a `clear`
    /// fill, so the blurred silhouette is not just a halo: its solid interior
    /// lands on the card surface at full strength. On a light `bg1` card that
    /// is `#FFFFFF` under 6% of `rgb(8,14,30)`, i.e. **`#F0F1F2`** — and since
    /// only section caps carry the ambient stop, the middle rows stayed
    /// `#FFFFFF` and the card read as striped (#515). Dark never showed it
    /// because dark drops the ambient layer altogether.
    ///
    /// Masking to `layerBounds − cardRect` (even-odd) keeps the outward halo
    /// and removes the interior wash. A mask clips a layer's shadow along with
    /// its content, which is exactly the lever needed here.
    private static func installHaloMask(
        on ambient: CAShapeLayer,
        cardRect: CGRect,
        cornerRadius: CGFloat,
        corners: CACornerMask
    ) {
        let mask = (ambient.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = ambient.bounds
        mask.fillRule = .evenOdd
        let halo = UIBezierPath(rect: ambient.bounds)
        halo.append(
            UIBezierPath(
                cgPath: cardPath(cardRect, cornerRadius: cornerRadius, corners: corners)
            )
        )
        halo.usesEvenOddFillRule = true
        mask.path = halo.cgPath
        if ambient.mask !== mask {
            ambient.mask = mask
        }
    }

    /// The card's real silhouette: a rect rounded only where `corners` says it
    /// is rounded.
    ///
    /// This used to be an unconditional `UIBezierPath(roundedRect:cornerRadius:)`,
    /// and that is the whole of #674. A section cap is rounded on one side and
    /// square on the other, so a fully rounded hole leaves the two square
    /// corners' little triangles OUTSIDE it — inside the visible part of the
    /// halo mask. The ambient stop's interior (`#F0F1F2` over `bg1`) then
    /// printed into exactly those triangles, which sit in the seam between two
    /// rows, and the section read as if every row were individually rounded.
    static func cardPath(
        _ rect: CGRect,
        cornerRadius: CGFloat,
        corners: CACornerMask = .allCorners
    ) -> CGPath {
        // Clamped the way `CardRowBackgroundView.outlinePath` clamps, so a row
        // shorter than two radii cannot ask for a corner bigger than itself.
        let radius = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
        return UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners.rectCorners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath
    }
}

extension CACornerMask {
    static let allCorners: CACornerMask = [
        .layerMinXMinYCorner, .layerMaxXMinYCorner,
        .layerMinXMaxYCorner, .layerMaxXMaxYCorner
    ]

    /// `UIBezierPath` speaks `UIRectCorner`; `CALayer` speaks `CACornerMask`.
    /// The two name the same four corners in UIKit's y-down geometry.
    var rectCorners: UIRectCorner {
        var corners: UIRectCorner = []
        if contains(.layerMinXMinYCorner) { corners.insert(.topLeft) }
        if contains(.layerMaxXMinYCorner) { corners.insert(.topRight) }
        if contains(.layerMinXMaxYCorner) { corners.insert(.bottomLeft) }
        if contains(.layerMaxXMaxYCorner) { corners.insert(.bottomRight) }
        return corners
    }
}

extension CGRect {
    /// Push the named edges outward by `amount`.
    ///
    /// Used for the edges a card shares with a neighbouring row. The halo is
    /// the region outside the card, so an edge that is really the middle of a
    /// taller card must be pushed past where the decoration can reach —
    /// otherwise the stop haloes into the neighbour's surface and draws a
    /// shadow line where the section is continuous.
    func grown(by amount: CGFloat, on edges: UIRectEdge) -> CGRect {
        var rect = self
        if edges.contains(.top) {
            rect.origin.y -= amount
            rect.size.height += amount
        }
        if edges.contains(.bottom) { rect.size.height += amount }
        if edges.contains(.left) {
            rect.origin.x -= amount
            rect.size.width += amount
        }
        if edges.contains(.right) { rect.size.width += amount }
        return rect
    }
}
