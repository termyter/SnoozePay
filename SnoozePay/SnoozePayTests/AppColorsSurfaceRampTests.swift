import UIKit
import XCTest
@testable import SnoozePay

/// Pins the surface (`bg0`...`bg4`) and foreground (`fg1`...`fg4`) ramps to the
/// canon in `docs/design/snoozepay-2026-04-27/project/tokens.css`, and keeps
/// the system palette out of both (#527).
///
/// The accent scales already have `AppColorsContrastTests`; the ramps had
/// nothing, which is how `AppColors.surface` — a plain
/// `UIColor.secondarySystemBackground` — survived the migration to tokens. Its
/// values (`#F2F2F7` light, `#1C1C1E` dark) appear nowhere in `tokens.css`, so
/// every screen that reached for it drifted off canon *and looked plausible*:
/// a warm grey next to `bg2`'s `#ECEEF6` reads as a design decision rather than
/// as a leftover. It cost a fix in #496, another in #492, and a wrong first
/// hypothesis in #515 before it was removed.
///
/// Hence two assertions, not one. Pinning the hexes catches a value drifting;
/// the system-palette check catches the *mechanism* coming back — a token
/// re-aliased onto `UIColor.<something>System<something>`, which would sail
/// past a colour-by-colour eyeball review because system colours are, by
/// construction, reasonable-looking greys.
@MainActor
final class AppColorsSurfaceRampTests: XCTestCase {

    private struct SurfaceStep {
        let name: String
        let color: UIColor
        let dark: UInt32
        let light: UInt32
    }

    private struct ForegroundStep {
        let name: String
        let color: UIColor
        let darkAlpha: CGFloat
        let lightAlpha: CGFloat
    }

    /// `--sp-bg-0`...`--sp-bg-4`, dark block then light block of `tokens.css`.
    private static let surfaceRamp: [SurfaceStep] = [
        SurfaceStep(name: "bg0", color: AppColors.bg0, dark: 0x060912, light: 0xF4F6FB),
        SurfaceStep(name: "bg1", color: AppColors.bg1, dark: 0x0E1320, light: 0xFFFFFF),
        SurfaceStep(name: "bg2", color: AppColors.bg2, dark: 0x161C2E, light: 0xECEEF6),
        SurfaceStep(name: "bg3", color: AppColors.bg3, dark: 0x1F2740, light: 0xDFE3F0),
        SurfaceStep(name: "bg4", color: AppColors.bg4, dark: 0x2A3354, light: 0xC9D0E3)
    ]

    /// The foreground ramp is a tint of one ink per theme at four alphas, so it
    /// is pinned as (ink, alpha) rather than as a flat hex.
    private static let foregroundRamp: [ForegroundStep] = [
        ForegroundStep(name: "fg1", color: AppColors.fg1, darkAlpha: 1.00, lightAlpha: 1.00),
        ForegroundStep(name: "fg2", color: AppColors.fg2, darkAlpha: 0.86, lightAlpha: 0.82),
        ForegroundStep(name: "fg3", color: AppColors.fg3, darkAlpha: 0.58, lightAlpha: 0.56),
        ForegroundStep(name: "fg4", color: AppColors.fg4, darkAlpha: 0.32, lightAlpha: 0.32)
    ]

    /// The colours a token must never be aliased onto. Deliberately includes
    /// the greys and fills as well as the backgrounds: the defect is "reached
    /// for the system palette", not "reached for one specific member of it".
    private static let systemPalette: [(name: String, color: UIColor)] = [
        ("systemBackground", .systemBackground),
        ("secondarySystemBackground", .secondarySystemBackground),
        ("tertiarySystemBackground", .tertiarySystemBackground),
        ("systemGroupedBackground", .systemGroupedBackground),
        ("secondarySystemGroupedBackground", .secondarySystemGroupedBackground),
        ("tertiarySystemGroupedBackground", .tertiarySystemGroupedBackground),
        ("systemFill", .systemFill),
        ("secondarySystemFill", .secondarySystemFill),
        ("systemGray5", .systemGray5),
        ("systemGray6", .systemGray6),
        ("label", .label),
        ("secondaryLabel", .secondaryLabel),
        ("tertiaryLabel", .tertiaryLabel),
        ("quaternaryLabel", .quaternaryLabel),
        ("separator", .separator)
    ]

    // MARK: - Canon

