import UIKit

/// App-wide color tokens. The "money / pain / warn" scales are the SnoozePay
/// brand palette (see `docs/design/snoozepay-2026-04-27/project/tokens.css`);
/// the legacy `accentBlue` / `accentOrange` / `snoozeButton` aliases at the
/// bottom map onto the new scales so existing screens keep compiling until
/// each one is migrated in its own UI issue.
enum AppColors {
    // MARK: - Backgrounds
    static let background = UIColor.systemBackground
    static let surface = UIColor.secondarySystemBackground
    static let surface2 = UIColor.tertiarySystemBackground

    // MARK: - Text
    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let textTertiary = UIColor.tertiaryLabel

    // MARK: - Brand · Money (positive / earnings / "deposit recovered")
    static let money300 = UIColor(hex: 0x5EEAB8)
    static let money400 = UIColor(hex: 0x2EDB9F)
    /// Primary money tone — used for the deposit / balance hero.
    static let money500 = UIColor(hex: 0x10B981)
    static let money600 = UIColor(hex: 0x0E9D6E)
    static let money700 = UIColor(hex: 0x0B7A56)

    // MARK: - Brand · Pain (progressive snooze / penalty / loss)
    static let pain300 = UIColor(hex: 0xFFB4A8)
    static let pain400 = UIColor(hex: 0xFF7A6B)
    /// Default "progressive snooze charged" red.
    static let pain500 = UIColor(hex: 0xF4523F)
    static let pain600 = UIColor(hex: 0xD43A28)

    // MARK: - Brand · Warn (snooze affordance / amber CTA)
    static let warn300 = UIColor(hex: 0xFFD479)
    static let warn400 = UIColor(hex: 0xFFB84D)
    /// Default snooze-button amber.
    static let warn500 = UIColor(hex: 0xF59E0B)
    static let warn600 = UIColor(hex: 0xC97A06)

    // MARK: - Brand · Info
    /// Informational links only — `--sp-info-500` in `tokens.css`.
    static let info500 = UIColor(hex: 0x4F8BFF)

    // MARK: - Theme-aware surfaces (`bg0`...`bg4`)
    //
    // Five-step surface elevation per `tokens.css`. `bg0` is the deepest /
    // app background, `bg4` the top hover/focus surface. Values resolve via
    // `UIColor(dynamicProvider:)` so each token auto-adapts when the system
    // toggles between light and dark, *and* when a single VC overrides its
    // `userInterfaceStyle` (e.g. AlarmFiringViewController forcing dark).
    /// App background — deepest. Dark `#060912`, Light `#F4F6FB`.
    static let bg0 = dynamicColor(dark: 0x060912, light: 0xF4F6FB)
    /// Card / sheet base. Dark `#0E1320`, Light `#FFFFFF`.
    static let bg1 = dynamicColor(dark: 0x0E1320, light: 0xFFFFFF)
    /// Raised card. Dark `#161C2E`, Light `#ECEEF6`.
    static let bg2 = dynamicColor(dark: 0x161C2E, light: 0xECEEF6)
    /// Active chip / sheet header. Dark `#1F2740`, Light `#DFE3F0`.
    static let bg3 = dynamicColor(dark: 0x1F2740, light: 0xDFE3F0)
    /// Hover / focus surface. Dark `#2A3354`, Light `#C9D0E3`.
    static let bg4 = dynamicColor(dark: 0x2A3354, light: 0xC9D0E3)

