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
///
/// Accessibility: because this is a real `UISwitch`, VoiceOver gets the native
/// `.button`/switch trait, the on/off value and double-tap activation for free
/// — there's nothing custom to re-implement. What it can't infer is *which*
/// setting the toggle controls, so every call site is responsible for setting a
/// context `accessibilityLabel` (e.g. the alarm card sets "Будильник"). We seed
/// a neutral fallback here so a switch that's never given one isn't announced
/// as an anonymous control.
final class SPSwitch: UISwitch {

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyBrandTint()
        seedAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyBrandTint()
        seedAccessibility()
    }

    private func seedAccessibility() {
        // Neutral fallback label; call sites override with a contextual one.
        accessibilityLabel = "Переключатель"
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
