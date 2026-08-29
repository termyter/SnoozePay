import UIKit
import XCTest
@testable import SnoozePay

/// Pins the readability of the foreground ramp (`fg1`...`fg4`) — the counterpart
/// of `AppColorsContrastTests`, which covers the accent scales (#504).
///
/// The ramp is four alphas over one ink per theme, and that is exactly why it
/// slipped: every step *looks* like a deliberate design value because it is one,
/// copied verbatim out of `tokens.css`. The canon light `fg-3`
/// (`rgba(10,15,31,.56)`) measures 4.19:1 on `bg2` — below the 4.5:1 body-text
/// bar — and nothing in the codebase said so, so eleven screens shipped their
/// meta copy under AA one screen at a time.
///
/// Two things have to hold at once here, and the pair is the whole point:
///
/// 1. every step that carries text clears the bar its role needs, and
/// 2. the steps stay *distinguishable from each other*.
///
/// Either one alone is trivially satisfiable — push the whole ramp to full
/// black and (1) passes while the design collapses into one voice; leave the
/// ramp at canon and (2) passes while the copy is unreadable. The fix for #504
/// is a point chosen between those two failures, so both are asserted.
///
/// Measurement note: `fgN` are ALPHA tokens. Reading their components directly
/// reports the ink's own luminance, which sails past any threshold regardless of
/// the surface — so everything below composites over the surface first.
final class AppColorsForegroundContrastTests: XCTestCase {

    /// The three surfaces ordinary copy actually lands on. `bg3`/`bg4` are
    /// hover/focus states that no meta line sits on statically; at the shipped
    /// alphas they measure 4.92:1 / 4.57:1 in light and 5.25:1 / 4.68:1 in dark,
    /// i.e. they clear too, but they are not pinned here because that would tie
    /// this file to the elevation ramp as well as to the ink ramp.
    private static let surfaces: [(name: String, color: UIColor)] = [
        ("bg0", AppColors.bg0),
        ("bg1", AppColors.bg1),
        ("bg2", AppColors.bg2)
    ]

    /// WCAG 2.1 minimum for normal-size text. The canon paints `.sp-meta`
    /// (`500 13px/18px`) and `.sp-caps` (`700 12px/16px`) with `fg3`, and WCAG
    /// counts large text only from 18pt — or 14pt bold — so the 3:1 large-text
    /// bar is not available to this token.
    private let bodyTextFloor: CGFloat = 4.5

    /// Absorbs 8-bit sRGB rounding of the composited colour only. The shipped
    /// values clear the floor by 0.6 or more, so a real regression moves the
    /// ratio far further than this.
    private let tolerance: CGFloat = 0.05

    // MARK: - The floor

    /// `fg2` and `fg3` both carry ordinary-size text — body copy and meta copy —
    /// so both owe 4.5:1 on every surface in both themes.
    ///
    /// `fg1` is stronger than `fg2` by construction and is covered by the
    /// ordering test. `fg4` is deliberately below the bar (2.10:1 in light): it
    /// is placeholder / disabled ink, which WCAG exempts, and pinning it at 4.5
    /// would demand that "unavailable" look identical to "available".
    func testTextSteps_clearBodyTextContrastOnEverySurface_inBothThemes() {
        let steps: [(name: String, color: UIColor)] = [
            ("fg2", AppColors.fg2),
            ("fg3", AppColors.fg3)
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (surfaceName, surface) in Self.surfaces {
                let background = surface.resolved(style)
                for (stepName, step) in steps {
                    let ratio = contrast(composite(step.resolved(style), over: background), background)
                    XCTAssertGreaterThanOrEqual(
                        ratio, bodyTextFloor - tolerance,
                        "\(stepName) is \(ratio.ratioText):1 on \(surfaceName) in \(style.name) — "
                        + "meta and body copy are normal-size text and owe 4.5:1"
                    )
                }
            }
        }
    }

    /// What makes the test above worth having: the value it replaced does NOT
    /// pass it.
    ///
    /// A threshold test is only as good as its distance from the thing it
    /// rejects, and that distance is invisible in a green run — so the canon
    /// alpha is measured here explicitly and asserted to fail. If someone
    /// "restores the canon" in `AppColors`, the test above goes red; if someone
    /// instead lowers the bar until the canon fits, this one goes red.
    func testTheCanonLightAlpha_isBelowTheBar_whichIsWhyItWasRaised() {
        let canonLightAlpha: CGFloat = 0.56
        for (surfaceName, surface) in Self.surfaces {
            let background = surface.resolved(.light)
            let canonInk = AppColors.fg3.resolved(.light).withAlphaComponent(canonLightAlpha)
            let ratio = contrast(composite(canonInk, over: background), background)
            XCTAssertLessThan(
                ratio, bodyTextFloor - tolerance,
                "the canon .56 light meta ink measures \(ratio.ratioText):1 on \(surfaceName) — "
                + "if it now clears the bar, #504 was solved elsewhere and this file is stale"
            )
        }
    }