    // MARK: - Theme-aware foregrounds (`fg1`...`fg4`)
    //
    // Primary → disabled scale. Dark mode tints `#EBEDF5` (near-white) at
    // 1.0 / 0.86 / 0.58 / 0.32 alpha; light mode tints `#0A0F1F` (brand
    // near-black ink) at 1.0 / 0.82 / 0.56 / 0.32. Step scale matches
    // `tokens.css`.
    /// Primary headings & hero numbers.
    static let fg1 = foreground(darkAlpha: 1.0, lightAlpha: 1.0, darkIsPureWhite: true)
    /// Body copy. Dark 86% white-ish, Light 82% near-black.
    static let fg2 = foreground(darkAlpha: 0.86, lightAlpha: 0.82)
    /// Meta. Dark 58%, Light 56%.
    static let fg3 = foreground(darkAlpha: 0.58, lightAlpha: 0.56)
    /// Disabled / placeholder. Dark 32%, Light 32%.
    static let fg4 = foreground(darkAlpha: 0.32, lightAlpha: 0.32)

    /// Text rendered ON top of `money500` fills. Dark mint hue.
    static let fgOnMoney = UIColor(hex: 0x052016)
    /// Text rendered ON top of `pain500` fills.
    static let fgOnPain = UIColor.white
    /// Text rendered ON top of `warn500` fills.
    static let fgOnWarn = UIColor(hex: 0x1A0F00)

    // MARK: - Theme-aware overlays (alpha on white / near-black ink)
    //
    // Dark mode lays white over surfaces (`rgba(255,255,255,X)`); light mode
    // lays the near-black ink (`#080E1E`) at the same alpha so an overlay
    // chip "darkens" on light and "brightens" on dark.
    static let whiteOverlay04 = overlay(alpha: 0.04)
    static let whiteOverlay06 = overlay(alpha: 0.06)
    static let whiteOverlay08 = overlay(alpha: 0.08)
    static let whiteOverlay12 = overlay(alpha: 0.12)
    static let whiteOverlay16 = overlay(alpha: 0.16)
    static let whiteOverlay24 = overlay(alpha: 0.24)

    // MARK: - Theme-aware strokes
    //
    // 1px hairlines for cards and dividers. Same alpha values, opposite ink:
    // white on dark / near-black on light.
    /// 8% hairline.
    static let stroke1 = overlay(alpha: 0.08)
    /// 14% stronger hairline (active state, focus ring).
    static let stroke2 = overlay(alpha: 0.14)
    /// Money-tinted stroke. Dark 45% / Light 55% (per `tokens.css`).
    static let strokeMoney = UIColor { trait in
        let alpha: CGFloat = trait.userInterfaceStyle == .light ? 0.55 : 0.45
        return UIColor(red: 46.0 / 255.0, green: 219.0 / 255.0, blue: 159.0 / 255.0, alpha: alpha)
    }
    /// Pain-tinted stroke. Dark 45% / Light 55%.
    static let strokePain = UIColor { trait in
        let alpha: CGFloat = trait.userInterfaceStyle == .light ? 0.55 : 0.45
        return UIColor(red: 244.0 / 255.0, green: 82.0 / 255.0, blue: 63.0 / 255.0, alpha: alpha)
    }

    // MARK: - Separator
    static let separator = UIColor.separator

    // MARK: - Legacy aliases
    //
    // Existing screens reach for these names. Each one is now a thin alias on
    // top of the brand scales, so a future PR can grep-and-replace call sites
    // without changing the rendered colour.

    /// Legacy "accent" — kept as systemBlue for now (pre-brand info actions).
    /// Migrate sites individually before retiring.
    static let accentBlue = UIColor.systemBlue
    /// Legacy green accent → maps onto the new `money500`.
    static let accentGreen = money500
    /// Legacy orange accent → maps onto the new `warn500`.
    static let accentOrange = warn500
    /// Destructive red → maps onto the new `pain500`.
    static let destructiveRed = pain500

    // MARK: - Button states (legacy)
    /// Snooze button amber → `warn500`.
    static let snoozeButton = warn500
    /// Dismiss button green → `money500`.
    static let dismissButton = money500
    static let disabledButton = UIColor.systemGray

