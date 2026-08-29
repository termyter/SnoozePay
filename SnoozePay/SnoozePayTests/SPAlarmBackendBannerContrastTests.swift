import XCTest
import UIKit
@testable import SnoozePay

/// Contrast floor for the alarm-backend banner (#428 review).
///
/// The banner's entire job is to be unmissable, and its first implementation
/// used `warn300` in both themes, which measured **1.21:1** against the
/// composited fill in light mode — invisible on any device whose system theme
/// is light (the alarms list does not force `.dark`). Eyeballing missed it, so
/// the ratio is asserted here in WCAG 2.1 terms instead of described in a
/// comment.
final class SPAlarmBackendBannerContrastTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text. The caps title is bold 12pt — not
    /// "large text" by WCAG's definition (≥14pt bold), so the strict 4.5:1
    /// applies rather than the 3:1 relaxation.
    private let minimumContrast: CGFloat = 4.5

    /// WCAG 2.1 non-text contrast floor (1.4.11) — for the container edge.
    private let nonTextFloor: CGFloat = 3.0

    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02

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
    /// "simplify back to `warn300`" cannot pass unnoticed. It stayed unusable
    /// after #489 made the scale theme-aware — the light value reaches only
    /// 2.68:1 on the dense end of the fill.
    func testWarn300_isBelowTheFloorOnLightFill() {
        let fill = bannerFill(in: .light, alpha: SPAlarmBackendBanner.fillAlphas[0])
        let ratio = contrastRatio(AppColors.warn300, fill)
        XCTAssertLessThan(
            ratio, minimumContrast,
            "warn300 measured \(ratio):1 — if this ever passes, revisit the palette comment"
        )
    }

    // MARK: - The edge (#538)

    /// The banner had no edge in either theme: at `warn400@22%` / `warn500@45%`
    /// the border measured 1.55:1 dark and 2.06:1 light against the page, and
    /// a 1pt line at that ratio is a rumour, not an edge. Since the fill stays
    /// a decorative wash (see below), the border is the ONLY thing separating
    /// the banner from `bg0`, so it has to clear 1.4.11 on its own.
    ///
    /// Same decision and the same alpha pair as `AlarmsStreakBannerView` (#531)
    /// — the two banners are one family. If these move, re-derive the numbers
    /// quoted in the view's header rather than deleting the pin.
    func testBorder_clearsTheNonTextFloorAgainstThePage() {
        let expected: [(style: UIUserInterfaceStyle, ratio: CGFloat)] = [
            (.dark, 3.50),
            (.light, 3.72)
        ]
        for entry in expected {
            let traits = UITraitCollection(userInterfaceStyle: entry.style)
            let page = AppColors.bg0.resolvedColor(with: traits)
            let border = SPAlarmBackendBanner.borderColor.resolvedColor(with: traits)
            let measured = contrastRatio(composite(border, over: page), page)

            XCTAssertGreaterThanOrEqual(
                measured, nonTextFloor,
                "\(entry.style.debugName) border measured \(measured):1 against the page"
            )
            XCTAssertEqual(
                measured, entry.ratio, accuracy: tolerance,
                "\(entry.style.debugName) border moved off its recorded measurement"
            )
        }
    }

    /// Border-over-page is the conservative reading: the 1pt stroke actually
    /// composites over the banner's own wash. Pinned so the header's second
    /// pair of numbers stays honest — and so both sides of the line are known
    /// to clear 3:1, not just the outer one.
    ///
    /// Measured at the DENSE stop, which is the worse of the two for the
    /// inner side; over the sparse stop the same stroke reads 3.53:1 dark and
    /// 3.58:1 light against the wash, so the whole ramp clears the floor.
    func testBorder_clearsTheFloorOnBothSidesOfTheLine() {
        let expected: [StrokeMeasurement] = [
            StrokeMeasurement(style: .dark, vsPage: 4.25, vsWash: 3.37),
            StrokeMeasurement(style: .light, vsPage: 3.98, vsWash: 3.31)
        ]
        for entry in expected {
            let traits = UITraitCollection(userInterfaceStyle: entry.style)
            let page = AppColors.bg0.resolvedColor(with: traits)
            let wash = bannerFill(in: entry.style, alpha: SPAlarmBackendBanner.fillAlphas[0])
            let border = SPAlarmBackendBanner.borderColor.resolvedColor(with: traits)
            let stroke = composite(border, over: wash)

            XCTAssertEqual(
                contrastRatio(stroke, page), entry.vsPage, accuracy: tolerance,
                "\(entry.style.debugName) stroke-over-wash moved against the page"
            )
            XCTAssertEqual(
                contrastRatio(stroke, wash), entry.vsWash, accuracy: tolerance,
                "\(entry.style.debugName) stroke-over-wash moved against the wash"
            )
        }
    }

    private struct StrokeMeasurement {
        let style: UIUserInterfaceStyle
        let vsPage: CGFloat
        let vsWash: CGFloat
    }

    /// The other half of the decision, measured rather than asserted in prose:
    /// the tint stays a decorative wash and is NOT asked to be the edge.
    ///
    /// Raising it to reach 3:1 against the page would cost the ink that sits
    /// on it — `warn400@45%` on dark takes the title from 11.22:1 to 4.68:1,
    /// and `warn400@74%` on light takes `warn600` down to 2.83:1, below the
    /// 4.5:1 floor the rest of this suite defends. So these numbers staying
    /// low is intended, and the border is what changed in #538.
    func testSurface_staysADecorativeWashAgainstThePage() {
        let expected: [WashMeasurement] = [
            WashMeasurement(style: .dark, dense: 1.26, sparse: 1.06),
            WashMeasurement(style: .light, dense: 1.20, sparse: 1.07)
        ]
        for entry in expected {
            let traits = UITraitCollection(userInterfaceStyle: entry.style)
            let page = AppColors.bg0.resolvedColor(with: traits)
            XCTAssertEqual(SPAlarmBackendBanner.fillAlphas.count, 2, "the wash is a two-stop recipe")

            let dense = bannerFill(in: entry.style, alpha: SPAlarmBackendBanner.fillAlphas[0])
            let sparse = bannerFill(in: entry.style, alpha: SPAlarmBackendBanner.fillAlphas[1])

            XCTAssertEqual(
                contrastRatio(dense, page), entry.dense, accuracy: tolerance,
                "\(entry.style.debugName) dense fill stop moved off its recorded measurement"
            )
            XCTAssertEqual(
                contrastRatio(sparse, page), entry.sparse, accuracy: tolerance,
                "\(entry.style.debugName) sparse fill stop moved off its recorded measurement"
            )
        }
    }

    private struct WashMeasurement {
        let style: UIUserInterfaceStyle
        let dense: CGFloat
        let sparse: CGFloat
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
