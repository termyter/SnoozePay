import UIKit

/// Atmospheric background for the V3 themed firing screen (#225).
///
/// Spec — `FiringTheme` in `docs/design/v2-handoff/components/SPThemedFiring.jsx`.
/// Three layers, bottom → top:
/// 1. **Base** — 160° diagonal linear gradient (`FIRING_THEMES[theme].bg`).
/// 2. **Scrim** — radial vignette anchored at (50%, 70%): nearly clear at the
///    centre, darkening toward the edges so the white copy stays legible on
///    bright themes.
/// 3. **Glow** — a soft 460pt accent circle whose centre sits 160pt below the
///    bottom edge (`accentSoft → clear at 65%`), selling the "light from
///    below the horizon" cue without a real Gaussian blur.
///
/// The view owns three CAGradientLayers and reflows them on every layout pass
/// so rotation / safe-area changes work without per-frame recompute. Used for
/// every stock theme except `.dawn`, which keeps the tone-reactive
/// `SPDawnBackgroundView` (calm / tense / drained transitions + breathing sun).
final class SPThemedFiringBackgroundView: UIView {

    // MARK: - Geometry constants

    /// CSS `linear-gradient(160deg, …)` direction. 160° clockwise from north
    /// in y-down coordinates is `(sin 160°, −cos 160°) ≈ (0.342, 0.940)` —
    /// mostly downward, drifting right. Half-vector offsets from the centre
    /// give unit start/end points for CAGradientLayer.
    private static let axisStart = CGPoint(x: 0.5 - 0.171, y: 0.5 - 0.470)
    private static let axisEnd = CGPoint(x: 0.5 + 0.171, y: 0.5 + 0.470)

    /// `radial-gradient(circle, accentSoft 0%, transparent 65%)` — 460pt
    /// circle, horizontally centred, its centre 160pt below the bottom edge.
    private static let glowDiameter: CGFloat = 460
    private static let glowBottomOverhang: CGFloat = 160

    // MARK: - Layers

    private let baseLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.startPoint = SPThemedFiringBackgroundView.axisStart
        gradient.endPoint = SPThemedFiringBackgroundView.axisEnd
        return gradient
    }()

    /// `radial-gradient(120% 80% at 50% 70%, black(inner) → black(outer))`.
    /// For `.radial` CAGradientLayer the endPoint deltas define the ellipse
    /// semi-axes: 120% of the width and 80% of the height.
    private let scrimLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.7)
        gradient.endPoint = CGPoint(x: 0.5 + 1.2, y: 0.7 + 0.8)
        gradient.locations = [0.0, 1.0]
        return gradient
    }()

    private let glowLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.locations = [0.0, 0.65]
        return gradient
    }()

    // MARK: - Init

    init(palette: AlarmFiringThemePalette) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.addSublayer(baseLayer)
        layer.addSublayer(scrimLayer)
        layer.addSublayer(glowLayer)
        apply(palette: palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Palette

    private func apply(palette: AlarmFiringThemePalette) {
        baseLayer.colors = palette.backgroundColors.map { $0.cgColor }
        baseLayer.locations = palette.backgroundLocations
        scrimLayer.colors = [
            UIColor.black.withAlphaComponent(palette.scrimInnerAlpha).cgColor,
            UIColor.black.withAlphaComponent(palette.scrimOuterAlpha).cgColor
        ]
        glowLayer.colors = [
            palette.accentSoft.cgColor,
            palette.accentSoft.withAlphaComponent(0).cgColor
        ]
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.frame = bounds
        scrimLayer.frame = bounds
        let diameter = Self.glowDiameter
        glowLayer.frame = CGRect(
            x: bounds.midX - diameter / 2,
            y: bounds.height + Self.glowBottomOverhang - diameter,
            width: diameter,
            height: diameter
        )
        CATransaction.commit()
    }
}