    /// Warm gold used for the active "Поспать ещё" pill on the alarm-firing
    /// screen (#E8A838). Kept as its own literal because the firing UI uses a
    /// slightly warmer hue than `warn500` (#79); migrating it onto a brand
    /// token is its own UI-issue decision.
    static let alarmFiringSnooze = UIColor(red: 0.91, green: 0.66, blue: 0.22, alpha: 1) // #E8A838

    // MARK: - Theme-aware helpers

    /// Resolve a token to either the light or dark hex literal based on the
    /// current trait collection. Used for the surface scale.
    private static func dynamicColor(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark)
        }
    }

    /// Resolve a foreground token. Dark mode tints `#EBEDF5` (or pure white
    /// for `fg1`) at `darkAlpha`; light mode tints the brand near-black ink
    /// `#0A0F1F` at `lightAlpha`. Pure white in dark is needed only for
    /// `fg1` so hero numbers don't acquire a slight off-white cast against
    /// the deepest `bg0` surface.
    private static func foreground(
        darkAlpha: CGFloat,
        lightAlpha: CGFloat,
        darkIsPureWhite: Bool = false
    ) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .light {
                return UIColor(red: 10.0 / 255.0, green: 15.0 / 255.0, blue: 31.0 / 255.0, alpha: lightAlpha)
            }
            if darkIsPureWhite {
                return UIColor(white: 1.0, alpha: darkAlpha)
            }
            return UIColor(red: 235.0 / 255.0, green: 237.0 / 255.0, blue: 245.0 / 255.0, alpha: darkAlpha)
        }
    }

    /// Tint overlay used for `whiteOverlayXX` and `strokeN`. Dark mode lays
    /// `rgba(255,255,255,alpha)`; light mode lays `rgba(10,15,31,alpha)`
    /// (the near-black brand ink) so the same call produces a "darkening"
    /// chip on light and a "brightening" chip on dark.
    private static func overlay(alpha: CGFloat) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .light {
                return UIColor(red: 10.0 / 255.0, green: 15.0 / 255.0, blue: 31.0 / 255.0, alpha: alpha)
            }
            return UIColor(white: 1.0, alpha: alpha)
        }
    }
}

/// App-wide spacing constants. The 4px grid (`sp1`...`sp10`) is the underlying
/// design-token (see `tokens.css`); the t-shirt aliases (`xs`...`xxl`) and the
/// semantic aliases (`screenInset`, `cardVerticalPadding`, ...) are kept so
/// existing call sites keep compiling. New code should reach for the `spN`
/// tokens directly so a single design-system bump touches one line.
enum AppSpacing {
    // MARK: - 4px grid (canonical)
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20
    static let sp6: CGFloat = 24
    static let sp7: CGFloat = 32
    static let sp8: CGFloat = 40
    static let sp9: CGFloat = 56
    static let sp10: CGFloat = 72

    // MARK: - Legacy t-shirt aliases (pre-token)
    static let xs: CGFloat = sp1   // 4
    static let sm: CGFloat = sp2   // 8
    static let md: CGFloat = sp3   // 12
    static let lg: CGFloat = sp4   // 16
    static let xl: CGFloat = sp6   // 24
    static let xxl: CGFloat = sp7  // 32

    // MARK: - Semantic aliases
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

/// App-wide corner radius constants. `xs`/`sm`/`md`/`lg` are pre-token aliases;
/// `xl`/`r2xl`/`pill` are new design-token additions matching `tokens.css`.
enum AppRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 8     // legacy alias of xs
    static let md: CGFloat = 12
    static let lg: CGFloat = 16    // legacy lg (old AppRadius.lg = 16)
    static let xl: CGFloat = 28
    /// "2xl" — Swift identifiers can't start with a digit, hence `r2xl`.
    static let r2xl: CGFloat = 36
    /// Pill / fully-rounded — call sites typically clamp to `bounds.height/2`,
    /// but this constant keeps intent explicit and matches `tokens.css`.
    static let pill: CGFloat = 999

    /// Canonical card corner radius — every standalone surface should round to
    /// this value so cards on different screens read as the same primitive.
    static let card: CGFloat = md
}

