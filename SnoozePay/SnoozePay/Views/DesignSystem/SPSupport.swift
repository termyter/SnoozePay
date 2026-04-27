import UIKit

/// Internal design-system support: shared gradient stops, motion constants,
/// and small helpers used across the SP* component family.
///
/// Every SP* primitive routes back to these helpers so the visual recipes
/// stay in one place — when the design tokens at
/// `docs/design/snoozepay-2026-04-27/project/tokens.css` change, only this
/// file needs to follow.
enum SPSupport {

    // MARK: - Brand gradients
    //
    // 135° linear gradients sourced from `--sp-grad-{money,pain,warn}` in
    // `tokens.css`. CAGradientLayer expects 0..1 start/end points so the
    // 135° vector resolves to (0, 0) → (1, 1) (top-left → bottom-right).

    static let gradientStart = CGPoint(x: 0, y: 0)
    static let gradientEnd = CGPoint(x: 1, y: 1)

    /// `--sp-grad-money: linear-gradient(135deg, #2EDB9F 0%, #10B981 60%, #0B7A56 100%)`.
    static var moneyGradientColors: [CGColor] {
        [
            AppColors.money400.cgColor,
            AppColors.money500.cgColor,
            AppColors.money700.cgColor
        ]
    }
    static let moneyGradientLocations: [NSNumber] = [0.0, 0.6, 1.0]

    /// `--sp-grad-pain: linear-gradient(135deg, #FFB4A8 0%, #F4523F 55%, #D43A28 100%)`.
    static var painGradientColors: [CGColor] {
        [
            AppColors.pain300.cgColor,
            AppColors.pain500.cgColor,
            AppColors.pain600.cgColor
        ]
    }
    static let painGradientLocations: [NSNumber] = [0.0, 0.55, 1.0]

    /// `--sp-grad-warn: linear-gradient(135deg, #FFD479 0%, #F59E0B 60%, #C97A06 100%)`.
    static var warnGradientColors: [CGColor] {
        [
            AppColors.warn300.cgColor,
            AppColors.warn500.cgColor,
            AppColors.warn600.cgColor
        ]
    }
    static let warnGradientLocations: [NSNumber] = [0.0, 0.6, 1.0]

    // MARK: - Motion (`tokens.css` durations + easings)

    /// `--sp-dur-quick: 140ms` — press/release scale animations.
    static let durationQuick: TimeInterval = 0.140
    /// `--sp-dur-base: 220ms` — segmented indicator slides, switch knob.
    static let durationBase: TimeInterval = 0.220
    /// `--sp-dur-slow: 420ms`.
    static let durationSlow: TimeInterval = 0.420

    /// Approximation of `cubic-bezier(.2,.8,.2,1)` used by `--sp-ease-out`.
    /// `UIView.animate(...)` doesn't accept arbitrary cubic-beziers; the
    /// closest preset (`.curveEaseOut`) gives the right "fast in, soft
    /// settle" character without dropping to CAMediaTimingFunction-only
    /// keyframe animations for every press feedback.
    static let easeOut: UIView.AnimationOptions = [.curveEaseOut]

    // MARK: - Press feedback

    /// Animate a 0.96 scale press (or restore to identity) on a view.
    /// Matches the `.sp-btn:active { transform: scale(.97) }` recipe from
    /// `components.css` (rounded to 0.96 for a slightly more tactile feel
    /// on touch devices).
    static func animatePress(_ view: UIView, pressed: Bool) {
        UIView.animate(
            withDuration: durationQuick,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: {
                view.transform = pressed ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            },
            completion: nil
        )
    }
}

/// Reusable `UIView` wrapping a `CAGradientLayer` that resizes its layer to
/// the view bounds on every layout pass. Internal — exposed only inside the
/// design system so SPButton / SPCard / SPSnoozePrice can share one
/// implementation rather than each rolling its own gradient layer.
final class SPGradientView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer {
        // swiftlint:disable:next force_cast
        layer as! CAGradientLayer
    }

    /// Convenience init that wires up a 135° gradient with the supplied
    /// `cgColor` stops + locations.
    init(colors: [CGColor], locations: [NSNumber]) {
        super.init(frame: .zero)
        gradientLayer.colors = colors
        gradientLayer.locations = locations
        gradientLayer.startPoint = SPSupport.gradientStart
        gradientLayer.endPoint = SPSupport.gradientEnd
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Refresh the underlying `cgColor` stops — call from
    /// `traitCollectionDidChange` so dynamic SwiftUI-style color tokens
    /// re-resolve on light/dark switch. The current SP gradients use brand
    /// hex literals so this is mostly defensive.
    func refresh(colors: [CGColor], locations: [NSNumber]) {
        gradientLayer.colors = colors
        gradientLayer.locations = locations
    }
}
