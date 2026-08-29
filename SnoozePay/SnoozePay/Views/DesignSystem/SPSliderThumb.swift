import UIKit

/// Money-tinted `UISlider` thumb, rendered for an explicit trait collection.
///
/// `UISlider` exposes no thumb-diameter knob — `setThumbImage` is the only
/// supported path — so both sliders on the alarm form (snooze duration in
/// `SnoozeSliderCell`, volume in `VolumePickerViewController`) draw their own
/// disc into a `UIImage`. That image is a *snapshot*: `UIColor.setFill()`
/// resolves a dynamic token against `UITraitCollection.current` at draw time
/// and the bitmap never re-resolves afterwards. Both call sites built theirs
/// from a `static` helper evaluated once during property initialisation, so
/// the thumb froze whichever theme happened to be current then and survived
/// every later light/dark flip (#492).
///
/// Rendering through an explicit `trait` — and re-rendering from
/// `registerForTraitChanges` — is what makes the thumb follow the theme.
/// Keeping one renderer instead of two copies also means the two sliders on
/// the same screen cannot drift apart again (they already had byte-identical
/// private copies of this recipe).
enum SPSliderThumb {

    /// Resting thumb diameter.
    static let diameter: CGFloat = 28
    /// Slightly larger disc while the user drags.
    static let highlightedDiameter: CGFloat = 30

    /// Alpha of the inner gloss dot. Measured against the disc it sits on:
    /// dark `#0B7451` on `#10B981` = 2.26:1, light `#78AB99` on `#096647` =
    /// 2.69:1 — a decorative highlight, not text, so the 3:1 component floor
    /// does not apply, but it has to stay visible in both themes.
    private static let glossAlpha: CGFloat = 0.45

    /// Install the resting + dragging thumb images for `trait`.
    ///
    /// Call once at setup and again from `registerForTraitChanges`, passing
    /// the host's current `traitCollection`.
    static func install(on slider: UISlider, trait: UITraitCollection) {
        slider.setThumbImage(image(diameter: diameter, trait: trait), for: .normal)
        slider.setThumbImage(image(diameter: highlightedDiameter, trait: trait), for: .highlighted)
    }

    /// Render the disc for one diameter.
    ///
    /// - `money500` fill — bright mint on dark, deep green on light.
    /// - `fgOnMoney` gloss dot — the design system's ink token for a *solid*
    ///   money fill, so it inverts with the disc instead of staying white:
    ///   dark brand ink on the bright dark-theme disc, white on the light
    ///   theme's deep-green one.
    /// - `shadow1` under the disc, taken from the shared recipe rather than a
    ///   black literal so it lightens on the light theme like every card does.
    static func image(diameter: CGFloat, trait: UITraitCollection) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let fill = AppColors.money500.resolvedColor(with: trait)
        let gloss = AppColors.fgOnMoney.resolvedColor(with: trait).withAlphaComponent(glossAlpha)
        let shadow = AppShadow.shadow1(for: trait)
        let shadowColor = shadow.color
            .resolvedColor(with: trait)
            .withAlphaComponent(CGFloat(shadow.opacity))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // 1pt of inset leaves the disc room to cast its shadow inside the
            // bitmap — anything beyond that is clipped by the image bounds.
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 2,
                color: shadowColor.cgColor
            )
            fill.setFill()
            UIBezierPath(ovalIn: rect).fill()
            // Clear the shadow before the gloss so the inner dot doesn't cast
            // a second one over the disc it sits on.
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            gloss.setFill()
            let inner = rect.insetBy(dx: rect.width * 0.32, dy: rect.height * 0.32)
            UIBezierPath(ovalIn: inner).fill()
        }
    }
}
