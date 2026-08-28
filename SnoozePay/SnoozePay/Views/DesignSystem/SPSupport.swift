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

    /// Deep-green promo fill used by the referral hero. `tokens.css` has no
    /// named token for it — the prototype inlines
    /// `linear-gradient(135deg, #1A2810 0%, #2C4A1F 50%, #4F8A3A 100%)` — so
    /// the stops live on `AppColors.heroDeep*`, which resolve per theme.
    ///
    /// Takes an explicit `trait` rather than reading `UITraitCollection.current`
    /// because the result lands in `CAGradientLayer.colors`, which stores plain
    /// `CGColor`s that never re-resolve: the owner must re-apply them on a
    /// theme flip (see `ReferralHeroCardView`).
    static func heroDeepGradientColors(for trait: UITraitCollection) -> [CGColor] {
        [AppColors.heroDeep700, AppColors.heroDeep500, AppColors.heroDeep300]
            .map { $0.resolvedColor(with: trait).cgColor }
    }
    static let heroDeepGradientLocations: [NSNumber] = [0.0, 0.5, 1.0]

    // MARK: - Progressive (warn → pain) interpolation

    /// Linear-interpolate between the warn and pain gradient stops to render
    /// the "the human keeps snoozing, surface keeps reddening" treatment
    /// from #139. `intensity` 0 returns pure warn, 1 returns pure pain; the
    /// shared `warnGradientLocations` are reused so the visual rhythm of the
    /// stops doesn't shift mid-fade.
    static func progressiveGradientColors(intensity: Double) -> [CGColor] {
        let clamped = max(0.0, min(1.0, intensity))
        return [
            lerpColor(AppColors.warn300, AppColors.pain300, progress: clamped).cgColor,
            lerpColor(AppColors.warn500, AppColors.pain500, progress: clamped).cgColor,
            lerpColor(AppColors.warn600, AppColors.pain600, progress: clamped).cgColor
        ]
    }

    /// Linear interpolation between two `UIColor` instances in sRGB.
    /// `t` is clamped to `0...1` — out-of-range inputs collapse to the
    /// nearest endpoint. Internal helper for the progressive snooze treatment;
    /// also re-used by the on-fill text colour so the typography contrast
    /// tracks the gradient.
    static func lerpColor(_ from: UIColor, _ toColor: UIColor, progress: Double) -> UIColor {
        let clamped = CGFloat(max(0.0, min(1.0, progress)))
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        from.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        toColor.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)
        return UIColor(
            red: fromR + (toR - fromR) * clamped,
            green: fromG + (toG - fromG) * clamped,
            blue: fromB + (toB - fromB) * clamped,
            alpha: fromA + (toA - fromA) * clamped
        )
    }

    // MARK: - Motion (`tokens.css` durations + easings)

    /// `--sp-dur-quick: 140ms` — press/release scale animations.
    static let durationQuick: TimeInterval = 0.140
    /// `--sp-dur-base: 220ms` — segmented indicator slides, switch knob.
    static let durationBase: TimeInterval = 0.220
    /// `--sp-dur-slow: 420ms`.
    static let durationSlow: TimeInterval = 0.420
    /// `--sp-dur-anxious: 900ms` — pulse cadence for "things are escalating"
    /// affordances (progressive-snooze indicator dot, low-balance flicker).
    /// Slower than a heartbeat so it reads as worry, not panic.
    static let durationAnxious: TimeInterval = 0.900

    /// Approximation of `cubic-bezier(.2,.8,.2,1)` used by `--sp-ease-out`.
    /// `UIView.animate(...)` doesn't accept arbitrary cubic-beziers; the
    /// closest preset (`.curveEaseOut`) gives the right "fast in, soft
    /// settle" character without dropping to CAMediaTimingFunction-only
    /// keyframe animations for every press feedback.
    static let easeOut: UIView.AnimationOptions = [.curveEaseOut]

    // MARK: - Spring easing

    /// Approximation of `--sp-ease-spring: cubic-bezier(.34,1.56,.64,1)` — the
    /// overshoot curve the design uses for the switch knob and "success"
    /// moments. The `> 1` control point produces a small bounce past the
    /// target, which `UISpringTimingParameters` reproduces with a light damping
    /// ratio. Tuned so the settle feels playful but doesn't visibly oscillate.
    static let springDampingRatio: CGFloat = 0.72
    static let springInitialVelocity = CGVector(dx: 0, dy: 0.4)

    /// Run `animations` with the spring overshoot curve over `duration`
    /// (defaults to `durationBase`). Use for switch toggles and success
    /// confirmations where the `cubic-bezier(.34,1.56,.64,1)` bounce is wanted;
    /// keep plain `animatePress` for the flat press scale.
    static func animateSpring(
        duration: TimeInterval = durationBase,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        let timing = UISpringTimingParameters(
            dampingRatio: springDampingRatio,
            initialVelocity: springInitialVelocity
        )
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations(animations)
        if let completion = completion {
            animator.addCompletion { _ in completion(true) }
        }
        animator.startAnimation()
    }

    // MARK: - Press feedback

    /// Animate a 0.97 scale press (or restore to identity) on a view.
    /// Matches the `.sp-btn:active { transform: scale(.97) }` recipe from
    /// `components.css`. Unified across SPButton + SPSnoozePrice +
    /// SPAmountPreset so the whole design system pulses by the same delta
    /// instead of each component picking its own scale.
    static func animatePress(_ view: UIView, pressed: Bool) {
        UIView.animate(
            withDuration: durationQuick,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: {
                view.transform = pressed ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            },
            completion: nil
        )
    }

    // MARK: - Shared label constructors

    /// Caps-styled section label — 12pt bold uppercase with the token
    /// tracking. Lived in three near-identical private copies across the
    /// statistics cards before #348 review; one owner now.
    static func makeCapsLabel(_ text: String, color: UIColor = AppColors.fg3) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: color
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Mono money/clock value label used by the statistics summary columns.
    /// Shrinks a touch rather than truncating — three columns of a
    /// four-digit rouble total get tight on the narrowest devices.
    static func makeMoneyValueLabel(
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.moneyMd
        label.textColor = color
        label.textAlignment = alignment
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Meta-styled caption — 13pt fg3, optionally pre-filled and aligned.
    static func makeMetaLabel(
        _ text: String? = nil,
        alignment: NSTextAlignment = .left,
        color: UIColor = AppColors.fg3
    ) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = color
        label.text = text
        label.textAlignment = alignment
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
