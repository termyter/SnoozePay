import UIKit
import XCTest
@testable import SnoozePay

/// Pins the warn chip's fill/ink pair in BOTH themes (#580).
///
/// The chip shipped the canon recipe byte-for-byte — `.sp-pill--warn` in
/// `tokens.css` is `rgba(245,158,11,.18)` over the card with `warn-300` ink —
/// and that recipe fails twice, in opposite ways:
///
///   - **dark**: 18% amber over the `bgRaised` card composites to `#3E3328`.
///     The ink is fine (8.71:1) but the CHIP is 1.38:1 against the card it
///     sits on, i.e. a brown smear. That brown is what reads as the bronze
///     the palette split in #520 was supposed to have retired.
///   - **light**: the same wash over the white card is `#FDEED3`, and the
///     light `warn300` (`#BE7B09`) on it measures 3.04:1 — under the 4.5:1
///     floor its 12pt caps require. (Bold 12pt is not "large text" by
///     WCAG 2.1 — that relaxation starts at 14pt bold.)
///
/// So both halves of `testCanonWash_failsInBothThemes` below are red on the
/// pre-#580 values and green after — the discriminating pair this suite
/// exists for. The rest pins what shipped instead: the solid `warnFill500`
/// under `fgOnWarn`, the same fill role #520 built for light.
final class SPPillWarnChipContrastTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text — the chip label is bold 12pt caps,
    /// which is below the ≥14pt-bold "large text" relaxation.
    private let textFloor: CGFloat = 4.5

    /// WCAG 2.1 non-text contrast floor (1.4.11) — the chip as an object.
    private let nonTextFloor: CGFloat = 3.0

    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02

    // MARK: - What shipped

    /// The ink half. One number for both themes, because both tokens are
    /// theme-flat — that sameness IS the fix, the two themes rendered this
    /// chip differently before.
    func testWarnChipInk_readsOnItsOwnFill_inBothThemes() {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let palette = SPPill.palette(for: .warn)
            let ratio = contrast(palette.ink.resolved(style), palette.fill.resolved(style))
            XCTAssertGreaterThanOrEqual(
                ratio, textFloor - tolerance,
                "warn chip ink is \(ratio.ratioText):1 on its fill in \(style.debugName)"
            )
            XCTAssertEqual(
                ratio, 8.79, accuracy: tolerance,
                "warn chip ink moved off its recorded measurement in \(style.debugName)"
            )
        }
    }

    /// The chip must also be a chip — an object told apart from the card it
    /// sits on. Dark is what #580 measured and what moves: 1.38:1 → 7.89:1.
    ///
    /// Light is pinned but NOT floored, and that is deliberate: amber on a
    /// white card is 2.15:1 and no step of the fill ramp beats 3:1 there
    /// (`warnFill300` is paler still). It was 1.15:1 as a wash, so the chip
    /// gained separation; what actually marks it out in light is the near-black
    /// ink on it. Flooring light here would be inventing a requirement the
    /// token cannot meet, which is how #520's heatmap regression happened.
    func testWarnChipFill_separatesFromTheCardItSitsOn() {
        let expected = [
            FillMeasurement(style: .dark, ratio: 7.89, floored: true),
            FillMeasurement(style: .light, ratio: 2.15, floored: false)
        ]
        for entry in expected {
            let card = AppColors.bgRaised.resolved(entry.style)
            let fill = SPPill.palette(for: .warn).fill.resolved(entry.style)
            let ratio = contrast(fill, card)
            XCTAssertEqual(
                ratio, entry.ratio, accuracy: tolerance,
                "warn chip vs card moved off its recorded measurement in \(entry.style.debugName)"
            )
            if entry.floored {
                XCTAssertGreaterThanOrEqual(
                    ratio, nonTextFloor,
                    "warn chip is \(ratio.ratioText):1 against its card in \(entry.style.debugName)"
                )
            }
        }
    }

    /// Chip fill against its card, per theme. `floored` marks the side that is
    /// asked to clear 1.4.11 — see the doc comment above for why light is not.
    private struct FillMeasurement {
        let style: UIUserInterfaceStyle
        let ratio: CGFloat
        let floored: Bool
    }

    /// Both halves of the pair are theme-flat tokens, so the chip renders
    /// identically in the two themes. Pinned because "make dark match light"
    /// was the whole ask, and a later `dynamicColor` here would undo it
    /// silently.
    func testWarnChip_rendersIdenticallyInBothThemes() {
        let palette = SPPill.palette(for: .warn)
        assertThemeFlat(palette.fill, token: 0xF59E0B, name: "fill")
        assertThemeFlat(palette.ink, token: 0x1A0F00, name: "ink")
    }

    private func assertThemeFlat(
        _ color: UIColor,
        token: UInt32,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            hex(color.resolved(.dark)), hex(color.resolved(.light)),
            "warn chip \(name) resolves differently per theme again",
            file: file, line: line
        )
        XCTAssertEqual(
            hex(color.resolved(.dark)), token,
            "warn chip \(name) drifted off its token",
            file: file, line: line
        )
        XCTAssertEqual(
            alpha(color.resolved(.dark)), 1, accuracy: 0.001,
            "warn chip \(name) is translucent — the wash is back",
            file: file, line: line
        )
    }

    /// The other tones were NOT part of the #580 decision and stay tints.
    /// Pinned so "the warn chip went solid, make the rest match" cannot happen
    /// by eye: `.pain` at full strength would put the alarm card's multiplier
    /// chip on the same visual level as its price chip.
    func testOtherTones_stayTranslucentTints() {
        for tone in [SPPill.Tone.money, .pain] {
            let fill = SPPill.palette(for: tone).fill.resolved(.dark)
            XCTAssertLessThan(
                alpha(fill), 1,
                "a non-warn pill tone became a solid fill"
            )
        }
    }

    // MARK: - The regression guard

    /// The canon wash, measured as it was actually rendered. Red on the
    /// pre-#580 values in both themes; this is the case that gives the suite
    /// its discriminating power.
    func testCanonWash_failsInBothThemes() {
        let darkCard = AppColors.bgRaised.resolved(.dark)
        let darkWash = composite(
            AppColors.warnFill500.withAlphaComponent(0.18).resolved(.dark),
            over: darkCard
        )
        XCTAssertLessThan(
            contrast(darkWash, darkCard), nonTextFloor,
            "the 18% wash now clears 1.4.11 on dark — re-derive the #580 decision"
        )

        let lightCard = AppColors.bgRaised.resolved(.light)
        let lightWash = composite(
            AppColors.warnFill500.withAlphaComponent(0.18).resolved(.light),
            over: lightCard
        )
        XCTAssertLessThan(
            contrast(AppColors.warn300.resolved(.light), lightWash), textFloor,
            "warn300 now reads on the light wash — re-derive the #580 decision"
        )
    }

    // MARK: - Colour maths

    private func composite(_ foreground: UIColor, over background: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        foreground.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var backRed: CGFloat = 0, backGreen: CGFloat = 0, backBlue: CGFloat = 0, backAlpha: CGFloat = 0
        background.getRed(&backRed, green: &backGreen, blue: &backBlue, alpha: &backAlpha)
        return UIColor(
            red: red * alpha + backRed * (1 - alpha),
            green: green * alpha + backGreen * (1 - alpha),
            blue: blue * alpha + backBlue * (1 - alpha),
            alpha: 1
        )
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs), second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func hex(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let toByte: (CGFloat) -> UInt32 = { UInt32(min(max(($0 * 255).rounded(), 0), 255)) }
        return (toByte(red) << 16) | (toByte(green) << 8) | toByte(blue)
    }

    private func alpha(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return alpha
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String { self == .dark ? "dark" : "light" }
}

private extension CGFloat {
    var ratioText: String { String(format: "%.2f", self) }
}
