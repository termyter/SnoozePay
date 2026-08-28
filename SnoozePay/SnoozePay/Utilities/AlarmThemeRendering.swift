import UIKit

/// Visual recipes shared between the theme picker tile, the leading strip on
/// `AlarmCell`, and the `AlarmFiringViewController` background (#151).
///
/// Every consumer reaches for the same gradient stops so the tile preview the
/// user picks really matches the firing screen they see. Custom photos load
/// out of `AlarmThemeImageStore`; if the file is missing the helpers return
/// the Dawn gradient so the firing screen is never blank.
enum AlarmThemeRendering {

    // MARK: - Gradient stops

    /// Gradient stops for a built-in theme. Every stock theme resolves to the
    /// stops its own firing background actually paints: Dawn mirrors the calm
    /// `SPDawnBackgroundView` base, the other five mirror
    /// `AlarmFiringThemePalette`. Before #463 Dawn returned a stale pre-#151
    /// blue-black recipe that matched no screen in the app and made the picker
    /// read as a single dark surface.
    /// Returns nil for `.custom` — that case renders an image, not a gradient.
    static func gradientColors(for theme: AlarmTheme) -> [CGColor]? {
        switch theme {
        case .dawn:
            return SPDawnBackgroundView.calmBaseColors.map { $0.cgColor }
        case .mountains, .ocean, .forest, .neon, .abstract:
            // FIRING_THEMES stops from the v3 handoff (`SPThemedFiring.jsx`)
            // via `AlarmFiringThemePalette` — single table so the picker tile
            // / alarm-cell strip and the firing background can't drift (#225).
            return AlarmFiringThemePalette.palette(for: theme)?
                .backgroundColors.map { $0.cgColor }
        case .custom:
            return nil
        }
    }

    /// Stop locations that pair with `gradientColors(for:)`. Optional so
    /// CAGradientLayer auto-distributes when the theme exposes only two
    /// colours.
    static func gradientLocations(for theme: AlarmTheme) -> [NSNumber]? {
        switch theme {
        case .dawn:
            return SPDawnBackgroundView.calmBaseLocations
        case .mountains, .ocean, .forest, .neon, .abstract:
            // Paired with the `AlarmFiringThemePalette` stop tables above —
            // midpoint pinned at 50% per the design's
            // `linear-gradient(160deg, … 0%, … 50%, … 100%)` recipe
            // (Abstract is the lone two-stop theme).
            return AlarmFiringThemePalette.palette(for: theme)?.backgroundLocations
        case .custom:
            return nil
        }
    }

    // MARK: - Accent glow

    /// Colour of the bottom-centre radial glow that pairs with
    /// `gradientColors(for:)` in `SPThemePreviewView` (#463).
    ///
    /// It is the same light-from-below-the-horizon cue the firing screen
    /// paints — the calm sun for Dawn, `accentSoft` for the five themed
    /// backgrounds — and it is what makes a tile identifiable at 100pt:
    /// the base stops alone read as "dark" on Dawn / Forest / Abstract.
    /// Returns nil for `.custom`, which shows a photo and no glow.
    static func accentGlowColor(for theme: AlarmTheme) -> UIColor? {
        switch theme {
        case .dawn:
            return SPDawnBackgroundView.calmSunCoreColor
        case .mountains, .ocean, .forest, .neon, .abstract:
            return AlarmFiringThemePalette.palette(for: theme)?.accentSoft
        case .custom:
            return nil
        }
    }

    // MARK: - Custom-image loader

    /// Resolve the user-picked photo for `.custom`. Returns nil for built-in
    /// themes and for `.custom` whose file is no longer on disk (Caches
    /// purge or first launch after restore).
    static func customImage(for theme: AlarmTheme) -> UIImage? {
        guard case .custom(let url) = theme else { return nil }
        return AlarmThemeImageStore.loadImage(at: url)
    }
}

// No hex helper here any more: every stop this file hands out now comes from
// `SPDawnBackgroundView` or `AlarmFiringThemePalette`, so there is exactly one
// place per theme where a literal colour is written down (#463).
