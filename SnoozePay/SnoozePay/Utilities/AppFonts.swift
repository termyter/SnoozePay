import UIKit

/// Brand font families for SnoozePay.
///
/// The design system specifies Manrope (UI / headings, weights 200/400/500/600/
/// 700/800) and JetBrains Mono (money, timers, clocks; weights 200/300/400/500/
/// 600/700). The static .ttf cuts live in `SnoozePay/Resources/Fonts/` and are
/// registered under `UIAppFonts` in `Info.plist`:
/// - `Manrope-{ExtraLight,Regular,Medium,SemiBold,Bold,ExtraBold}.ttf`
/// - `JetBrainsMono-{ExtraLight,Light,Regular,Medium,SemiBold,Bold}.ttf`
///
/// `brandFontsAvailable` probes the registry once at first use; when a face is
/// missing (e.g. a stripped test bundle) every accessor falls back to the
/// matching iOS system font (`.systemFont` for sans, `.monospacedSystemFont`
/// for mono), so the API always succeeds.
///
/// Sources:
/// - Manrope: https://fonts.google.com/specimen/Manrope
/// - JetBrains Mono: https://github.com/JetBrains/JetBrainsMono (v2.304)
///
/// Both fonts are SIL OFL 1.1 licensed (free for commercial use, embed in app);
/// license texts ship next to the .ttf files (`OFL-Manrope.txt`,
/// `OFL-JetBrainsMono.txt`).
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
        case ultralight  // 200 ExtraLight — used by clockXl (tokens.css clock-xl weight 200)
        case light       // 300 — used by clockLg

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
            case .extrabold: return "Bold"          // bundled JBM set tops out at Bold
            case .ultralight: return "ExtraLight"   // JBM ExtraLight (200) per tokens.css clock-xl
            case .light: return "Light"             // JBM Light (300)
            }
        }

        fileprivate var systemWeight: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .extrabold: return .heavy
            case .ultralight: return .thin // system thin ≈ 200, matches JBM ExtraLight
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

    /// Runtime probe, evaluated once (static-let caching): true when both brand
    /// families resolve through the font registry — i.e. the bundled .ttf files
    /// are present AND registered under `UIAppFonts`. Probing (instead of a
    /// hardcoded `true`) keeps every accessor safe in stripped bundles such as
    /// unit-test hosts without the resources phase.
    private static let brandFontsAvailable: Bool =
        UIFont(name: "Manrope-Regular", size: 17) != nil
            && UIFont(name: "JetBrainsMono-Regular", size: 17) != nil

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

// MARK: - Tabular numeric helper

extension UIFont {
    /// Tabular-figures variant of the font — every digit glyph occupies the
    /// same advance width, so columns of numbers (clock ticks, balance
    /// rows, the firing-screen history ticker) stop reflowing every time a
    /// `1` swaps with a `4`. Mirrors SwiftUI's `Font.monospacedDigit()`
    /// using the UIKit feature-settings descriptor (Apple flags
    /// `kNumberSpacingType` + `kMonospacedNumbersSelector`).
    ///
    /// Lives in `AppFonts.swift` because the design-system fonts compose
    /// into UIFont via `AppFonts.font(...)`, and several call sites
    /// (`AlarmFiringViewController.timeLabel`, the new `historyTicker`
    /// in #139, future money-row labels) chain `.monospacedDigit()` on
    /// the resulting `UIFont`. `UIFont` itself does not ship the SwiftUI
    /// instance method, so we add it here.
    func monospacedDigit() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                ]
            ]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
