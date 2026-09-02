import os
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

    /// Returned when the trait collection carries no usable scale. 1pt is
    /// drawable — thicker than intended, but visible, which beats a division
    /// by zero. Exposed so a test can pin the value without invoking the
    /// branch, which traps (see `width(for:)`).
    static let degenerateWidth: CGFloat = 1

    /// The width to use *before* a view knows which screen it will draw on —
    /// i.e. when a constraint has to be built in `init`.
    ///
    /// 1/3pt is one device pixel at @3x and two thirds of one at @2x, so it is
    /// never *thicker* than a real hairline on any display iOS ships. That
    /// asymmetry is the whole point: too thin is a faint line, too thick is a
    /// deliberate-looking divider, and only the second one is mistaken for
    /// design.
    ///
    /// The 0.5pt this shipped with in round 2 broke exactly that promise —
    /// at @3x it is one and a half device pixels, thicker than the 1/3pt the
    /// `1.0 / max(displayScale, 2)` it replaced resolved to on every @3x
    /// phone. `testProvisionalWidth_isNeverThickerThanARealHairline` is what
    /// caught it; the constant, not the claim, was the thing that was wrong.
    ///
    /// That the old expression saw a *real* scale in an initialiser is not
    /// folklore — it is pinned by
    /// `testADetachedView_reportsTheSameScaleAsAHostedOne`. The comment this
    /// replaced claimed the opposite ("`displayScale` is `0` until the view
    /// is in a window"), and had it been right, `max(0, 2)` would have made
    /// 0.5 the faithful value. It is not right.
    ///
    /// The cost, stated rather than glossed: at @2x this is two thirds of a
    /// device pixel, so an un-hosted row draws a faintly antialiased line
    /// where 0.5 drew a crisp one. That is the direction this constant errs
    /// in on purpose, and no single number can be exact on both scales — the
    /// exact value comes from the re-read, not from here.
    ///
    /// Pair it with a re-read once the view has a window — a provisional value
    /// that is never replaced is just a wrong value with a nicer name.
    static let provisionalWidth: CGFloat = 1.0 / 3.0

    /// Width of a single device pixel for the display described by `trait`.
    ///
    /// A `displayScale` of 0 is not a benign input: it means the trait
    /// collection was read before it resolved against a screen, which is the
    /// same defect class the header of this file is about. Twelve hand-rolled
    /// copies of this arithmetic each swallowed that case silently; now that
    /// they are one line, that line says so — loudly in DEBUG and CI, and
    /// still drawable in release.
    static func width(for trait: UITraitCollection) -> CGFloat {
        let scale = trait.displayScale
        guard scale > 0 else {
            AppLogger.ui.error(
                """
                AppHairline: displayScale is 0 — a trait collection was read before it \
                resolved against a screen. Drawing a 1pt line instead of a hairline.
                """
            )
            assertionFailure(
                """
                AppHairline.width(for:) got displayScale == 0. The caller read a trait \
                collection before it had a screen — build the constraint with \
                AppHairline.provisionalWidth and re-read it in layoutSubviews.
                """
            )
            return degenerateWidth
        }
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
