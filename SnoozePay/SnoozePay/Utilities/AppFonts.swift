import UIKit

/// Brand font families for SnoozePay.
///
/// **Status — placeholder fallback.**
/// The design system specifies Manrope (UI / headings, weights 400/500/600/700/800)
/// and JetBrains Mono (money, timers, clocks; weights 400/500/600/700). The .ttf
/// binaries are not bundled in this PR so every accessor below currently falls
/// back to the matching iOS system font (`.systemFont` for sans, `.monospacedSystemFont`
/// for mono).
///
/// TODO: PM adds Manrope/JetBrainsMono .ttf to `SnoozePay/Resources/Fonts/` and
/// registers them under `UIAppFonts` in `Info.plist` (a separate manual step —
/// `Info.plist` is a PM-only / no-touch file, so this PR does **not** seed the
/// keys), then flips `brandFontsAvailable = true`. The `font(family:weight:size:)`
/// lookup below will then start resolving the PostScript names instead of
/// returning system fonts; until that happens the API is safe to call (system
/// fallback always succeeds).
///
/// Required files once PM does the manual step:
/// - `Manrope-{Regular,Medium,SemiBold,Bold,ExtraBold}.ttf`
/// - `JetBrainsMono-{Regular,Medium,SemiBold,Bold}.ttf`
///
/// Sources:
/// - Manrope: https://fonts.google.com/specimen/Manrope
/// - JetBrains Mono: https://fonts.google.com/specimen/JetBrains+Mono
///
/// Both fonts are SIL OFL 1.1 licensed (free for commercial use, embed in app).
enum AppFonts {

    // MARK: - Families

    enum Family {
        case sans   // Manrope
        case mono   // JetBrainsMono
    }

    // MARK: - Weights
    //
    // Mapped to PostScript names of the bundled fonts. `UIFont.Weight` is the
    // system-font analogue used as a fallback when the brand font cannot be
    // resolved (e.g. in unit tests or before the .ttf files land).

    enum Weight {
        case regular     // 400
        case medium      // 500
        case semibold    // 600
        case bold        // 700
        case extrabold   // 800 (Manrope only)
        case ultralight  // 100 (system fallback only — used by clockXl)
        case light       // 300 (system fallback only — used by clockLg)

        /// PostScript name suffix for Manrope.
        fileprivate var manropeSuffix: String {
            switch self {
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .semibold: return "SemiBold"
            case .bold: return "Bold"
            case .extrabold: return "ExtraBold"
            case .ultralight: return "ExtraLight" // Manrope's lightest cut
            case .light: return "ExtraLight"
            }
        }

        /// PostScript name suffix for JetBrains Mono.
        fileprivate var jetBrainsMonoSuffix: String {
            switch self {
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .semibold: return "SemiBold"
            case .bold: return "Bold"
            case .extrabold: return "Bold"      // JBM tops out at Bold
            case .ultralight: return "Thin"     // JBM has Thin (100)
            case .light: return "Light"         // JBM has Light (300)
            }
        }

        fileprivate var systemWeight: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .extrabold: return .heavy
            case .ultralight: return .ultraLight
            case .light: return .light
            }
        }
    }

    // MARK: - Public API

    /// Returns a font for the given family / weight / size, falling back to the
    /// system font when the brand .ttf isn't registered yet.
    static func font(family: Family, weight: Weight, size: CGFloat) -> UIFont {
        if brandFontsAvailable, let custom = customFont(family: family, weight: weight, size: size) {
            return custom
        }
        switch family {
        case .sans:
            return .systemFont(ofSize: size, weight: weight.systemWeight)
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: weight.systemWeight)
        }
    }

    /// Convenience: Manrope at given weight + size.
    static func sans(_ weight: Weight, _ size: CGFloat) -> UIFont {
        font(family: .sans, weight: weight, size: size)
    }

    /// Convenience: JetBrains Mono at given weight + size.
    static func mono(_ weight: Weight, _ size: CGFloat) -> UIFont {
        font(family: .mono, weight: weight, size: size)
    }

    // MARK: - Private

    /// Flip to `true` once PM bundles the .ttf binaries and registers them under
    /// `UIAppFonts` in `Info.plist` (manual no-touch-file step).
    /// Deliberately gated so we can ship the API surface without worrying that
    /// half-loaded fonts will quietly use the wrong glyphs at runtime.
    private static let brandFontsAvailable: Bool = false

    private static func customFont(family: Family, weight: Weight, size: CGFloat) -> UIFont? {
        let name: String
        switch family {
        case .sans:
            name = "Manrope-\(weight.manropeSuffix)"
        case .mono:
            name = "JetBrainsMono-\(weight.jetBrainsMonoSuffix)"
        }
        return UIFont(name: name, size: size)
    }
}
