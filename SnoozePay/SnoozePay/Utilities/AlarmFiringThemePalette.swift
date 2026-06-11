import UIKit

/// Per-theme visual recipe for the V3 themed firing screen (#225).
///
/// Source of truth — `FIRING_THEMES` in
/// `docs/design/v2-handoff/components/SPThemedFiring.jsx`. The theme changes
/// ONLY the atmosphere: full-bleed 160° background, darkening scrim, bottom
/// accent glow, accent tint (balance pill / eyebrow / bell tile / clock halo).
/// Layout, copy and CTAs stay identical across all six stock themes.
///
/// `.custom` (user photo) intentionally has no palette — the firing screen
/// keeps the photo + 45% dim treatment from #151, so `palette(for:)` returns
/// nil and callers fall back to the neutral white chrome.
struct AlarmFiringThemePalette: Equatable {

    // MARK: - Background

    /// 160°-diagonal linear gradient stops (top-left-ish → bottom-right-ish).
    /// Also reused by `AlarmThemeRendering` for the picker tile / alarm-cell
    /// strip so the preview the user picks matches the firing screen.
    let backgroundColors: [UIColor]
    /// Stop locations paired with `backgroundColors`.
    let backgroundLocations: [NSNumber]

    /// Radial vignette over the background — black alpha at the ellipse
    /// centre (50% x, 70% y) and at its far edge. Keeps the white copy
    /// legible on the brighter themes (Mountains' near-white horizon).
    let scrimInnerAlpha: CGFloat
    let scrimOuterAlpha: CGFloat

    // MARK: - Accents

    /// Theme accent — eyebrow caps, balance-pill text/icon tint.
    let accent: UIColor
    /// Low-alpha accent — bell-tile ring + bottom glow fill.
    let accentSoft: UIColor

    /// Balance pill fill / hairline border (`pillBg` / `pillBorder` in JSX).
    let pillBackground: UIColor
    let pillBorder: UIColor

    /// 135°-diagonal gradient for the 72×72 bell tile, stops at 0 / 0.6 / 1.
    let bellGradientColors: [UIColor]

    /// Soft halo behind the 96pt clock (`timeShadow` in JSX — colour at
    /// alpha 1 plus the layer `shadowOpacity` that carries the CSS alpha).
    let timeShadowColor: UIColor
    let timeShadowOpacity: Float

    // MARK: - Table

