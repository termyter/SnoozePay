import UIKit

/// Miniature of an alarm theme's firing atmosphere (#463).
///
/// Shared by the theme picker's 180pt preview block and by every grid tile, so
/// both are built from one recipe and cannot drift apart. Two layers:
/// 1. **Base** — 135° diagonal gradient, `AlarmThemeRendering.gradientColors`.
/// 2. **Glow** — bottom-centre radial in the theme's accent, the same
///    "light from below the horizon" cue the firing background paints. Without
///    it Dawn / Forest / Abstract all read as the same dark surface at tile
///    size, which is exactly what the design audit flagged.
///
/// Geometry comes from the prototype's preview block (`SPMore2.jsx:277-281`):
/// a 240pt circle whose bottom sits 40pt below a 180pt-tall block — i.e. a
/// diameter of 1.33× and a centre inset of 0.44× the block's short side. Both
/// ratios are expressed against `min(width, height)` so the same recipe scales
/// down to a 3-column tile without the glow swallowing it.
final class SPThemePreviewView: UIView {

    // MARK: - Geometry

    private static let glowDiameterRatio: CGFloat = 1.333
    private static let glowCentreInsetRatio: CGFloat = 0.444

    // MARK: - Layers

    private let baseLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        // 135° (top-left → bottom-right), matching the prototype's tiles.
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        return gradient
    }()

    /// `radial-gradient(circle, accent 0%, transparent 65%)` — same fade stop
    /// as `SPThemedFiringBackgroundView`, so the miniature and the real screen
    /// carry the same amount of warmth.
    private let glowLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.locations = [0.0, 0.65]
        return gradient
    }()

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.addSublayer(baseLayer)
        layer.addSublayer(glowLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Theme

    /// Paint the miniature for `theme`.
    ///
    /// - Returns: `true` when the theme resolved to a gradient recipe. `false`
    ///   means `.custom`: the view hides itself and the caller is expected to
    ///   surface the user's photo instead.
    @discardableResult
    func apply(theme: AlarmTheme) -> Bool {
        guard let colors = AlarmThemeRendering.gradientColors(for: theme) else {
            isHidden = true
            return false
        }
        // Snap, don't cross-fade: cells are reused while scrolling.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        isHidden = false
        baseLayer.colors = colors
        baseLayer.locations = AlarmThemeRendering.gradientLocations(for: theme)

        if let glow = AlarmThemeRendering.accentGlowColor(for: theme) {
            glowLayer.isHidden = false
            glowLayer.colors = [glow.cgColor, glow.withAlphaComponent(0).cgColor]
        } else {
            glowLayer.isHidden = true
        }
        return true
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.frame = bounds
        let shortSide = min(bounds.width, bounds.height)
        let diameter = shortSide * Self.glowDiameterRatio
        glowLayer.frame = CGRect(
            x: bounds.midX - diameter / 2,
            y: bounds.height - shortSide * Self.glowCentreInsetRatio - diameter / 2,
            width: diameter,
            height: diameter
        )
        CATransaction.commit()
    }
}
