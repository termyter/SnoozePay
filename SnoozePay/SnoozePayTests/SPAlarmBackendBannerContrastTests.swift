import XCTest
import UIKit
@testable import SnoozePay

/// Contrast floor for the alarm-backend banner (#428 review).
///
/// The banner's entire job is to be unmissable, and its first implementation
/// used the STATIC `warn300` token, which measures **1.21:1** against the
/// composited fill in light mode — invisible on any device whose system theme
/// is light (the alarms list does not force `.dark`). Eyeballing missed it, so
/// the ratio is asserted here in WCAG 2.1 terms instead of described in a
/// comment.
final class SPAlarmBackendBannerContrastTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text. The caps title is bold 12pt — not
    /// "large text" by WCAG's definition (≥14pt bold), so the strict 4.5:1
    /// applies rather than the 3:1 relaxation.
    private let minimumContrast: CGFloat = 4.5

    // MARK: - Measurements

    func testEmphasisColour_readsOnTheBannerFill_light() {
        assertEmphasisReadable(in: .light)
    }

    func testEmphasisColour_readsOnTheBannerFill_dark() {
        assertEmphasisReadable(in: .dark)
    }

    func testIconGlyph_readsOnItsTile_light() {
        assertIconReadable(in: .light)
    }

    func testIconGlyph_readsOnItsTile_dark() {
        assertIconReadable(in: .dark)
    }

    /// The regression this suite exists for: the token the banner originally
    /// used must still be measurably unusable in light mode, so a future
    /// "simplify back to `warn300`" cannot pass unnoticed.
    func testStaticWarn300_isBelowTheFloorOnLightFill() {
        let fill = bannerFill(in: .light, alpha: SPAlarmBackendBanner.fillAlphas[0])
        let ratio = contrastRatio(AppColors.warn300, fill)
        XCTAssertLessThan(
            ratio, minimumContrast,
            "warn300 measured \(ratio):1 — if this ever passes, revisit the palette comment"
        )
    }

    // MARK: - Assertions

    private func assertEmphasisReadable(
        in style: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let emphasis = SPAlarmBackendBanner.emphasisColor.resolvedColor(with: traits)
        // Both stops of the two-stop tint — the title sits over the dense end,
        // the CTA over the sparse one.
        for alpha in SPAlarmBackendBanner.fillAlphas {
            let fill = bannerFill(in: style, alpha: alpha)
            let ratio = contrastRatio(emphasis, fill)
            XCTAssertGreaterThanOrEqual(
                ratio, minimumContrast,
                "title/CTA contrast \(ratio):1 at fill alpha \(alpha) in \(style.debugName)",
                file: file, line: line
            )
        }
    }

    private func assertIconReadable(
        in style: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let glyph = SPAlarmBackendBanner.iconColor.resolvedColor(with: traits)
        let tile = SPAlarmBackendBanner.iconTileColor.resolvedColor(with: traits)
        // The tile itself may be translucent, so composite it over the fill it
        // sits on before measuring.
        let tileOverFill = composite(
            tile,
            over: bannerFill(in: style, alpha: SPAlarmBackendBanner.fillAlphas[0])
        )
        let ratio = contrastRatio(glyph, tileOverFill)
        XCTAssertGreaterThanOrEqual(
            ratio, minimumContrast,
            "icon contrast \(ratio):1 in \(style.debugName)",
            file: file, line: line
        )
    }

    // MARK: - Colour maths

    /// The banner's fill as actually rendered: `warn400` at `alpha` over `bg0`.
    private func bannerFill(in style: UIUserInterfaceStyle, alpha: CGFloat) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: style)
        return composite(
            AppColors.warn400.withAlphaComponent(alpha),
            over: AppColors.bg0.resolvedColor(with: traits)
        )
    }

    private func composite(_ foreground: UIColor, over background: UIColor) -> UIColor {
        let fore = components(foreground)
        let back = components(background)
        let alpha = fore.alpha
        return UIColor(
            red: alpha * fore.red + (1 - alpha) * back.red,
            green: alpha * fore.green + (1 - alpha) * back.green,
            blue: alpha * fore.blue + (1 - alpha) * back.blue,
            alpha: 1
        )
    }

    /// sRGB channels of a colour, alpha included.
    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func components(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return Channels(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        let rgb = components(color)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    private func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs)
        let second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String {
        self == .dark ? "dark" : "light"
    }
}
