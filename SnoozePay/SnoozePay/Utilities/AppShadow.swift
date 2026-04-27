import UIKit

/// Shadow recipes from `tokens.css` (`--sp-shadow-1` / `--sp-shadow-2`). The
/// dark variant is a single drop shadow; the light variant is a two-stop
/// drop shadow (`0 1px 3px / 0 4px 14px rgba(8,14,30,.06)`) that fakes the
/// ambient + key light a flat single shadow can't reproduce. CALayer renders
/// one stop natively, so we use the wider stop for visibility on light
/// surfaces. Apply via `apply(to: layer)` from `traitCollectionDidChange`
/// so the shadow re-resolves on theme switch.
struct AppShadow {
    let color: UIColor
    let opacity: Float
    let offset: CGSize
    let radius: CGFloat

    /// Default card shadow. Dark `0 2px 8px rgba(0,0,0,.35)`. Light is the
    /// dominant stop of `0 1px 3px / 0 4px 14px rgba(8,14,30,.06)` — we use
    /// the wider 14pt radius for legibility on near-white surfaces.
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
}
