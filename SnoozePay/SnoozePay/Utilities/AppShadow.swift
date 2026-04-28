import UIKit

/// Shadow recipes from `tokens.css` (`--sp-shadow-1` / `--sp-shadow-2`). The
/// dark variant is a single drop shadow; the light variant is a two-stop
/// drop shadow (`0 1px 3px / 0 4px 14px rgba(8,14,30,.06)`) that fakes the
/// ambient + key light a flat single shadow can't reproduce.
///
/// CALayer can render only one shadow natively, so the wider key stop is
/// installed on the host layer via `apply(to:)` and the narrower ambient stop
/// is rendered through a dedicated sibling sublayer inserted at index 0 by
/// ``installAmbientShadow1Layer(on:cornerRadius:trait:)``. The sublayer is a
/// `CAShapeLayer` clipped to a clear path so only its shadow is visible.
///
/// Apply via `apply(to: layer)` from `traitCollectionDidChange` so the shadow
/// re-resolves on theme switch, and call
/// ``installAmbientShadow1Layer(on:cornerRadius:trait:)`` from both
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

    /// Default card shadow — the wider/key stop only. Dark
    /// `0 2px 8px rgba(0,0,0,.35)`. Light is the dominant stop of
    /// `0 1px 3px / 0 4px 14px rgba(8,14,30,.06)` — we use the wider 14pt
    /// radius for legibility on near-white surfaces. Pair with
    /// ``installAmbientShadow1Layer(on:cornerRadius:trait:)`` to render the
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
    /// narrower `0 1px 3px` ambient stop. The ambient layer fills with
    /// `clear` and uses its own shadow chain so the visible card surface
    /// (drawn by the host's `backgroundColor` / `borderColor` on the host
    /// layer itself) is unaffected.
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
        trait: UITraitCollection
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
            // sublayers a card might own. The ambient layer renders only
            // its shadow (fill is clear), so z-order doesn't bleed visible
            // pixels onto the card surface.
            hostLayer.insertSublayer(layer, at: 0)
            ambient = layer
        }

        ambient.frame = hostLayer.bounds
        let path = UIBezierPath(roundedRect: hostLayer.bounds, cornerRadius: cornerRadius).cgPath
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
    }
}
