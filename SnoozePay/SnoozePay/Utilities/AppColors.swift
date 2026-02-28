import UIKit

/// App-wide color tokens. Uses system colors where possible for automatic dark/light support.
enum AppColors {
    // MARK: - Backgrounds
    static let background = UIColor.systemBackground
    static let surface = UIColor.secondarySystemBackground
    static let surface2 = UIColor.tertiarySystemBackground

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
