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
/// context `accessibilityLabel` (e.g. the alarm card sets «Будильник»). We seed
/// a neutral fallback here so a switch that's never given one isn't announced
/// as an anonymous control.
final class SPSwitch: UISwitch {

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyBrandTint()
        applyFixedSizeContract()
        seedAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyBrandTint()
        applyFixedSizeContract()
        seedAccessibility()
    }

    /// A switch is a fixed-size control: `UISwitch` draws its track and knob at
    /// the intrinsic size **centred in its bounds** and clips to nothing, so a
    /// squeezed frame doesn't shrink the control — it makes it spill out of the
    /// frame on BOTH sides. Auto Layout has no way to know that, and with the
    /// stock 750/750 priorities the switch is as compressible as the label
    /// beside it.
    ///
    /// That tie is what produced #630: in the alarm card the caps label's
    /// trailing is pinned to the switch's leading, so when a long title's
    /// single-line intrinsic width exceeds the run, the deficit can be taken
    /// out of EITHER view at equal cost — the split is degenerate. The engine
    /// took ~38pt out of the switch, whose drawing stayed 62pt wide and,
    /// re-centred in the narrower bounds, slid ~19pt to the right and past the
    /// card edge. The trailing constraint was satisfied the whole time; the
    /// *width* was the thing that moved, which is why probes that measured
    /// `frame.maxX` found nothing wrong.
    ///
    /// Declaring it non-shrinkable here (rather than at each call site —
    /// `SettingsIconRowCell` had already patched the other half of this by
    /// hand) makes the split unique at every title length, and fixes
    /// `ProgressiveScaleCell` too: it pins its text column to the switch the
    /// same way.
    ///
    /// Only the compression side is raised. Hugging stays at the platform's
    /// 750, which already outranks every label's 251, so the switch is not
    /// stretched today — and leaving it optional keeps a stack that legitimately
    /// stretches its trailing container from logging a broken constraint.
    private func applyFixedSizeContract() {
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func seedAccessibility() {
        // Neutral fallback label; call sites override with a contextual one.
        accessibilityLabel = Localized.text("common.switch.accessibility")
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
