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

    /// Vertical (top → bottom) gradient stops for a built-in theme. The Dawn
    /// recipe matches the literal layer in `AlarmFiringViewController` so
    /// switching `.dawn` keeps the historical look untouched.
    /// Returns nil for `.custom` — that case renders an image, not a gradient.
    static func gradientColors(for theme: AlarmTheme) -> [CGColor]? {
        switch theme {
        case .dawn:
            return [
                UIColor(themeRGB: 0x14122A).cgColor,
                UIColor(themeRGB: 0x0F1A2E).cgColor,
                UIColor(themeRGB: 0x0A1320).cgColor,
                UIColor(themeRGB: 0x050912).cgColor
            ]
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
            return [0.0, 0.4, 0.7, 1.0]
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

    // MARK: - Custom-image loader

    /// Resolve the user-picked photo for `.custom`. Returns nil for built-in
    /// themes and for `.custom` whose file is no longer on disk (Caches
    /// purge or first launch after restore).
    static func customImage(for theme: AlarmTheme) -> UIImage? {
        guard case .custom(let url) = theme else { return nil }
        return AlarmThemeImageStore.loadImage(at: url)
    }
}

// MARK: - Hex helper (file-scoped)

private extension UIColor {
    /// `0xRRGGBB` literal initializer used by the gradient stop tables above.
    /// File-scoped so it doesn't clash with the identical helper inside
    /// `AlarmFiringViewController`.
    convenience init(themeRGB rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
