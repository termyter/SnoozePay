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
///     `fgOnWarnWash`, not `fgOnWarn`. White on the wash measures ~1.2:1 —
///     the defect that was fixed in `SPAlarmBackendBanner`.
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

    /// The misuse this pairing exists to prevent: `fgOnWarn` is ink for a
    /// SOLID `warn500` fill. On the wash it is white-on-tint and unreadable, so it
    /// must never be the better choice — if it ever is, the wash stopped being
    /// a wash.
    func testFgOnWarn_wouldBeWorseThanFgOnWarnWashOnTheWash() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let fill = composite(AppColors.warnWash.resolved(style), over: AppColors.bg1.resolved(style))
            let wash = contrast(AppColors.fgOnWarnWash.resolved(style), fill)
            let solid = contrast(AppColors.fgOnWarn.resolved(style), fill)
            XCTAssertGreaterThan(
                wash, solid,
                "fgOnWarn beats fgOnWarnWash on the wash in \(style == .light ? "light" : "dark") — "
                + "the wash recipe no longer matches its ink"
            )
        }
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