    func testSurfaceRamp_matchesTheCanonTokens_inBothThemes() {
        for step in Self.surfaceRamp {
            XCTAssertEqual(
                hex(step.color.resolved(.dark)), hex(UIColor(rgb: step.dark)),
                "\(step.name) drifted off --sp-bg in the dark block of tokens.css"
            )
            XCTAssertEqual(
                hex(step.color.resolved(.light)), hex(UIColor(rgb: step.light)),
                "\(step.name) drifted off --sp-bg in the light block of tokens.css"
            )
        }
    }

    /// `#0E1320` on dark vs `#FFFFFF` on light is the whole point of the ramp.
    /// A step that resolves identically in both themes is a static literal that
    /// was never wired through `UIColor(dynamicProvider:)`.
    func testSurfaceRamp_resolvesToADifferentValuePerTheme() {
        for step in Self.surfaceRamp {
            XCTAssertNotEqual(
                hex(step.color.resolved(.light)), hex(step.color.resolved(.dark)),
                "\(step.name) is the same colour in both themes — it is not theme-aware"
            )
        }
    }

    func testForegroundRamp_tintsTheBrandInkAtTheCanonAlphas() {
        for step in Self.foregroundRamp {
            XCTAssertEqual(
                alpha(step.color.resolved(.dark)), step.darkAlpha, accuracy: 0.005,
                "\(step.name) dark alpha"
            )
            XCTAssertEqual(
                alpha(step.color.resolved(.light)), step.lightAlpha, accuracy: 0.005,
                "\(step.name) light alpha"
            )
            // Light ink is the brand near-black `#0A0F1F`, dark ink is
            // near-white — so the two themes must land on opposite sides of
            // mid-grey once composited at full strength.
            XCTAssertLessThan(
                luminance(step.color.resolved(.light).withAlphaComponent(1)), 0.1,
                "\(step.name) light ink is not the brand near-black"
            )
            XCTAssertGreaterThan(
                luminance(step.color.resolved(.dark).withAlphaComponent(1)), 0.7,
                "\(step.name) dark ink is not the near-white foreground base"
            )
        }
    }

    // MARK: - No system colours

    /// A dynamic system colour resolves to the *same pair* of values in light
    /// and dark whichever token it hides behind, so matching on the pair —
    /// rather than on a single theme — is what distinguishes "aliased onto the
    /// system palette" from "happens to share one value with it". `bg1` is
    /// `#FFFFFF` in light exactly like `secondarySystemGroupedBackground`; only
    /// its dark value (`#0E1320` vs `#1C1C1E`) tells them apart.
    func testRamps_areNotAliasedOntoTheSystemPalette() {
        let tokens: [(String, UIColor)] = Self.surfaceRamp.map { ($0.name, $0.color) }
            + Self.foregroundRamp.map { ($0.name, $0.color) }
        for (tokenName, token) in tokens {
            for (systemName, system) in Self.systemPalette {
                let sameLight = hex(token.resolved(.light)) == hex(system.resolved(.light))
                let sameDark = hex(token.resolved(.dark)) == hex(system.resolved(.dark))
                XCTAssertFalse(
                    sameLight && sameDark,
                    "\(tokenName) resolves exactly like UIColor.\(systemName) in both themes — "
                    + "the palette is back on the system colours the tokens replaced"
                )
            }
        }
    }

