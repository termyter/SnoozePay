import UIKit

/// Brand-tinted UISwitch.
///
/// `UISwitch` already gives us the platform-native physics and a11y for free
/// — the SP recipe just needs the `onTintColor` flipped to the money tone so
/// the toggle reads as "money / commit" instead of the default iOS green.
///
/// Subclassing (rather than a factory) keeps the type information attached
/// to call sites: a screen that exposes `let pushToggle = SPSwitch()` makes
/// the brand intent obvious in code review.
final class SPSwitch: UISwitch {

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyBrandTint()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyBrandTint()
    }

    private func applyBrandTint() {
        // `--sp-switch.is-on { background: var(--sp-grad-money) }` and a knob
        // that translates on `--sp-ease-spring`.
        //
        // Documented limitation (per #287): a true gradient on-track + the
        // spring knob physics would require fully re-implementing the control
        // (custom track view + thumb + pan gesture + a11y), which is a high
        // regression risk for a tiny visual delta — the `money500` flat fill
        // already lines up with the dominant gradient stop and is
        // indistinguishable from the gradient in motion. UISwitch also owns its
        // own native (already springy) knob animation, so we inherit a close
        // match to `--sp-ease-spring` for free. If a future task does build the
        // custom track, `SPSupport.animateSpring` provides the matching curve.
        onTintColor = AppColors.money500
    }
}
