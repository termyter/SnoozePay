import UIKit

/// Per-theme accent steps for the statistics screen (#493).
///
/// After #489 the brand scales are theme-aware, and every light step is solved
/// for a ROLE against the raised card `bg2`: `300` is decorative (3:1), `400`
/// is large text (4.5:1), `500` is body text (6:1). The dark canon tints the
/// screen's small accents — the "СЕРИЯ" caps, the worst-weekday value, the
/// heatmap tooltip status — with the bright `300` step, which is 10–12:1 on the
/// dark card. The same token in light lands at 3.01:1, i.e. below the 4.5:1 AA
/// floor for the 11–12pt type those accents actually use.
///
/// So the fix belongs at the call site, not in the token: dark keeps `300`
/// byte-identical, light steps down to `500`.
///
///     tone      light    dark
///     money     6.03:1   11.24:1
///     warn      6.03:1   12.06:1
///     pain      6.01:1    9.96:1
///
/// (Measured on `bg2`; `AppColorsContrastTests` pins the underlying steps.)
enum StatisticsAccentTones {

    /// Money accent for TEXT — `money300` on dark, `money500` on light.
    static let money = tone(dark: AppColors.money300, light: AppColors.money500)

    /// Warn accent for TEXT — `warn300` on dark, `warn500` on light. Light
    /// warn is bronze, not amber: no step of the amber ramp carries text on a
    /// near-white surface (`warn500` dark is 1.85:1 there). This is the INK
    /// half of the warn role (#520) and must never be swapped for `warnFill*`.
    static let warn = tone(dark: AppColors.warn300, light: AppColors.warn500)

    /// Pain accent for TEXT — `pain300` on dark, `pain500` on light.
    static let pain = tone(dark: AppColors.pain300, light: AppColors.pain500)

    private static func tone(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { trait in
            let source = trait.userInterfaceStyle == .light ? light : dark
            return source.resolvedColor(with: trait)
        }
    }
}
