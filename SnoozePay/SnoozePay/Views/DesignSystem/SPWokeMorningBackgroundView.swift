import UIKit

/// Atmospheric background for the WokeMorning summary screen (#228).
///
/// Spec — `docs/design/v2-handoff/components/SPWokeMorning.jsx`. A single
/// mint-green "misty morning" theme regardless of the alarm's firing theme.
/// Four layers, bottom → top:
/// 1. **Base sky** — 180° vertical linear gradient `#244E45 → #16332E (30%)
///    → #0B1C1A (60%) → #07110F (100%)`, painted over an opaque `#060F0E`.
/// 2. **Top mint mist** — a 560pt radial circle whose centre sits 160pt above
///    the top edge: `rgba(158,230,204,.32) 0% → .10 38% → clear 68%`.
/// 3. **Horizon hairline** — a 1pt horizontal line at 44% height:
///    `clear → rgba(158,230,204,.10) 50% → clear`.
/// 4. **Bottom green glow** — a 520pt radial circle 160pt below the bottom
///    edge: `rgba(46,219,159,.28) 0% → .06 45% → clear 72%`.
///
/// UIKit has no cheap layer blur, so the JSX `filter: blur()` is approximated
/// by the soft radial falloff of each gradient. The view owns its layers and
/// reflows them on every layout pass (rotation / safe-area), mirroring
/// `SPThemedFiringBackgroundView`.
final class SPWokeMorningBackgroundView: UIView {

    // MARK: - Geometry constants

    /// Top mist — 560pt circle, horizontally centred, centre 160pt above top.
    private static let mistDiameter: CGFloat = 560
    private static let mistTopOverhang: CGFloat = 160

    /// Bottom glow — 520pt circle, horizontally centred, centre 160pt below.
    private static let glowDiameter: CGFloat = 520
    private static let glowBottomOverhang: CGFloat = 160

    /// Horizon hairline sits at 44% of the height, 1pt tall.
    private static let horizonFraction: CGFloat = 0.44

    private static let mistColor = UIColor(hex: 0x9EE6CC)
    /// Byte-identical to the brand `AppColors.money400` token — reuse it rather
    /// than re-literal the hex (design-system single-source-of-truth).
    private static let glowColor = AppColors.money400

    // MARK: - Layers

    /// `linear-gradient(180deg, …)` — top → bottom, so the unit axis is
    /// (0.5, 0) → (0.5, 1).
    private let baseLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.colors = [
            UIColor(hex: 0x244E45).cgColor,
            UIColor(hex: 0x16332E).cgColor,
            UIColor(hex: 0x0B1C1A).cgColor,
            UIColor(hex: 0x07110F).cgColor
        ]
        gradient.locations = [0.0, 0.3, 0.6, 1.0]
        return gradient
    }()

    private let mistLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.colors = [
            mistColor.withAlphaComponent(0.32).cgColor,
            mistColor.withAlphaComponent(0.10).cgColor,
            mistColor.withAlphaComponent(0).cgColor
        ]
        gradient.locations = [0.0, 0.38, 0.68]
        return gradient
    }()

    private let horizonLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = [
            mistColor.withAlphaComponent(0).cgColor,
            mistColor.withAlphaComponent(0.10).cgColor,
            mistColor.withAlphaComponent(0).cgColor
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        return gradient
    }()

    private let glowLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.colors = [
            glowColor.withAlphaComponent(0.28).cgColor,
            glowColor.withAlphaComponent(0.06).cgColor,
            glowColor.withAlphaComponent(0).cgColor
        ]
        gradient.locations = [0.0, 0.45, 0.72]
        return gradient
    }()

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor(hex: 0x060F0E)
        layer.addSublayer(baseLayer)
        layer.addSublayer(mistLayer)
        layer.addSublayer(horizonLayer)
        layer.addSublayer(glowLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        baseLayer.frame = bounds

        // Centre 160pt above top edge → origin.y = centreY - radius.
        let mist = Self.mistDiameter
        mistLayer.frame = CGRect(
            x: bounds.midX - mist / 2,
            y: -(Self.mistTopOverhang + mist / 2),
            width: mist,
            height: mist
        )

        horizonLayer.frame = CGRect(
            x: 0,
            y: (bounds.height * Self.horizonFraction).rounded(),
            width: bounds.width,
            height: 1
        )

        let glow = Self.glowDiameter
        glowLayer.frame = CGRect(
            x: bounds.midX - glow / 2,
            y: bounds.height + Self.glowBottomOverhang - glow / 2,
            width: glow,
            height: glow
        )

        CATransaction.commit()
    }
}

// MARK: - Hex helper (file-scoped)

private extension UIColor {
    /// `0xRRGGBB` literal initializer for this screen's mint atmosphere stops.
    /// File-scoped copy — `private` is file-scope in Swift, mirroring the
    /// identical helpers in the firing `+Layout` / `+Theme` / `+Snoozed` files
    /// (the brand-token `UIColor(hex:)` in AppColors is itself `private` and not
    /// visible across files).
    convenience init(hex rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
