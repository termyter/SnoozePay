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

    /// Warm orange/gold used for the active "Отложить" pill on the alarm-firing
    /// screen (#E8A838). Kept distinct from `accentOrange`/`snoozeButton` so the
    /// firing UI can preserve its specific Figma hue without leaking that
    /// magic literal into the view code (#79).
    static let alarmFiringSnooze = UIColor(red: 0.91, green: 0.66, blue: 0.22, alpha: 1) // #E8A838
}

/// App-wide spacing constants. T-shirt sizes (`xs`...`xxl`) are the underlying
/// tokens; the semantic aliases below are what new code should reach for so a
/// single design-system bump (e.g. screen inset 16 → 20) only touches one line.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Standard horizontal inset for cards / banners against the screen edge.
    static let screenInset: CGFloat = lg
    /// Vertical gap between logical sections (e.g. between the balance card and
    /// the alarms list).
    static let sectionGap: CGFloat = xl
    /// Vertical gap between rows / items inside the same section.
    static let itemGap: CGFloat = md
    /// Horizontal gap between an icon and its inline label.
    static let inlineGap: CGFloat = sm
    /// Vertical padding inside a card (top / bottom).
    static let cardVerticalPadding: CGFloat = md
    /// Horizontal padding inside a card (leading / trailing of card contents).
    static let cardHorizontalPadding: CGFloat = lg
}

/// App-wide corner radius constants
enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20

    /// Canonical card corner radius — every standalone surface should round to
    /// this value so cards on different screens read as the same primitive.
    static let card: CGFloat = md
}

/// Typography tokens. Section headers had three slightly-different recipes
/// across `SettingsVC` / `CreateAlarmVC` / `StatisticsVC`; route every site
/// through these so future copy / weight changes happen in one place.
enum AppTypography {
    /// Font for table-view section headers and any "ВЕРХНИЙ ТЕКСТ"-style
    /// uppercase label.
    static let sectionHeader: UIFont = .preferredFont(forTextStyle: .footnote)
    static let sectionHeaderColor: UIColor = .secondaryLabel
    /// Letter-spacing applied to uppercase headers (matches iOS system grouped
    /// table-view header tracking).
    static let sectionHeaderKerning: CGFloat = 0.5
}
