import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme floor for the Settings screen (#496).
///
/// Two separate regressions are pinned here, both invisible to a dark-only
/// eyeball pass:
///
/// 1. The toast used `.white` on `UIColor.label` at 90%. `label` inverts with
///    the theme, so in DARK the pill was white and the text was white. Over
///    `bg0` at 90% alpha that composites to 1.24:1 — text-shaped noise.
///    Reading the code in light mode gives no hint of it.
/// 2. `.insetGrouped` card rows were fill + shadow only. In light the fill is
///    `#FFFFFF` on a `#F4F6FB` page — 1.06:1 of surface separation — so the
///    shadow was carrying the whole card edge on its own. The outline is what
///    makes the section a card, and it has to exist without doubling where two
///    rows meet.
@MainActor
final class SettingsLightThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text. The toast is 15pt medium.
    private let minimumContrast: CGFloat = 4.5

    /// Windows hosting the surfaces under test. Held for the lifetime of the
    /// test case: a released window takes its subtree's traits with it.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Toast

    func testToastInk_readsOnItsPill_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ink = SettingsToastLabel.inkColor.resolved(style)
            let fill = SettingsToastLabel.fillColor.resolved(style)
            let ratio = contrastRatio(ink, fill)
            XCTAssertGreaterThanOrEqual(
                ratio, minimumContrast,
                "toast ink is \(String(format: "%.2f", ratio)):1 on its pill in \(style.debugName)"
            )
        }
    }

    /// The regression this file exists for. If someone "simplifies" the toast
    /// back to white-on-`label`, this reminds them what that measured.
    func testPreviousToastRecipe_wasInvisibleInDark() {
        let oldFill = composite(
            UIColor.label.withAlphaComponent(0.9).resolved(.dark),
            over: AppColors.bg0.resolved(.dark)
        )
        let ratio = contrastRatio(.white, oldFill)
        XCTAssertLessThan(
            ratio, 1.3,
            "white on `label`@90% in dark measured \(String(format: "%.2f", ratio)):1 — "
            + "if this ever passes, the palette changed and the comment needs revisiting"
        )
    }

    func testToastPill_carriesShadowAndBorder_soItDetachesFromLightContent() {
        let toast = SettingsToastLabel()
        toast.overrideUserInterfaceStyle = .light
        toast.text = "Скопировано"
        toast.frame = CGRect(x: 0, y: 0, width: 160, height: SettingsToastLabel.minimumHeight)
        toast.setNeedsLayout()
        toast.layoutIfNeeded()

        XCTAssertGreaterThan(toast.layer.borderWidth, 0, "light pill needs an outline")
        XCTAssertNotNil(toast.layer.borderColor)
        XCTAssertGreaterThan(toast.layer.shadowOpacity, 0, "light pill needs a lift")
        XCTAssertFalse(toast.layer.masksToBounds, "masksToBounds would clip the shadow away")
        XCTAssertNotNil(toast.layer.shadowPath)
    }

    func testToastPadding_comesFromTheSpacingScale() {
        let toast = SettingsToastLabel()
        toast.text = "x"
        let bare = UILabel()
        bare.font = AppTypography.body
        bare.text = "x"
        XCTAssertEqual(
            toast.intrinsicContentSize.width - bare.intrinsicContentSize.width,
            AppSpacing.sp4 * 2,
            accuracy: 0.5
        )
        XCTAssertEqual(
            toast.intrinsicContentSize.height - bare.intrinsicContentSize.height,
            AppSpacing.sp2 * 2,
            accuracy: 0.5
        )
        XCTAssertEqual(SettingsToastLabel.minimumHeight, 36)
    }

    // MARK: - Card rows

    func testCardRow_fillsTheBrandCardToken_notTheSystemGrey() {
        let cell = styledCell(position: .single)
        guard let surface = cell.backgroundView as? CardRowBackgroundView else {
            return XCTFail("styleAsCardRow must install a CardRowBackgroundView")
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                hex(surface.backgroundColor?.resolved(style) ?? .clear),
                hex(AppColors.bg1.resolved(style)),
                "card row fill in \(style.debugName)"
            )
        }
        XCTAssertEqual(hex(cell.backgroundColor ?? .red), hex(UIColor.clear))
    }

    /// The reason the outline is not optional in light: fill alone gives the
    /// card 1.06:1 of separation from the page it sits on.
    func testLightCardFill_isNearlyIndistinguishableFromThePage() {
        let ratio = contrastRatio(AppColors.bg1.resolved(.light), AppColors.bg0.resolved(.light))
        XCTAssertLessThan(ratio, 1.15, "measured \(String(format: "%.3f", ratio)):1")
    }

    func testEveryRowPosition_drawsAnOutline_inBothThemes() {
        for position in [CardRowPosition.single, .first, .middle, .last] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let outline = outlineLayer(of: laidOutSurface(position: position, style: style))
                XCTAssertNotNil(outline?.path, "\(position) outline path in \(style.debugName)")
                XCTAssertGreaterThan(outline?.lineWidth ?? 0, 0)
                XCTAssertNotNil(outline?.strokeColor)
            }
        }
    }

    /// Middle rows stroke the two side rails only. A four-sided border per row
    /// would render a double-thick rule against the system row separator.
    func testMiddleRow_strokesOnlyTheSideRails() {
        let surface = laidOutSurface(position: .middle, style: .light)
        let path = outlineLayer(of: surface)?.path
        let box = path?.boundingBox ?? .zero
        XCTAssertEqual(box.height, surface.bounds.height, accuracy: 0.01, "rails span the full row")
        XCTAssertLessThan(box.width, surface.bounds.width, "rails are inset by half a hairline")
        XCTAssertGreaterThan(box.width, surface.bounds.width - 2, "rails still hug the edges")
    }

    /// First/last cap the section, so their outline pulls in vertically on the
    /// capped side and runs flush on the side the neighbour continues.
    func testCapRows_pullInOnlyOnTheEdgeTheyCap() {
        let first = laidOutSurface(position: .first, style: .light)
        let firstBox = outlineLayer(of: first)?.path?.boundingBox ?? .zero
        XCTAssertGreaterThan(firstBox.minY, 0, "first row insets its top edge")
        XCTAssertEqual(firstBox.maxY, first.bounds.maxY, accuracy: 0.01, "…and runs flush at the bottom")

        let last = laidOutSurface(position: .last, style: .light)
        let lastBox = outlineLayer(of: last)?.path?.boundingBox ?? .zero
        XCTAssertEqual(lastBox.minY, 0, accuracy: 0.01, "last row runs flush at the top")
        XCTAssertLessThan(lastBox.maxY, last.bounds.maxY, "…and insets its bottom edge")
    }

    func testShadow_onSectionCapsOnly() {
        for position in [CardRowPosition.single, .first, .last] {
            let surface = laidOutSurface(position: position, style: .light)
            XCTAssertGreaterThan(surface.layer.shadowOpacity, 0, "\(position) should lift")
            XCTAssertNotNil(surface.layer.shadowPath, "\(position) should rasterise its shadow")
        }
        let middle = laidOutSurface(position: .middle, style: .light)
        XCTAssertEqual(middle.layer.shadowOpacity, 0, "middle rows must not stack shadows")
    }

    /// The row decoration caches `cgColor`, so it has to re-resolve when the
    /// style flips under an already-rendered row rather than only on dequeue.
    func testOutlineColour_differsPerTheme_soAFlipRepaintsRenderedRows() {
        let light = laidOutSurface(position: .first, style: .light)
        let dark = laidOutSurface(position: .first, style: .dark)
        let lightStroke = outlineLayer(of: light)?.strokeColor.map { hex(UIColor(cgColor: $0)) }
        let darkStroke = outlineLayer(of: dark)?.strokeColor.map { hex(UIColor(cgColor: $0)) }
        XCTAssertNotNil(lightStroke)
        XCTAssertNotEqual(lightStroke, darkStroke)
        XCTAssertNotEqual(light.layer.shadowRadius, dark.layer.shadowRadius)
    }

    // MARK: - Row accents on the card

    /// The snooze-price row tints its glyph and value with `warn400`. Cards are
    /// `bg1`, and after #489 the light `warn400` is bronze — check it still
    /// clears the body-text bar there, since `AppColorsContrastTests` only
    /// pins the scale against the worse `bg2` surface.
    func testSnoozePriceAccent_readsOnTheCard_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrastRatio(
                AppColors.warn400.resolved(style),
                AppColors.bg1.resolved(style)
            )
            XCTAssertGreaterThanOrEqual(
                ratio, minimumContrast,
                "warn400 is \(String(format: "%.2f", ratio)):1 on the card in \(style.debugName)"
            )
        }
    }

    // MARK: - Fixtures

    private func styledCell(position: CardRowPosition) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.styleAsCardRow(position: position)
        return cell
    }

    /// The row decoration resolves its `cgColor`s once at `init` and after that
    /// only from `registerForTraitChanges`. UIKit propagates a style change
    /// down a real hierarchy, so a detached view never gets that callback and
    /// keeps whatever `UITraitCollection.current` happened to be when it was
    /// constructed — which is how both themes previously measured as light.
    /// Hosting the surface in a window is what makes `style` mean anything.
    private func laidOutSurface(
        position: CardRowPosition,
        style: UIUserInterfaceStyle
    ) -> CardRowBackgroundView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 343, height: 52))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        hostWindows.append(window)

        let surface = CardRowBackgroundView(position: position, cornerRadius: AppRadius.sm)
        surface.frame = window.bounds
        window.addSubview(surface)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return surface
    }

    private func outlineLayer(of surface: CardRowBackgroundView) -> CAShapeLayer? {
        surface.layer.sublayers?.compactMap { $0 as? CAShapeLayer }
            .first { $0.name != AppShadow.ambientShadow1LayerName }
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

    private func hex(_ color: UIColor) -> String {
        let rgb = channels(color)
        return String(
            format: "%02X%02X%02X@%.2f",
            Int((rgb.red * 255).rounded()),
            Int((rgb.green * 255).rounded()),
            Int((rgb.blue * 255).rounded()),
            rgb.alpha
        )
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String {
        self == .dark ? "dark" : "light"
    }
}
