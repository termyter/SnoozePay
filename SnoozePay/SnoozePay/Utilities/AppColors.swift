import UIKit

/// App-wide color tokens. Uses system colors where possible for automatic dark/light support.
enum AppColors {
    // MARK: - Backgrounds
    static let background = UIColor.systemBackground
    static let surface = UIColor.secondarySystemBackground
    static let surface2 = UIColor.tertiarySystemBackground

    // MARK: - Cards
    /// Fill colour for card-like containers. Same as `surface` but named after
    /// its semantic role so `UIView.applyCardStyle()` callers don't have to
    /// reach for `surface`. Re-bind here if cards ever need a different tint
    /// (e.g. brighter than other secondary surfaces) without changing call sites.
    static let cardSurface = UIColor.secondarySystemBackground
    /// Hairline border colour for cards. `UIColor.separator` is fully opaque
    /// grey in light mode (visible against `secondarySystemBackground`) and a
    /// subtle dim in dark mode — so a single token works for both.
    static let cardBorder = UIColor.separator
    /// Background tint for screens that host insetGrouped tables of cards.
    /// Light mode darkens the system grouped background a notch so each card
    /// (`secondarySystemBackground`) reads as a distinct surface — the default
    /// `systemGroupedBackground` (#F2F2F7) and `secondarySystemBackground`
    /// (#FFFFFF) are only ~5% luminance apart, which renders as one
    /// undifferentiated block. Dark mode keeps the system colour: contrast is
    /// already sufficient and overriding would break trait-aware tinting.
    static let groupedBackground: UIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(white: 0.92, alpha: 1.0) // ~#EBEBEB, ~+5% darker than #F2F2F7
    }

    // MARK: - Text
    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let textTertiary = UIColor.tertiaryLabel

    // MARK: - Accent
    static let accentBlue = UIColor.systemBlue
    static let accentGreen = UIColor(red: 0.19, green: 0.82, blue: 0.34, alpha: 1) // #30D158
    static let accentOrange = UIColor.systemOrange
    static let destructiveRed = UIColor.systemRed

    // MARK: - Separator
    static let separator = UIColor.separator

    // MARK: - Button states
    static let snoozeButton = UIColor.systemOrange
    static let dismissButton = UIColor(red: 0.19, green: 0.82, blue: 0.34, alpha: 1) // #30D158
    static let disabledButton = UIColor.systemGray
}

/// App-wide spacing constants
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// App-wide corner radius constants
enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}
