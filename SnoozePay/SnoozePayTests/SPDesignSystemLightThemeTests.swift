import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme guarantees for the shared design-system primitives (#498).
///
/// Two classes of regression are pinned here, because both were introduced by
/// eyeballing a dark-only screen:
///
/// 1. **Ink on a fill.** `fgOnMoney` / `fgOnWarn` mean "ink on a *solid* fill
///    of that colour". Applied to a gradient — or to a faint tint of one —
///    they invert into unreadable. The «Популярно» badge used to be a money
///    *gradient* with white ink, which cannot work in dark: whichever ink you
///    pick, one end of the `money400 → money700` ramp fails.
/// 2. **Separation on a near-white page.** In light mode `bg1` is `#FFFFFF`
///    and the page under a tile is `bg0` `#F4F6FB`. A drop shadow alone does
///    not separate them, so idle tiles must carry a border *and* a shadow.
final class SPDesignSystemLightThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text.
    private let normalTextFloor: CGFloat = 4.5
    /// WCAG 2.1 floor for large text (≥14pt bold). The segmented labels are
    /// `buttonSm` — bold 14pt — so they qualify for the relaxed bar.
    private let largeTextFloor: CGFloat = 3.0
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.05

    // MARK: - SPAmountPreset · «Популярно» badge

    func testPopularBadgeInk_readsOnItsFill_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(
                SPAmountPreset.popularBadgeInk.resolved(style),
                SPAmountPreset.popularBadgeFill.resolved(style)
            )
            XCTAssertGreaterThanOrEqual(
                ratio, normalTextFloor - tolerance,
                "«Популярно» ink is \(ratio.ratioText):1 on its fill in \(style.name)"
            )
        }
    }

    /// The reason the badge is a solid fill and not `--sp-grad-money`: in the
    /// dark theme neither candidate ink survives the whole ramp. If someone
    /// restores the gradient "because the CSS says so", these two numbers are
    /// what they have to answer for.
    func testMoneyGradientEnds_cannotCarryASingleInk_inDark() {
        let whiteOnBrightEnd = contrast(.white, AppColors.money400.resolved(.dark))
        XCTAssertLessThan(
            whiteOnBrightEnd, normalTextFloor,
            "white on the money400 end measures \(whiteOnBrightEnd.ratioText):1"
        )

        let darkInkOnDeepEnd = contrast(
            AppColors.fgOnMoney.resolved(.dark),
            AppColors.money700.resolved(.dark)
        )
        XCTAssertLessThan(
            darkInkOnDeepEnd, normalTextFloor,
            "fgOnMoney on the money700 end measures \(darkInkOnDeepEnd.ratioText):1"
        )
    }

    // MARK: - SPAmountPreset · light-mode separation

    func testIdleTile_inLight_carriesBothABorderAndAShadow() throws {
        let tile = try makeLaidOutTile(style: .light)

        XCTAssertGreaterThan(
            tile.layer.shadowOpacity, 0,
            "a white tile on a #F4F6FB page needs --sp-shadow-1 to lift off it"
        )
        XCTAssertTrue(
            tile.layer.sublayers?.contains { $0.borderWidth > 0 } ?? false,
            "a shadow alone does not separate white from near-white — keep the hairline"
        )
    }

    /// Dark is the canon and must not acquire the light treatment.
    func testIdleTile_inDark_staysFlat() throws {
        let tile = try makeLaidOutTile(style: .dark)

        XCTAssertEqual(
            tile.layer.shadowOpacity, 0,
            "dark keeps the flat outlined card — bg1 on bg0 is already a visible step"
        )
        XCTAssertNil(
            tile.layer.sublayers?.first { $0.name == AppShadow.ambientShadow1LayerName },
            "the light-only ambient shadow stop leaked into dark"
        )
    }

    // MARK: - SPSegmented

    func testSegmentedLabels_readOnTheirSurfaces_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let selected = contrast(
                SPSegmented.selectedTitleColor.resolved(style),
                SPSegmented.indicatorColor.resolved(style)
            )
            XCTAssertGreaterThanOrEqual(
                selected, normalTextFloor - tolerance,
                "active segment label is \(selected.ratioText):1 on the indicator in \(style.name)"
            )

            // The track is a translucent wash, so composite it over the page
            // it sits on before measuring the idle label against it.
            let track = composite(
                SPSegmented.trackColor.resolved(style),
                over: AppColors.bg0.resolved(style)
            )
            let idle = contrast(
                composite(SPSegmented.idleTitleColor.resolved(style), over: track),
                track
            )
            XCTAssertGreaterThanOrEqual(
                idle, largeTextFloor - tolerance,
                "idle segment label is \(idle.ratioText):1 on the track in \(style.name)"
            )
        }
    }

    // MARK: - Fixtures

    /// A laid-out preset tile forced into `style`.
    ///
    /// Skips rather than fails if the runtime declines to propagate the
    /// override onto a view that is not in a window — that would be a fact
    /// about the harness, not about the component.
    private func makeLaidOutTile(style: UIUserInterfaceStyle) throws -> SPAmountPreset {
        let tile = SPAmountPreset(value: 149, label: "Бонус 5%", popular: true)
        tile.overrideUserInterfaceStyle = style
        tile.frame = CGRect(x: 0, y: 0, width: 110, height: 88)
        tile.setNeedsLayout()
        tile.layoutIfNeeded()
        try XCTSkipUnless(
            tile.traitCollection.userInterfaceStyle == style,
            "detached view did not adopt overrideUserInterfaceStyle"
        )
        return tile
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

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return Channels(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        let rgb = channels(color)
        func value(_ raw: CGFloat) -> CGFloat {
            raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * value(rgb.red) + 0.7152 * value(rgb.green) + 0.0722 * value(rgb.blue)
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs)
        let second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var name: String { self == .light ? "light" : "dark" }
}

private extension CGFloat {
    /// Two decimals — failure messages carry the measurement, not a shrug.
    var ratioText: String { String(format: "%.2f", self) }
}
