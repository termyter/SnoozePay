import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme guarantees for the payment-methods screen (#495).
///
/// The screen has one deliberate exception to "everything is theme-aware":
/// the Apple Pay hero is a payment *instrument*, not an app surface, so it
/// stays `#15151A` in both themes exactly as iOS Wallet keeps a dark card
/// dark on a white page. Everything that follows from that decision is what
/// these tests pin:
///
/// 1. The fill must NOT flip — a `bg1` Apple Pay card would be a white slab
///    with white ink on it.
/// 2. Because the fill never flips, its ink cannot be `fg1`/`fg2`/`fg3`
///    (near-black in light). It has to be the `fgOnPaymentCard*` pair, and
///    that pair has to clear AA against the fill in both themes.
/// 3. The two rows on the page — the default method and the ghost "add card"
///    tile — must stay distinguishable once the page turns near-white.
///
/// Views are hosted in a real `UIWindow` and the override is set on the
/// **window**: a detached view never receives the trait-change callback, keeps
/// its `init`-time resolution, and would measure identical in both themes.
final class PaymentMethodsLightThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text (the caps labels are 12pt bold,
    /// which is *not* "large" — large starts at 14pt bold).
    private let normalTextFloor: CGFloat = 4.5
    /// WCAG 2.1 floor for non-text separation (fills, borders).
    private let objectFloor: CGFloat = 3.0
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.05

    /// Windows have to outlive the assertions that read from them, and have to
    /// be dismissed afterwards so they don't stack up across the suite.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - The instrument fill does not flip

    func testApplePayCardFill_isIdenticalInBothThemes() throws {
        let light = try applePayCard(in: .light)
        let dark = try applePayCard(in: .dark)

        XCTAssertEqual(
            rgbaText(light.resolvedBackground), rgbaText(dark.resolvedBackground),
            "the Apple Pay card is an instrument, not a surface — flipping its "
                + "fill to bg1 in light turns it into a white slab"
        )
    }

    /// A dark instrument on a near-white page is the *point*: it is what makes
    /// "this is the method you pay with" legible without a selected-state
    /// chip. Measured, not eyeballed.
    func testApplePayCardFill_separatesFromTheLightPage() throws {
        let card = try applePayCard(in: .light)
        let ratio = contrast(
            card.resolvedBackground,
            AppColors.bg0.resolvedFor(.light)
        )
        XCTAssertGreaterThanOrEqual(
            ratio, objectFloor - tolerance,
            "default method reads at \(ratio.formattedRatio):1 against the light page"
        )
    }

    // MARK: - Ink on the instrument

    /// Every label rendered inside the card, measured against the fill it is
    /// actually drawn on — in both themes, because the fill is shared.
    func testEveryLabelOnTheCard_clearsAA_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = try applePayCard(in: style)
            let labels = card.view.descendants(ofType: UILabel.self)
            XCTAssertFalse(labels.isEmpty, "no labels found on the Apple Pay card")

            for label in labels {
                let ink = label.renderedInk.resolvedFor(style)
                let ratio = contrast(
                    composite(ink, over: card.resolvedBackground),
                    card.resolvedBackground
                )
                XCTAssertGreaterThanOrEqual(
                    ratio, normalTextFloor - tolerance,
                    "«\(label.plainText)» is \(ratio.formattedRatio):1 on the card in \(style.styleName)"
                )
            }
        }
    }

    /// Regression guard for the specific literal this issue removed: the canon
    /// carried a second, fainter ink step (40% white) that measured 3.83:1 on
    /// `#15151A` and failed AA in *both* themes. If someone reintroduces a
    /// step below the surviving one, this is the number they have to beat.
    func testPaymentCardMetaInk_clearsAA_whereTheFortyPercentStepDidNot() {
        let fill = AppColors.paymentCard
        let retired = UIColor(white: 1, alpha: 0.4)

        let retiredRatio = contrast(composite(retired, over: fill), fill)
        XCTAssertLessThan(
            retiredRatio, normalTextFloor,
            "the retired 40% step measured \(retiredRatio.formattedRatio):1 — that is why it went"
        )

        let shipped = contrast(
            composite(AppColors.fgOnPaymentCardMeta, over: fill),
            fill
        )
        XCTAssertGreaterThanOrEqual(
            shipped, normalTextFloor - tolerance,
            "fgOnPaymentCardMeta is \(shipped.formattedRatio):1 on the card"
        )
    }

    /// `fgOnPaymentCard*` is ink for a fill that is dark in BOTH themes, so —
    /// unlike `fg1` — it must not be theme-aware. A dynamic ink here would go
    /// near-black in light and vanish into `#15151A`.
    func testPaymentCardInks_areNotThemeAware() {
        for ink in [AppColors.fgOnPaymentCard, AppColors.fgOnPaymentCardMeta, AppColors.paymentCardEdge] {
            XCTAssertEqual(
                rgbaText(ink.resolvedFor(.light)), rgbaText(ink.resolvedFor(.dark)),
                "ink on the always-dark payment card must not flip with the theme"
            )
        }
    }

    // MARK: - Default method vs. ghost tile

    /// The ghost "add card" tile is an `SPCard(.outline)`: transparent fill,
    /// so on a light page its fill *is* the page (1.00:1) and the hairline is
    /// the only thing holding it. That is the intended difference from the
    /// filled default method — but the hairline has to actually be there.
    func testGhostAddCardTile_isOutlinedNotFilled_inLight() throws {
        let hosted = try host(style: .light)
        let ghost = try XCTUnwrap(
            hosted.descendants(ofType: SPCard.self).first,
            "the add-card placeholder is gone"
        )

        XCTAssertTrue(ghost.tone == .outline, "the add-card tile stopped being an outline card")
        XCTAssertGreaterThan(
            ghost.layer.borderWidth, 0,
            "a transparent tile on a near-white page has nothing but its hairline"
        )
        XCTAssertEqual(
            ghost.layer.shadowOpacity, 0,
            "the ghost tile must stay flat — a shadow would read as a second filled method"
        )
    }

    /// The footer caption is information, not a disabled control. `fg4` (the
    /// placeholder step) measures 2.10:1 on the light page; the caption now
    /// uses `fg3`, which the canon prescribes for captions of this kind.
    func testFooterCaptionInk_outreadsThePlaceholderStep_inLight() {
        let page = AppColors.bg0.resolvedFor(.light)
        let caption = contrast(composite(AppColors.fg3.resolvedFor(.light), over: page), page)
        let placeholder = contrast(composite(AppColors.fg4.resolvedFor(.light), over: page), page)

        XCTAssertLessThan(
            placeholder, objectFloor,
            "fg4 measures \(placeholder.formattedRatio):1 — too faint to carry copy"
        )
        XCTAssertGreaterThan(
            caption, placeholder,
            "fg3 (\(caption.formattedRatio):1) must out-read fg4 (\(placeholder.formattedRatio):1)"
        )
    }

    // MARK: - Fixtures

    private struct HostedCard {
        let view: UIView
        let resolvedBackground: UIColor
    }

    /// Hosts the screen in a real window and forces `style` on the **window**,
    /// so every descendant receives the trait change instead of keeping its
    /// `init`-time resolution.
    private func host(style: UIUserInterfaceStyle) throws -> UIView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        hostWindows.append(window)

        let controller = PaymentMethodsViewController()
        window.rootViewController = controller
        controller.loadViewIfNeeded()
        window.setNeedsLayout()
        window.layoutIfNeeded()

        try XCTSkipUnless(
            controller.view.traitCollection.userInterfaceStyle == style,
            "window did not propagate overrideUserInterfaceStyle"
        )
        return controller.view
    }

    /// The Apple Pay hero, located by its fill rather than by index so a
    /// reordered stack renames nothing silently.
    private func applePayCard(in style: UIUserInterfaceStyle) throws -> HostedCard {
        let hosted = try host(style: style)
        let expected = rgbaText(AppColors.paymentCard.resolvedFor(style))
        let card = try XCTUnwrap(
            hosted.descendants(ofType: UIView.self).first { candidate in
                guard let fill = candidate.backgroundColor else { return false }
                return rgbaText(fill.resolvedFor(style)) == expected
            },
            "no view on the screen is filled with AppColors.paymentCard"
        )
        return HostedCard(
            view: card,
            resolvedBackground: try XCTUnwrap(card.backgroundColor).resolvedFor(style)
        )
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

    private func rgbaText(_ color: UIColor) -> String {
        let rgb = channels(color)
        return String(format: "%.3f/%.3f/%.3f/%.3f", rgb.red, rgb.green, rgb.blue, rgb.alpha)
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
    func resolvedFor(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIView {
    func descendants<T: UIView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            let nested = subview.descendants(ofType: type)
            return (subview as? T).map { [$0] + nested } ?? nested
        }
    }
}

private extension UILabel {
    /// The colour the label actually draws with. Attributed labels ignore
    /// `textColor`, so reading it would measure a value nothing renders.
    var renderedInk: UIColor {
        if let attributed = attributedText, attributed.length > 0,
           let colour = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor {
            return colour
        }
        return textColor
    }

    var plainText: String { attributedText?.string ?? text ?? "" }
}

private extension UIUserInterfaceStyle {
    var styleName: String { self == .light ? "light" : "dark" }
}

private extension CGFloat {
    /// Two decimals — failure messages carry the measurement, not a shrug.
    var formattedRatio: String { String(format: "%.2f", self) }
}
