import UIKit
import XCTest
@testable import SnoozePay

/// Pins the colour decisions the referral screen makes on top of the brand
/// scales (#497), in the same style as `AppColorsContrastTests`.
///
/// Two of them are easy to "fix" by eye and silently break:
///
///  1. The hero fill stays DARK in both themes (it is a filled promo panel,
///     like `--sp-grad-night`, not a surface). That is the only reason its
///     copy can be white in both — swap a stop for a light surface and the
///     white copy disappears.
///  2. The friend avatar is a WASH, not a solid fill, so its ink is
///     `fgOnWarnWash`, not `fgOnWarn`. That held when `fgOnWarn` was white
///     (~1.2:1 on the wash — the defect fixed in `SPAlarmBackendBanner`) and
///     it still holds now that #520 made it `#1A0F00`: a near-black on a pale
///     wash is readable but is not a warn treatment, so the light half of the
///     rule is pinned by identity rather than by contrast.
final class ReferralScreenContrastTests: XCTestCase {

    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.05

    // MARK: - Hero fill

    /// The copy sits over the top-left of the 135° ramp, i.e. the `700` and
    /// `500` stops; `300` is the decorative bottom-right corner and is only
    /// held to the large-text bar (the dark theme's `#4F8A3A` is 4.17:1 with
    /// white and is canon — tightening it means changing the canon).
    func testHeroInk_isReadableOnEveryStopInBothThemes() {
        let stops: [(name: String, color: UIColor, target: CGFloat)] = [
            ("heroDeep700", AppColors.heroDeep700, 4.5),
            ("heroDeep500", AppColors.heroDeep500, 4.5),
            ("heroDeep300", AppColors.heroDeep300, 3.0)
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, color, target) in stops {
                let ratio = contrast(AppColors.fgOnHeroDeep.resolved(style), color.resolved(style))
                XCTAssertGreaterThanOrEqual(
                    ratio, target - tolerance,
                    "fgOnHeroDeep is \(String(format: "%.2f", ratio)):1 on \(name) in "
                    + "\(style == .light ? "light" : "dark"), its role needs \(target):1"
                )
            }
        }
    }

    /// The whole point of the token: the panel must not follow the surface
    /// scale into the light theme. If a stop ever resolves lighter than the
    /// light card it sits on, the white copy is gone.
    func testHeroFill_staysDarkerThanTheLightCard() {
        let card = luminance(AppColors.bg2.resolved(.light))
        for (name, color) in [
            ("heroDeep700", AppColors.heroDeep700),
            ("heroDeep500", AppColors.heroDeep500),
            ("heroDeep300", AppColors.heroDeep300)
        ] {
            XCTAssertLessThan(
                luminance(color.resolved(.light)), card,
                "\(name) is lighter than bg2 in the light theme — the hero has become a light surface"
            )
        }
    }

    /// The dark theme is the canon and must not drift while the light one is
    /// tuned: these are the literals inlined in `SPMore4.jsx`.
    func testHeroFill_keepsTheCanonDarkStops() {
        let canon: [(String, UIColor, UInt32)] = [
            ("heroDeep700", AppColors.heroDeep700, 0x1A2810),
            ("heroDeep500", AppColors.heroDeep500, 0x2C4A1F),
            ("heroDeep300", AppColors.heroDeep300, 0x4F8A3A)
        ]
        for (name, color, expected) in canon {
            XCTAssertEqual(
                hex(color.resolved(.dark)), expected,
                "\(name) drifted from the prototype: expected " + String(format: "#%06X", expected)
                + ", got " + String(format: "#%06X", hex(color.resolved(.dark)))
            )
        }
    }

    // MARK: - Warn wash

    /// 17pt bold initial on a 36pt avatar — large text, so 3:1. The dark theme
    /// keeps the canon recipe (60% bronze + `warn300`) bit for bit.
    func testWarnWashInk_clearsTheLargeTextBarOverTheCard() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let fill = composite(AppColors.warnWash.resolved(style), over: AppColors.bg1.resolved(style))
            let ratio = contrast(AppColors.fgOnWarnWash.resolved(style), fill)
            XCTAssertGreaterThanOrEqual(
                ratio, 3.0 - tolerance,
                "fgOnWarnWash is \(String(format: "%.2f", ratio)):1 on the wash in "
                + "\(style == .light ? "light" : "dark")"
            )
        }
    }

    /// The misuse this pairing exists to prevent: `fgOnWarn` is ink for a SOLID
    /// warn fill and does not belong on a wash.
    ///
    /// Measured only in DARK, and the reason is worth writing down. This test
    /// used to run both themes and assert `fgOnWarnWash` beats `fgOnWarn`,
    /// which held while `fgOnWarn` was white: white on the pale light wash is
    /// 1.35:1. Since #520 `fgOnWarn` is `#1A0F00` in both themes, and near-black
    /// on a pale wash measures 13.97:1 — it *beats* the wash ink (6.86:1)
    /// without being correct, because on a light wash it is no longer warn ink
    /// at all, just `fg1` under another name. Contrast stopped being able to
    /// tell the two apart in light, so the light half is pinned by identity
    /// below instead of by a ratio. The dark arithmetic is unchanged.
    func testFgOnWarn_wouldBeWorseThanFgOnWarnWashOnTheDarkWash() {
        let fill = composite(AppColors.warnWash.resolved(.dark), over: AppColors.bg1.resolved(.dark))
        let wash = contrast(AppColors.fgOnWarnWash.resolved(.dark), fill)
        let solid = contrast(AppColors.fgOnWarn.resolved(.dark), fill)
        XCTAssertGreaterThan(
            wash, solid,
            "fgOnWarn beats fgOnWarnWash on the dark wash — the wash recipe no longer matches its ink"
        )
    }

    /// The light half of the pairing above: the wash ink must stay a warn TONE
    /// rather than collapse onto the on-fill ink. This is what stops a future
    /// "both are dark now, use one token" cleanup from putting `#1A0F00` on a
    /// wash and calling it a warn treatment.
    func testFgOnWarnWash_staysAWarnToneAndNotTheOnFillInk() {
        XCTAssertEqual(hex(AppColors.fgOnWarnWash.resolved(.light)), hex(AppColors.warn600.resolved(.light)))
        XCTAssertNotEqual(hex(AppColors.fgOnWarnWash.resolved(.light)), hex(AppColors.fgOnWarn.resolved(.light)))
    }

    /// The dark theme keeps the recipe the prototype shipped: `warn600` at
    /// 60% with `warn300` on top.
    func testWarnWash_keepsTheCanonDarkRecipe() {
        XCTAssertEqual(hex(AppColors.warnWash.resolved(.dark)), hex(AppColors.warn600.resolved(.dark)))
        XCTAssertEqual(alpha(AppColors.warnWash.resolved(.dark)), 0.60, accuracy: 0.001)
        XCTAssertEqual(hex(AppColors.fgOnWarnWash.resolved(.dark)), hex(AppColors.warn300.resolved(.dark)))
    }

    // MARK: - Helpers

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

    /// Flatten a partially transparent colour onto an opaque one — a wash is
    /// only ever seen composited over the card it lies on.
    private func composite(_ color: UIColor, over background: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var backRed: CGFloat = 0, backGreen: CGFloat = 0, backBlue: CGFloat = 0, backAlpha: CGFloat = 0
        background.getRed(&backRed, green: &backGreen, blue: &backBlue, alpha: &backAlpha)
        return UIColor(
            red: red * alpha + backRed * (1 - alpha),
            green: green * alpha + backGreen * (1 - alpha),
            blue: blue * alpha + backBlue * (1 - alpha),
            alpha: 1
        )
    }

    private func alpha(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return alpha
    }

    private func hex(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let toByte: (CGFloat) -> UInt32 = { UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255)) }
        return (toByte(red) << 16) | (toByte(green) << 8) | toByte(blue)
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}