/// Typography roles from `tokens.css`. Each role returns a configured `UIFont`
/// resolved via `AppFonts` (currently falls back to system fonts; see
/// `AppFonts` doc comment for the migration plan).
///
/// Mono roles (`moneyXl`/`moneyLg`/`moneyMd`/`moneySm`/`clockXl`/`clockLg`)
/// use JetBrains Mono so digits column-align across rows.
enum AppTypography {

    // MARK: - Display & headings (Manrope)

    /// Hero number / display metric — 88pt heavy.
    static var display: UIFont { AppFonts.sans(.extrabold, 88) }
    /// h1 — 32pt extrabold.
    static var h1: UIFont { AppFonts.sans(.extrabold, 32) }
    /// h2 — 24pt bold.
    static var h2: UIFont { AppFonts.sans(.bold, 24) }
    /// h3 — 20pt bold.
    static var h3: UIFont { AppFonts.sans(.bold, 20) }
    /// h4 — 17pt bold.
    static var h4: UIFont { AppFonts.sans(.bold, 17) }

    // MARK: - Body (Manrope)

    /// Large body — 17pt medium.
    static var bodyLg: UIFont { AppFonts.sans(.medium, 17) }
    /// Body — 15pt medium.
    static var body: UIFont { AppFonts.sans(.medium, 15) }
    /// Meta / secondary — 13pt medium.
    static var meta: UIFont { AppFonts.sans(.medium, 13) }
    /// Caps label — 12pt bold uppercase. Tracking applied per-attributedString
    /// (see `capsKerning`).
    static var caps: UIFont { AppFonts.sans(.bold, 12) }
    /// Letter-spacing for `caps` (matches `+0.12em` in `tokens.css`).
    static let capsKerning: CGFloat = 12 * 0.12

    // MARK: - Buttons (Manrope)

    /// Primary button label — 16pt bold.
    static var button: UIFont { AppFonts.sans(.bold, 16) }
    /// Compact button label — 14pt bold.
    static var buttonSm: UIFont { AppFonts.sans(.bold, 14) }

    // MARK: - Money / numeric (JetBrains Mono)

    /// Hero balance — 56pt mono bold.
    static var moneyXl: UIFont { AppFonts.mono(.bold, 56) }
    /// Section balance — 32pt mono bold.
    static var moneyLg: UIFont { AppFonts.mono(.bold, 32) }
    /// Inline amount — 20pt mono bold.
    static var moneyMd: UIFont { AppFonts.mono(.bold, 20) }
    /// Caption amount / row total — 14pt mono semibold.
    static var moneySm: UIFont { AppFonts.mono(.semibold, 14) }

    // MARK: - Clock (JetBrains Mono)

    /// Alarm-firing clock — 96pt mono ultralight.
    static var clockXl: UIFont { AppFonts.mono(.ultralight, 96) }
    /// Card clock — 64pt mono light.
    static var clockLg: UIFont { AppFonts.mono(.light, 64) }

    // MARK: - Legacy section header
    //
    // Pre-token "ВЕРХНИЙ ТЕКСТ" recipe used by SettingsVC / CreateAlarmVC /
    // StatisticsVC. Kept as-is so those screens keep rendering identically
    // until each one migrates onto `caps` in its own UI issue.

    /// Font for table-view section headers. Use `caps` instead in new code.
    static let sectionHeader: UIFont = .preferredFont(forTextStyle: .footnote)
    static let sectionHeaderColor: UIColor = .secondaryLabel
    /// Letter-spacing applied to uppercase headers (matches iOS system grouped
    /// table-view header tracking).
    static let sectionHeaderKerning: CGFloat = 0.5
}

// MARK: - UIColor hex helper

private extension UIColor {
    /// Convenience initializer for `0xRRGGBB` literals so the brand-token
    /// constants above read as in `tokens.css`. Alpha defaults to 1.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