    /// The literal that started #527. Kept as a named case so the reasoning
    /// survives even if the loop above is ever narrowed: the token that used to
    /// fill cards was `secondarySystemBackground`, and neither of its values is
    /// a surface in our ramp.
    func testSecondarySystemBackground_isNoStepOfOurRamp() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let system = hex(UIColor.secondarySystemBackground.resolved(style))
            for step in Self.surfaceRamp {
                XCTAssertNotEqual(
                    hex(step.color.resolved(style)), system,
                    "\(step.name) equals secondarySystemBackground in \(style.debugName)"
                )
            }
        }
    }

    // MARK: - Time picker row

    /// The one call site the removed alias had. `TimePickerCell` filled
    /// `AppColors.surface`; every sibling row of the same form — name, repeat,
    /// sound, volume, vibration, penalty — already set `bg1`. Same defect and
    /// same fix as `ProgressiveCardSurface` in #492, which
    /// `CreateAlarmLightThemeTests` pins the same way.
    ///
    /// What renders is `CardRowBackgroundView`'s `bg1`, because `styleAsCardRow`
    /// clears the cell's own fill in `willDisplay`. That is *why* the old value
    /// was never visible on screen and why it survived so long; the assertion is
    /// on the cell's declared fill, so the next reader isn't told two different
    /// things by two adjacent rows.
    func testTimePickerCell_declaresTheBrandCardToken_notTheSystemGrey() {
        let cell = TimePickerCell(style: .default, reuseIdentifier: nil)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let fill = cell.backgroundColor?.resolved(style) ?? .clear
            XCTAssertEqual(
                hex(fill), hex(AppColors.bg1.resolved(style)),
                "time picker row fill in \(style.debugName) must match its sibling rows"
            )
            XCTAssertNotEqual(
                hex(fill), hex(UIColor.secondarySystemBackground.resolved(style)),
                "time picker row is back on the system grey in \(style.debugName)"
            )
        }
    }

    /// The «Подъём» caps header documents itself as `fg3` and was painted
    /// `tertiaryLabel` — 30% ink, where every other caps header on the form is
    /// 56%. On the white card that is 1.71:1; `fg3` is 4.41:1.
    func testTimePickerCapsHeader_usesTheBrandMetaInk() {
        let cell = TimePickerCell(style: .default, reuseIdentifier: nil)
        // Matched by size + non-empty text rather than by font identity: the
        // readout carries no text until `configure(time:)`, and the wheels
        // contribute no laid-out labels to a cell that was never in a window.
        let header = allLabels(in: cell.contentView).first {
            !($0.text ?? "").isEmpty && $0.font.pointSize == AppTypography.caps.pointSize
        }
        guard let header else {
            return XCTFail("TimePickerCell must own a caps header label")
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                hex(header.textColor.resolved(style)), hex(AppColors.fg3.resolved(style)),
                "caps header ink in \(style.debugName)"
            )
        }
    }

    /// The measurement behind the change above, so the number is checked rather
    /// than quoted: the old ink failed AA for the caps size in both themes.
    func testTimePickerCapsHeader_clearsAAOnTheCard_whichTertiaryLabelDidNot() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = AppColors.bg1.resolved(style)
            let now = contrastRatio(composite(AppColors.fg3.resolved(style), over: card), card)
            let before = contrastRatio(
                composite(UIColor.tertiaryLabel.resolved(style), over: card),
                card
            )
            XCTAssertGreaterThan(now, before, "fg3 must be the stronger ink in \(style.debugName)")
            XCTAssertLessThan(before, 3.0, "tertiaryLabel was not the defect this claims it was")
            XCTAssertGreaterThan(now, 4.0, "fg3 caps header is \(now):1 in \(style.debugName)")
        }
    }

    private func allLabels(in view: UIView) -> [UILabel] {
        view.subviews.reduce(into: [UILabel]()) { result, subview in
            if let label = subview as? UILabel { result.append(label) }
            result.append(contentsOf: allLabels(in: subview))
        }
    }

    // MARK: - Colour maths

    private func composite(_ foreground: UIColor, over background: UIColor) -> UIColor {
        let fore = channels(foreground)
        let back = channels(background)
        let alpha = fore.alpha
        return UIColor(
            red: alpha * fore.red + (1 - alpha) * back.red,
            green: alpha * fore.green + (1 - alpha) * back.green,
            blue: alpha * fore.blue + (1 - alpha) * back.blue,
            alpha: 1
        )
    }

    private func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs)
        let second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    /// Unlike the brand tokens, several members of `systemPalette` are declared
    /// in a grayscale space, where `getRed` is not guaranteed — hence the
    /// `getWhite` fallback rather than a bare `XCTFail`.
    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return Channels(red: red, green: green, blue: blue, alpha: alpha)
        }
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return Channels(red: white, green: white, blue: white, alpha: alpha)
        }
        XCTFail("colour is representable in neither sRGB nor grayscale: \(color)")
        return Channels(red: 0, green: 0, blue: 0, alpha: 1)
    }

    private func alpha(_ color: UIColor) -> CGFloat {
        channels(color).alpha
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        let rgb = channels(color)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    private func hex(_ color: UIColor) -> String {
        let rgb = channels(color)
        return String(
            format: "%02X%02X%02X@%.2f",
            Int((rgb.red * 255).rounded()),
            Int((rgb.green * 255).rounded()),
            Int((rgb.blue * 255).rounded()),
            rgb.alpha
        )
    }
}

private extension UIColor {
    /// Local twin of `AppColors`' own hex initialiser, which is `private` to
    /// that file — the expected values here are read straight off `tokens.css`
    /// and must not go through the code under test.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1
        )
    }

    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String {
        self == .dark ? "dark" : "light"
    }
}
