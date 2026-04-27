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
        case .mountains:
            // Placeholder gradient until design ships an alpine image asset
            // (tracked as a #151 follow-up). The deep mountain blue →
            // near-black stops still read as "alpine night" until then.
            return [
                UIColor(themeRGB: 0x3D5A80).cgColor,
                UIColor(themeRGB: 0x293241).cgColor
            ]
        case .ocean:
            return [
                UIColor(themeRGB: 0x1A659E).cgColor,
                UIColor(themeRGB: 0x003554).cgColor
            ]
        case .abstract:
            // Money-tinted radial vibe — dark green core fading into the
            // brand near-black ink. Rendered as a vertical gradient here
            // because both consumers (firing screen, picker tile) use a
            // CAGradientLayer; the "radial" character is sold by the stop
            // distribution rather than `.radial` type.
            return [
                UIColor(themeRGB: 0x10B981).cgColor,
                UIColor(themeRGB: 0x064E3B).cgColor,
                UIColor(themeRGB: 0x050912).cgColor
            ]
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
        case .abstract:
            return [0.0, 0.55, 1.0]
        case .mountains, .ocean:
            return [0.0, 1.0]
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
