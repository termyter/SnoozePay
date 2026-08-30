import UIKit
import XCTest
@testable import SnoozePay

/// Pins the theme-aware brand accent scales (#474).
///
/// The dark palette is the canon from `docs/design/snoozepay-2026-04-27/
/// project/tokens.css`. The light scale is *derived* from it rather than
/// copied: the dark values were chosen to glow on `#060912`, and on a light
/// surface most of them stop being readable — `warn500` lands at 1.85:1.
///
/// Each light step is solved for its ROLE, and this file is what stops the
/// next person from "fixing" a colour by eye and quietly dropping it below
/// the threshold its role depends on.
///
/// Contrast is measured against `bg2` (the raised card), not `bg0`. Accents
/// sit on cards far more often than on the app background, and `bg2` is the
/// worse surface in BOTH themes — lighter than `bg0` on dark, darker than
/// `bg0` on light. A value that clears here clears on every surface.
final class AppColorsContrastTests: XCTestCase {

    // MARK: - Roles

    /// WCAG 2.1 minimum for each step of the light scale.
    /// 300 decorative / borders · 400 large text · 500 body text · 600–700 emphasis.
    private static let lightRoleTargets: [(name: String, color: UIColor, target: CGFloat)] = [
        ("money300", AppColors.money300, 3.0),
        ("money400", AppColors.money400, 4.5),
        ("money500", AppColors.money500, 6.0),
        ("money600", AppColors.money600, 8.0),
        ("money700", AppColors.money700, 10.5),
        ("pain300", AppColors.pain300, 3.0),
        ("pain400", AppColors.pain400, 4.5),
        ("pain500", AppColors.pain500, 6.0),
        ("pain600", AppColors.pain600, 8.0),
        ("warn300", AppColors.warn300, 3.0),
        ("warn400", AppColors.warn400, 4.5),
        ("warn500", AppColors.warn500, 6.0),
        ("warn600", AppColors.warn600, 8.0),
        ("info500", AppColors.info500, 6.0)
    ]

    /// Absorbs sRGB rounding only — the derivation targets the nominal value,
    /// so a real regression moves the ratio by far more than this.
    private let tolerance: CGFloat = 0.05

    // MARK: - Light scale

    func testLightAccents_meetTheContrastTheirRoleRequires() {
        let card = AppColors.bg2.resolved(.light)
        for (name, color, target) in Self.lightRoleTargets {
            let ratio = contrast(color.resolved(.light), card)
            XCTAssertGreaterThanOrEqual(
                ratio, target - tolerance,
                "\(name) is \(String(format: "%.2f", ratio)):1 on the light raised card, "
                + "its role needs \(target):1"
            )
        }
    }

    /// The regression this file exists to prevent: the dark value carried over
    /// into light unchanged. Every accent must actually differ between themes.
    func testEveryAccent_resolvesToADifferentValuePerTheme() {
        for (name, color, _) in Self.lightRoleTargets {
            XCTAssertNotEqual(
                hex(color.resolved(.light)), hex(color.resolved(.dark)),
                "\(name) resolves to the same colour in both themes — the light scale is not wired up"
            )
        }
    }

    // MARK: - Dark scale

    /// The dark scale is the brand canon and must not drift while the light
    /// one is being tuned.
    func testDarkAccents_stillMatchTheBrandPalette() {
        let canon: [(String, UIColor, UInt32)] = [
            ("money300", AppColors.money300, 0x5EEAB8),
            ("money400", AppColors.money400, 0x2EDB9F),
            ("money500", AppColors.money500, 0x10B981),
            ("money600", AppColors.money600, 0x0E9D6E),
            ("money700", AppColors.money700, 0x0B7A56),
            ("pain300", AppColors.pain300, 0xFFB4A8),
            ("pain400", AppColors.pain400, 0xFF7A6B),
            ("pain500", AppColors.pain500, 0xF4523F),
            ("pain600", AppColors.pain600, 0xD43A28),
            ("warn300", AppColors.warn300, 0xFFD479),
            ("warn400", AppColors.warn400, 0xFFB84D),
            ("warn500", AppColors.warn500, 0xF59E0B),
            ("warn600", AppColors.warn600, 0xC97A06),
            ("info500", AppColors.info500, 0x4F8BFF)
        ]
        for (name, color, expected) in canon {
            XCTAssertEqual(
                hex(color.resolved(.dark)), expected,
                "\(name) drifted from tokens.css: expected "
                + String(format: "#%06X", expected)
                + ", got " + String(format: "#%06X", hex(color.resolved(.dark)))
            )
        }
    }

    // MARK: - Text on fills