    /// Dark was never the defect and must not be "fixed" along with light: the
    /// canon `.58` measures 5.68:1 on its worst surface here. Pinned as an
    /// upper bound as well as a lower one, because the cheap way to make the
    /// floor test pass everywhere is to darken every step in both themes, and
    /// that would quietly repaint the dark UI the issue never complained about.
    func testDarkMetaInk_staysAtTheCanonStrength() {
        XCTAssertEqual(alpha(AppColors.fg3.resolved(.dark)), 0.58, accuracy: 0.005,
                       "dark fg3 drifted off --sp-fg-3; #504 was a light-theme decision")
    }

    // MARK: - The ceiling: hierarchy

    /// `fg1 > fg2 > fg3 > fg4`, strictly, on every surface in both themes.
    ///
    /// The margin is what carries the meaning. Ordering alone would still hold
    /// with the steps a rounding error apart, and a ramp whose steps are a
    /// rounding error apart is one voice wearing four names.
    func testTheRamp_staysStrictlyOrderedByContrast_inBothThemes() {
        let ramp: [(name: String, color: UIColor)] = [
            ("fg1", AppColors.fg1),
            ("fg2", AppColors.fg2),
            ("fg3", AppColors.fg3),
            ("fg4", AppColors.fg4)
        ]
        let minimumSeparation: CGFloat = 1.0
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (surfaceName, surface) in Self.surfaces {
                let background = surface.resolved(style)
                let measured = ramp.map { step in
                    (step.name, contrast(composite(step.color.resolved(style), over: background), background))
                }
                for (stronger, weaker) in zip(measured, measured.dropFirst()) {
                    XCTAssertGreaterThan(
                        stronger.1, weaker.1 + minimumSeparation,
                        "\(stronger.0) (\(stronger.1.ratioText):1) and \(weaker.0) "
                        + "(\(weaker.1.ratioText):1) have merged on \(surfaceName) in \(style.name)"
                    )
                }
            }
        }
    }

    /// The other half of the #504 trade, stated in the units the decision was
    /// made in. 0.66 would have measured 6.03:1 — comfortably over the bar —
    /// and was rejected because it leaves 0.16 of alpha between meta and body.
    /// This is the assertion that keeps "more contrast is always better" from
    /// eating the ramp one PR at a time.
    func testLightMeta_keepsItsDistanceFromTheBodyStep() {
        let bodyAlpha = alpha(AppColors.fg2.resolved(.light))
        let metaAlpha = alpha(AppColors.fg3.resolved(.light))
        XCTAssertGreaterThanOrEqual(
            bodyAlpha - metaAlpha, 0.20 - 0.005,
            "light fg3 is \(metaAlpha) against fg2's \(bodyAlpha) — the meta step is climbing "
            + "into the body step"
        )
    }

    // MARK: - Helpers

    /// Flattens a translucent ink onto an opaque surface, the way the renderer
    /// does: straight source-over alpha blend in sRGB. Same shape as the helper
    /// in `AppColorsSurfaceRampTests`, kept file-local for the same reason the
    /// rest of the suite keeps its own — these files are read one at a time.
    private func composite(_ ink: UIColor, over background: UIColor) -> UIColor {
        let top = components(ink)
        let bottom = components(background)
        let opacity = top.alpha
        return UIColor(
            red: opacity * top.red + (1 - opacity) * bottom.red,
            green: opacity * top.green + (1 - opacity) * bottom.green,
            blue: opacity * top.blue + (1 - opacity) * bottom.blue,
            alpha: 1
        )
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        let parts = components(color)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(parts.red) + 0.7152 * channel(parts.green) + 0.0722 * channel(parts.blue)
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs), second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func alpha(_ color: UIColor) -> CGFloat {
        components(color).alpha
    }

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func components(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Channels(red: red, green: green, blue: blue, alpha: alpha)
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
    var ratioText: String { String(format: "%.2f", self) }
}
