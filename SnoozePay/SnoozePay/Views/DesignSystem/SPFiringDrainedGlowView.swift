import UIKit

/// Red "drained" glow that rises from the bottom of the firing screen in the
/// no-balance state (#227, `SPFiringNoBalanceThemes.jsx`). The same warning
/// glow renders over every theme (and the custom photo), layered above the
/// background but below the content, so the spent-wallet cue is consistent.
///
/// Spec: a 480pt red circle whose centre sits 170pt below the bottom edge —
/// `rgba(244,82,63,.28) → .08 @40% → clear @68%` — breathing on an 8s loop
/// (scale 1 → 1.06). A radial `CAGradientLayer` stands in for the CSS blur 26.
final class SPFiringDrainedGlowView: UIView {

    private static let diameter: CGFloat = 480
    private static let bottomOverhang: CGFloat = 170
    private static let breatheDuration: CFTimeInterval = 8
    private static let breatheKey = "drainedGlowBreathe"

    /// `0xF4523F` = rgba(244, 82, 63). Identical across all themes.
    private static let glowRed = UIColor(red: 244 / 255, green: 82 / 255, blue: 63 / 255, alpha: 1)

    private let glowLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.colors = [
            SPFiringDrainedGlowView.glowRed.withAlphaComponent(0.28).cgColor,
            SPFiringDrainedGlowView.glowRed.withAlphaComponent(0.08).cgColor,
            SPFiringDrainedGlowView.glowRed.withAlphaComponent(0).cgColor
        ]
        gradient.locations = [0.0, 0.40, 0.68]
        return gradient
    }()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.addSublayer(glowLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let diameter = Self.diameter
        glowLayer.frame = CGRect(
            x: bounds.midX - diameter / 2,
            y: bounds.height + Self.bottomOverhang - diameter,
            width: diameter,
            height: diameter
        )
        glowLayer.cornerRadius = diameter / 2
        CATransaction.commit()
    }

    /// Start/stop the 8s breathing pulse alongside the view's visibility so a
    /// hidden glow isn't animating off-screen.
    func setBreathing(_ active: Bool) {
        isHidden = !active
        if active {
            guard glowLayer.animation(forKey: Self.breatheKey) == nil else { return }
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1.0
            pulse.toValue = 1.06
            pulse.duration = Self.breatheDuration / 2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowLayer.add(pulse, forKey: Self.breatheKey)
        } else {
            glowLayer.removeAnimation(forKey: Self.breatheKey)
        }
    }
}
