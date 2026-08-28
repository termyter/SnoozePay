import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme guarantees for the Wallet tab and its transaction history
/// (#494).
///
/// Three decisions on these screens are judgement calls that would silently
/// regress if someone re-picked a colour by eye, so each is pinned by its
/// measurement rather than by a comment:
///
/// 1. **Which step of the brand ramp tints a row sum.** After #489 the ramp is
///    theme-aware, so "money400" no longer names one colour — it names a pair,
///    and only the light half is at risk.
/// 2. **That credit and debit are not distinguished by colour alone.** In
///    light the two tints land at the *same* luminance, so the "+" / "−" sign
///    is doing the work a colour-blind reader depends on.
/// 3. **That the footer disclaimer is legible in light.** It is canon `fg4`,
///    and the light block of `tokens.css` reuses the dark alpha — which puts
///    13pt copy at 2.10:1.
final class WalletLightThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text.
    private let normalTextFloor: CGFloat = 4.5
    /// WCAG 2.1 floor for large text and for non-text graphics (icon glyphs).
    private let largeTextFloor: CGFloat = 3.0
    /// Floor for quiet meta copy in light. Not a WCAG level — it is the
    /// measured value of the `fg3` meta step on `bg0` (4.26:1), pinned so the
    /// wallet's disclaimer can't drift back down to `fg4` (2.10:1).
    private let quietMetaFloor: CGFloat = 4.2
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.05

    // MARK: - Row sums

    /// Row sums sit on `SPCard(tone: .surface)`, whose fill is `bg1`
    /// (`#FFFFFF` light / `#0E1320` dark) — not `bg0`. Measured there:
    /// money400 5.27:1 light / 10.37:1 dark, pain400 5.22:1 / 7.28:1.
    func testRowSumInk_clearsBodyTextContrastOnTheCard_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = AppColors.bg1.resolved(style)
            for direction in [WalletLedgerDirection.incoming, .outgoing] {
                let ratio = contrast(WalletAmountTint.ink(for: direction).resolved(style), card)
                XCTAssertGreaterThanOrEqual(
                    ratio, normalTextFloor - tolerance,
                    "\(direction) row sum is \(ratio.ratioText):1 on the \(style.name) card"
                )
            }
        }
    }

    /// The neutral `.unclassified` ink is `fg3`, the meta token — 4.35:1 on
    /// the light card, i.e. just under the body-text bar. That is acceptable
    /// *here specifically* because the row sum is 20pt bold mono, which WCAG
    /// counts as large text (3:1). Pinned at the bar it actually has to clear
    /// so nobody "fixes" it by promoting the whole scale.
    func testUnclassifiedRowSum_clearsTheLargeTextBar_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = AppColors.bg1.resolved(style)
            // `fg3` is an ALPHA token — measuring it without compositing it
            // over the card first reports the ink's own luminance and quietly
            // passes any threshold.
            let ratio = contrast(
                composite(WalletAmountTint.ink(for: .unclassified).resolved(style), over: card),
                card
            )
            XCTAssertGreaterThanOrEqual(
                ratio, largeTextFloor - tolerance,
                "unclassified row sum is \(ratio.ratioText):1 on the \(style.name) card"
            )
        }
    }

    /// The regression this file exists to catch first: a row-sum tint that
    /// resolves to the dark brand value in light too. That is not a
    /// hypothetical — it is what every one of these screens looked like
    /// before #489.
    func testRowSumInk_resolvesToADifferentValuePerTheme() {
        for direction in [WalletLedgerDirection.incoming, .outgoing] {
            let ink = WalletAmountTint.ink(for: direction)
            XCTAssertNotEqual(
                hex(ink.resolved(.light)), hex(ink.resolved(.dark)),
                "\(direction) row sum is the same colour in both themes"
            )
        }
    }

    /// Credit and debit are ~0.05 apart in contrast against the light card
    /// (5.27 vs 5.22) — i.e. identical luminance, separated by hue only. A
    /// deuteranopic reader therefore cannot tell them apart by colour, and
    /// the sign prefix is not decoration but the actual affordance.
    func testCreditAndDebit_areNotSeparableByLuminance_soTheSignCarriesThem() {
        let card = AppColors.bg1.resolved(.light)
        let credit = contrast(WalletAmountTint.ink(for: .incoming).resolved(.light), card)
        let debit = contrast(WalletAmountTint.ink(for: .outgoing).resolved(.light), card)
        XCTAssertLessThan(
            abs(credit - debit), 0.5,
            "light credit \(credit.ratioText):1 vs debit \(debit.ratioText):1 — if these ever "
            + "diverge, revisit whether the sign is still the only differentiator"
        )

        XCTAssertEqual(WalletLedgerDirection.incoming.signPrefix, "+")
        XCTAssertEqual(WalletLedgerDirection.outgoing.signPrefix, "−")
    }

    /// An unclassifiable row must not guess a direction: neutral ink, no sign.
    func testUnclassifiedRow_staysNeutralAndUnsigned() {
        XCTAssertNil(WalletLedgerDirection.unclassified.signPrefix)
        let page = AppColors.bg1.resolved(.light)
        XCTAssertEqual(
            flattened(WalletAmountTint.ink(for: .unclassified).resolved(.light), over: page),
            flattened(AppColors.fg3.resolved(.light), over: page),
            "the neutral row lost the meta ink"
        )
    }

    func testDirectionMapping_followsTheLedgerNotTheGlyph() {
        XCTAssertEqual(WalletLedgerDirection(.topup), .incoming)
        XCTAssertEqual(WalletLedgerDirection(.promotion), .incoming)
        // `.refund` moves money INTO the wallet (#358) — it is a credit even
        // though its glyph is an undo arrow, not a plus.
        XCTAssertEqual(WalletLedgerDirection(.refund), .incoming)
        XCTAssertEqual(WalletLedgerDirection(.charge), .outgoing)
        XCTAssertEqual(WalletLedgerDirection(.unknown("future")), .unclassified)
    }

    /// The row's rendered string carries the sign, so the tint is redundant
    /// rather than load-bearing.
    func testRenderedAmount_carriesItsSign() {
        let charge = Transaction(type: .charge, amount: 50)
        let topup = Transaction(type: .topup, amount: 500)
        let alien = Transaction(type: .unknown("cashback"), amount: 30)

        XCTAssertTrue(
            WalletTransactionHistoryViewController.makeAmountLabel(for: charge)
                .attributedText?.string.hasPrefix("−") ?? false
        )
        XCTAssertTrue(
            WalletTransactionHistoryViewController.makeAmountLabel(for: topup)
                .attributedText?.string.hasPrefix("+") ?? false
        )
        let alienText = WalletTransactionHistoryViewController.makeAmountLabel(for: alien)
            .attributedText?.string ?? ""
        XCTAssertFalse(alienText.hasPrefix("+"))
        XCTAssertFalse(alienText.hasPrefix("−"))
    }

    // MARK: - Leading icon tile

    /// The 36×36 tile is a *wash* — the ink at 14% over the card — not a solid
    /// fill. The glyph on top must therefore stay the full-strength ink
    /// (4.36:1 / 4.26:1 in light); `fgOnMoney` / `fgOnPain` are white in light
    /// and would disappear here. This test is what stops that substitution.
    func testIconGlyph_readsOnItsOwnWash_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = AppColors.bg1.resolved(style)
            for direction in [WalletLedgerDirection.incoming, .outgoing] {
                let wash = composite(
                    WalletAmountTint.iconWash(for: direction).resolved(style), over: card
                )
                let ratio = contrast(WalletAmountTint.ink(for: direction).resolved(style), wash)
                XCTAssertGreaterThanOrEqual(
                    ratio, largeTextFloor - tolerance,
                    "\(direction) glyph is \(ratio.ratioText):1 on its \(style.name) wash"
                )
                // White ink is the wrong choice on a wash — pin the number
                // that makes that obvious rather than trusting the comment.
                let whiteInk = contrast(.white, wash)
                if style == .light {
                    XCTAssertLessThan(
                        whiteInk, largeTextFloor,
                        "white on the light wash measures \(whiteInk.ratioText):1"
                    )
                }
            }
        }
    }

    // MARK: - Footer disclaimer

    /// Hosted in a real `UIWindow` with the override set on the WINDOW: a
    /// detached view never receives the trait-change callback, so it keeps
    /// whatever it resolved at `init` and both themes measure identical.
    func testFooterDisclaimer_liftsInLightAndKeepsTheCanonQuietInkInDark() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let controller = WalletViewController()
        window.rootViewController = controller
        // Deliberately NOT made visible: the window only has to own the trait
        // environment. Making it visible would run the appearance cycle, and
        // `viewWillAppear` can present the balance-corruption alert.
        controller.loadViewIfNeeded()

        let footer = try XCTUnwrap(
            findLabel(in: controller.view, startingWith: "Покупка не возвращается"),
            "footer disclaimer is no longer on the Wallet tab"
        )

        window.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        try XCTSkipUnless(
            footer.traitCollection.userInterfaceStyle == .light,
            "window override did not propagate — a harness fact, not a component one"
        )
        // The `fgN` tokens are ALPHA over an ink, so both the measurement and
        // the identity check have to composite over the page first — `fg3`
        // and `fg4` share the same RGB and differ only in alpha.
        let lightPage = AppColors.bg0.resolved(.light)
        let lightInk = footer.textColor.resolvedColor(with: footer.traitCollection)
        let light = contrast(composite(lightInk, over: lightPage), lightPage)
        // `fg4` measures 2.10:1 on the light page — unreadable for copy the
        // user is expected to act on. `fg3` is 4.26:1: the meta step every
        // other quiet line in the light theme already sits at. The next rung
        // up, `fg2`, is 10.66:1 and would make a disclaimer as loud as body
        // copy, so the bar here is "clearly above the fg4 floor", not AA.
        XCTAssertGreaterThanOrEqual(
            light, quietMetaFloor - tolerance,
            "footer disclaimer is \(light.ratioText):1 in light — it must not slide back "
            + "toward the 2.10:1 that canon fg4 gives here"
        )
        XCTAssertEqual(
            flattened(lightInk, over: lightPage),
            flattened(AppColors.fg3.resolved(.light), over: lightPage),
            "light footer is no longer on the meta step"
        )

        // Dark is the canon and deliberately quiet: the fix is light-only.
        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        let darkPage = AppColors.bg0.resolved(.dark)
        XCTAssertEqual(
            flattened(footer.textColor.resolvedColor(with: footer.traitCollection), over: darkPage),
            flattened(AppColors.fg4.resolved(.dark), over: darkPage),
            "dark footer drifted off the canon --sp-fg-4"
        )
    }

    // MARK: - 7-day chart

    /// `CAGradientLayer.colors` stores plain `CGColor`s: resolved once,
    /// frozen forever. The bars used to be painted at `init` and never
    /// re-resolved, so launching in dark and switching to light left the dark
    /// `pain300` top stop (`#FFB4A8`, 1.9:1) on a white card. Hosted in a
    /// window because a detached view never gets the trait-change callback —
    /// without the window this test passes against the broken code.
    func testWeeklyChartBars_reresolveOnAThemeFlip() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIViewController()
        let chart = WalletWeeklyChartView()
        chart.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        host.view.addSubview(chart)
        window.rootViewController = host
        chart.update(values: [0, 0, 0, 0, 0, 0, Decimal(200)])

        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        try XCTSkipUnless(
            chart.traitCollection.userInterfaceStyle == .dark,
            "window override did not propagate — a harness fact, not a component one"
        )
        let inDark = gradientStops(in: chart)
        try XCTSkipUnless(!inDark.isEmpty, "no gradient bar was installed for a non-zero day")

        window.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        let inLight = gradientStops(in: chart)

        XCTAssertNotEqual(
            inDark, inLight,
            "bar gradient kept its dark stops after the flip — CGColor never re-resolves itself"
        )
    }

    /// The seam the fix leans on: a trait-explicit gradient builder. If this
    /// ever returns the same stops for both themes, the view-level test above
    /// is measuring nothing.
    func testPainGradientStops_differPerTheme() {
        let light = SPSupport.painGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
        let dark = SPSupport.painGradientColors(for: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(light.count, dark.count)
        for (index, pair) in zip(light, dark).enumerated() {
            XCTAssertNotEqual(
                hex(UIColor(cgColor: pair.0)), hex(UIColor(cgColor: pair.1)),
                "pain gradient stop \(index) is identical in both themes"
            )
        }
    }

    // MARK: - Fixtures

    /// Every gradient stop under `root`, flattened to hex so two snapshots
    /// can be compared across a theme flip.
    private func gradientStops(in root: UIView) -> [UInt32] {
        var found = gradientStops(in: root.layer)
        for subview in root.subviews {
            found.append(contentsOf: gradientStops(in: subview))
        }
        return found
    }

    private func gradientStops(in layer: CALayer) -> [UInt32] {
        var found: [UInt32] = []
        if let gradient = layer as? CAGradientLayer, let colors = gradient.colors {
            for case let color as CGColor in colors {
                found.append(hex(UIColor(cgColor: color)))
            }
        }
        for sublayer in layer.sublayers ?? [] {
            found.append(contentsOf: gradientStops(in: sublayer))
        }
        return found
    }

    private func findLabel(in root: UIView, startingWith prefix: String) -> UILabel? {
        if let label = root as? UILabel, label.text?.hasPrefix(prefix) == true {
            return label
        }
        for subview in root.subviews {
            if let found = findLabel(in: subview, startingWith: prefix) { return found }
        }
        return nil
    }

    // MARK: - Colour maths

    /// Hex of `color` after it is laid over `background`. Alpha tokens
    /// (`fg2`/`fg3`/`fg4`) share an RGB and differ only in alpha, so a raw
    /// hex comparison cannot tell them apart.
    private func flattened(_ color: UIColor, over background: UIColor) -> UInt32 {
        hex(composite(color, over: background))
    }

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

    private func hex(_ color: UIColor) -> UInt32 {
        let rgb = channels(color)
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(rgb.red) << 16) | (toByte(rgb.green) << 8) | toByte(rgb.blue)
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
    /// Two decimals — a failure message should carry the measurement.
    var ratioText: String { String(format: "%.2f", self) }
}
