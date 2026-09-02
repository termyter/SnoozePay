import UIKit

/// One device pixel, expressed in points — the width every hairline border,
/// section outline and divider in the app is drawn with.
///
/// The scale is always read from a **specific** trait collection rather than
/// from `UIScreen.main`. A layer caches whatever number it is handed, and this
/// project has already paid for globals that bake a value from the wrong
/// screen (the same class of bug as caching a `cgColor` resolved against
/// another view's traits). Taking the trait of the view that will actually
/// draw the line keeps the value correct on external displays, in previews and
/// in multi-window setups.
enum AppHairline {

    /// Width of a single device pixel for the display described by `trait`.
    ///
    /// `displayScale` is `0` for a trait collection that has never been
    /// resolved against a screen; the fallback of 1× then yields a plain 1pt
    /// line, which is visible rather than invisible. Detached views on the
    /// current SDK already report a real scale, so the fallback is a guard,
    /// not the normal path.
    static func width(for trait: UITraitCollection) -> CGFloat {
        let scale = trait.displayScale
        guard scale > 0 else { return 1 }
        return 1.0 / scale
    }
}

extension UIView {

    /// Hairline width resolved against *this view's* trait collection, i.e.
    /// the scale of the screen the view is on. Use it wherever a border,
    /// outline or divider should be one device pixel thick.
    ///
    /// Read it at the point of use (`layoutSubviews`,
    /// `traitCollectionDidChange`, a themed-decoration pass) rather than
    /// caching it in `init`: a view can move between displays of different
    /// scale, and the trait collection is what tells us it did.
    var hairlineWidth: CGFloat {
        AppHairline.width(for: traitCollection)
    }
}