    // swiftlint:disable function_body_length
    /// Resolve the firing palette for a theme. Returns nil for `.custom` —
    /// photo backgrounds keep the un-themed treatment. Long by design: it's
    /// the literal six-row `FIRING_THEMES` table, one entry per stock theme.
    static func palette(for theme: AlarmTheme) -> AlarmFiringThemePalette? {
        switch theme {
        case .dawn:
            return AlarmFiringThemePalette(
                backgroundColors: [
                    UIColor(firingRGB: 0x2B1A0E),
                    UIColor(firingRGB: 0x6B3517),
                    UIColor(firingRGB: 0xC46A1A)
                ],
                backgroundLocations: [0.0, 0.5, 1.0],
                scrimInnerAlpha: 0.05,
                scrimOuterAlpha: 0.50,
                accent: UIColor(firingRGB: 0xFFD479),
                accentSoft: UIColor(firingRGB: 0xFFD479, alpha: 0.18),
                pillBackground: UIColor(firingRGB: 0xFFB84D, alpha: 0.16),
                pillBorder: UIColor(firingRGB: 0xFFD479, alpha: 0.32),
                bellGradientColors: [
                    UIColor(firingRGB: 0xFFD479),
                    UIColor(firingRGB: 0xF59E0B),
                    UIColor(firingRGB: 0xC97A06)
                ],
                timeShadowColor: UIColor(firingRGB: 0xFFB84D),
                timeShadowOpacity: 0.35
            )
        case .ocean:
            return AlarmFiringThemePalette(
                backgroundColors: [
                    UIColor(firingRGB: 0x08182A),
                    UIColor(firingRGB: 0x134E5E),
                    UIColor(firingRGB: 0x71B280)
                ],
                backgroundLocations: [0.0, 0.5, 1.0],
                scrimInnerAlpha: 0.05,
                scrimOuterAlpha: 0.55,
                accent: UIColor(firingRGB: 0x9EE6CC),
                accentSoft: UIColor(firingRGB: 0x9EE6CC, alpha: 0.18),
                pillBackground: UIColor(firingRGB: 0x71B280, alpha: 0.18),
                pillBorder: UIColor(firingRGB: 0x9EE6CC, alpha: 0.32),
                bellGradientColors: [
                    UIColor(firingRGB: 0x9EE6CC),
                    UIColor(firingRGB: 0x4A9D9C),
                    UIColor(firingRGB: 0x1F5F66)
                ],
                timeShadowColor: UIColor(firingRGB: 0x71B280),
                timeShadowOpacity: 0.32
            )
        case .mountains:
            return AlarmFiringThemePalette(
                backgroundColors: [
                    UIColor(firingRGB: 0x1A1F2E),
                    UIColor(firingRGB: 0x5A6B8A),
                    UIColor(firingRGB: 0xE1E5EA)
                ],
                backgroundLocations: [0.0, 0.5, 1.0],
                scrimInnerAlpha: 0.10,
                scrimOuterAlpha: 0.50,
                accent: UIColor(firingRGB: 0xE1E5EA),
                accentSoft: UIColor(firingRGB: 0xE1E5EA, alpha: 0.20),
                pillBackground: UIColor(firingRGB: 0xB7C0D0, alpha: 0.22),
                pillBorder: UIColor(firingRGB: 0xE1E5EA, alpha: 0.40),
                bellGradientColors: [
                    UIColor(firingRGB: 0xF4F6F9),
                    UIColor(firingRGB: 0xB7C0D0),
                    UIColor(firingRGB: 0x5A6B8A)
                ],
                timeShadowColor: UIColor(firingRGB: 0xE1E5EA),
                timeShadowOpacity: 0.30
            )
        case .forest:
            return AlarmFiringThemePalette(
                backgroundColors: [
                    UIColor(firingRGB: 0x0A1A0A),
                    UIColor(firingRGB: 0x1E3823),
                    UIColor(firingRGB: 0x4A6B3A)
                ],
                backgroundLocations: [0.0, 0.5, 1.0],
                scrimInnerAlpha: 0.05,
                scrimOuterAlpha: 0.55,
                accent: UIColor(firingRGB: 0xA8D89A),
                accentSoft: UIColor(firingRGB: 0xA8D89A, alpha: 0.16),
                pillBackground: UIColor(firingRGB: 0x4A6B3A, alpha: 0.22),
                pillBorder: UIColor(firingRGB: 0xA8D89A, alpha: 0.34),
                bellGradientColors: [
                    UIColor(firingRGB: 0xC5E8B0),
                    UIColor(firingRGB: 0x6A9853),
                    UIColor(firingRGB: 0x2F4D24)
                ],
                timeShadowColor: UIColor(firingRGB: 0x4A6B3A),
                timeShadowOpacity: 0.40
            )
        case .neon:
            return AlarmFiringThemePalette(
                backgroundColors: [
                    UIColor(firingRGB: 0x0A0A1F),
                    UIColor(firingRGB: 0x3D1E63),
                    UIColor(firingRGB: 0xFF3D8A)
                ],
                backgroundLocations: [0.0, 0.5, 1.0],
                scrimInnerAlpha: 0.10,
                scrimOuterAlpha: 0.55,
                accent: UIColor(firingRGB: 0xFF7EC8),
                accentSoft: UIColor(firingRGB: 0xFF7EC8, alpha: 0.22),
                pillBackground: UIColor(firingRGB: 0xFF3D8A, alpha: 0.20),
                pillBorder: UIColor(firingRGB: 0xFF7EC8, alpha: 0.40),
                bellGradientColors: [
                    UIColor(firingRGB: 0xFF7EC8),
                    UIColor(firingRGB: 0xC53578),
                    UIColor(firingRGB: 0x5C1A4A)
                ],
                timeShadowColor: UIColor(firingRGB: 0xFF3D8A),
                timeShadowOpacity: 0.40
            )
        case .abstract:
            return AlarmFiringThemePalette(
                backgroundColors: [
                    UIColor(firingRGB: 0x1E1E1E),
                    UIColor(firingRGB: 0x2A2A2A)
                ],
                backgroundLocations: [0.0, 1.0],
                scrimInnerAlpha: 0.0,
                scrimOuterAlpha: 0.30,
                accent: .white,
                accentSoft: UIColor(white: 1.0, alpha: 0.12),
                pillBackground: UIColor(white: 1.0, alpha: 0.10),
                pillBorder: UIColor(white: 1.0, alpha: 0.22),
                bellGradientColors: [
                    UIColor(firingRGB: 0xFFFFFF),
                    UIColor(firingRGB: 0xBFBFBF),
                    UIColor(firingRGB: 0x6F6F6F)
                ],
                timeShadowColor: .white,
                timeShadowOpacity: 0.10
            )
        case .custom:
            return nil
        }
    }
    // swiftlint:enable function_body_length

    /// Bell-tile gradient stop locations — the JSX recipe is
    /// `linear-gradient(135deg, A 0%, B 60%, C 100%)` for every theme.
    static let bellGradientLocations: [NSNumber] = [0.0, 0.6, 1.0]
}

// MARK: - Hex helper (file-scoped)

private extension UIColor {
    /// `0xRRGGBB` literal initializer used by the palette table above.
    /// File-scoped copy — `private` means file-scope in Swift, so the
    /// identical helpers in sibling files don't collide.
    convenience init(firingRGB rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
