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
        // `--sp-switch.is-on { background: var(--sp-grad-money) }` — UISwitch
        // doesn't render a gradient natively, so we fall back to the
        // `money500` flat fill which lines up with the dominant gradient
        // stop and keeps the toggle indistinguishable in motion.
        onTintColor = AppColors.money500
    }
}