    /// `fgOnMoney` inverts between themes: the light money fill is dark green
    /// and cannot carry the dark ink the bright dark-theme fill takes.
    /// `fgOnWarn` no longer inverts — since #520 its fill is `warnFill500`,
    /// amber in both themes, so the ink is near-black in both.
    /// Body-text threshold, since these labels are ordinary sized.
    func testInkOnFills_isReadableInBothThemes() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("fgOnMoney", AppColors.fgOnMoney, AppColors.money500),
            ("fgOnWarn", AppColors.fgOnWarn, AppColors.warnFill500)
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, ink, fill) in pairs {
                let ratio = contrast(ink.resolved(style), fill.resolved(style))
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5 - tolerance,
                    "\(name) is \(String(format: "%.2f", ratio)):1 on its fill in "
                    + "\(style == .light ? "light" : "dark")"
                )
            }
        }
    }

    /// `fgOnPain` is white over the pain fill in both themes. The dark theme
    /// lands at 3.43:1 — that is pre-existing (white on `#F4523F`) and only
    /// clears the large-text bar, so it is pinned there rather than at 4.5.
    /// Tightening it means changing `pain500`, which is a design decision.
    func testWhiteOnPainFill_clearsAtLeastTheLargeTextBar() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(AppColors.fgOnPain.resolved(style), AppColors.pain500.resolved(style))
            XCTAssertGreaterThanOrEqual(ratio, 3.0 - tolerance, "fgOnPain in \(style == .light ? "light" : "dark")")
        }
    }

    // MARK: - The warn role split (#520)
    //
    // `warn*` and `warnFill*` are two answers to two different questions, and
    // the whole point of splitting them is that neither answer can be quietly
    // given to the other question. These four tests are what makes the split
    // survive: without them a future "the warn scale should be consistent"
    // cleanup collapses the pair back and nothing goes red.

    /// The fill half is the canon `--sp-grad-warn` ramp, and `tokens.css` does
    /// NOT redefine the warn scale inside `[data-theme="light"]` — so the fill
    /// stays amber in light. A silent revert to the bronze ink tone is exactly
    /// the regression this pins.
    func testWarnFill_isTheCanonAmberInBothThemes() {
        let canon: [(String, UIColor, UInt32)] = [
            ("warnFill300", AppColors.warnFill300, 0xFFD479),
            ("warnFill500", AppColors.warnFill500, 0xF59E0B),
            ("warnFill600", AppColors.warnFill600, 0xC97A06)
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, color, expected) in canon {
                XCTAssertEqual(
                    hex(color.resolved(style)), expected,
                    "\(name) is " + String(format: "#%06X", hex(color.resolved(style)))
                    + " in \(style == .light ? "light" : "dark"), canon is "
                    + String(format: "#%06X", expected)
                )
            }
        }
    }

    /// The ink half has to clear body text on every surface it can land on —
    /// this is the #489 property, and switching an ink call site to the fill
    /// tone would drop it to 1.85:1 on the light card.
    ///
    /// There is exactly ONE registered exception: `AppColors.penaltyAmountDisplay32`,
    /// the 32pt snooze amount, which is `warnFill500` used as ink by PM
    /// decision (#673). It is named here so the rule and its exception cannot
    /// drift apart in separate files; the ratio it costs and the mitigation it
    /// leans on are pinned by `PenaltyDisplayColorTests`.
    ///
    /// ⚠️ What this test does NOT do is inspect call sites. It iterates token
    /// VALUES against the three surfaces, so a second `static let foo =
    /// warnFill500` used as text would be invisible to it, and `hardcoded_color`
    /// only matches raw `UIColor(...)` literals. The guard against that is the
    /// exception's NAME carrying its size (`…Display32`), not this assertion —
    /// said plainly here because an earlier version of this comment claimed the
    /// coverage it does not have.
    func testWarnInk_clearsBodyTextOnEverySurface() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, surface) in [("bg0", AppColors.bg0), ("bg1", AppColors.bg1), ("bg2", AppColors.bg2)] {
                let ratio = contrast(AppColors.warn500.resolved(style), surface.resolved(style))
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5 - tolerance,
                    "warn500 (ink) is \(String(format: "%.2f", ratio)):1 on \(name) in "
                    + "\(style == .light ? "light" : "dark")"
                )
            }
        }
    }

    /// The symmetric half: ink on the fill. `fgOnWarn` is near-black in both
    /// themes now, and white here would measure 2.15:1 — one contrast failure
    /// traded for another, which is the way this change could go wrong.
    func testInkOnWarnFill_clearsBodyTextInBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(AppColors.fgOnWarn.resolved(style), AppColors.warnFill500.resolved(style))
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5 - tolerance,
                "fgOnWarn is \(String(format: "%.2f", ratio)):1 on warnFill500 in "
                + "\(style == .light ? "light" : "dark")"
            )
        }
    }

    /// The measurement the issue turned on: the warn fill has to be told apart
    /// from the `money500` element sitting on it — the snooze slider's thumb on
    /// its track. The ink tone measured **1.00:1** against it in light, i.e.
    /// exactly isoluminant, and no amount of hue-tuning fixes a pair whose
    /// luminances match. The fill tone measures 3.26:1, clearing the 3:1
    /// non-text bar.
    ///
    /// Light only. The dark pair measures 1.18:1 and is NOT asserted here: it
    /// is the pairing the issue reports as reading correctly, so pinning it
    /// would be inventing a requirement the shipped design does not have.
    func testWarnFill_isDistinguishableFromTheMoneyThumbInLight() {
        let ratio = contrast(AppColors.warnFill500.resolved(.light), AppColors.money500.resolved(.light))
        XCTAssertGreaterThanOrEqual(
            ratio, 3.0 - tolerance,
            "warnFill500 vs money500 is \(String(format: "%.2f", ratio)):1 in light — "
            + "the filled and unfilled halves of the slider merge"
        )
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
        let a = luminance(lhs), b = luminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func hex(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let toByte: (CGFloat) -> UInt32 = { UInt32((($0 * 255).rounded()).clamped(0, 255)) }
        return (toByte(red) << 16) | (toByte(green) << 8) | toByte(blue)
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}
