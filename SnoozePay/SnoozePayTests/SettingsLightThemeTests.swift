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
/// 1b. …and the fix for that (`bg3`) moved the failure rather than ending it:
///    the ink read fine, but the pill measured 1.19:1 against the light page,
///    so the hairline and the glyphs were the only thing describing its shape,
///    and it sat on top of the tab bar besides (#518). The lesson the tests
///    now encode: measuring ink against its own pill says nothing about
///    whether the pill is visible.
/// 2. `.insetGrouped` card rows were fill + shadow only. In light the fill is
///    `#FFFFFF` on a `#F4F6FB` page — 1.06:1 of surface separation — so the
///    shadow was carrying the whole card edge on its own. The outline is what
///    makes the section a card, and it has to exist without doubling where two
///    rows meet.
@MainActor
final class SettingsLightThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text. The toast is 15pt medium.
    private let minimumContrast: CGFloat = 4.5

    /// WCAG 2.1 §1.4.11 floor for a non-text UI surface — what the pill itself
    /// has to clear against whatever it is floating over.
    private let minimumSurfaceContrast: CGFloat = 3.0

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

    /// The defect this section grew for the second time (#518): the ink test
    /// above measures the pill against ITSELF, so a pill that is invisible
    /// against the page it floats over sails straight through it. `bg3` did
    /// exactly that — 1.19:1 in light, with only the hairline and the glyphs
    /// carrying the shape.
    ///
    /// `bg0` is the page, but a toast is not pinned to one surface; it drifts
    /// over cards and chips too, so every step of the ramp is checked.
    func testToastSurface_separatesFromEverySurfaceItFloatsOver_inBothThemes() throws {
        let surfaces: [(String, UIColor)] = [
            ("bg0", AppColors.bg0), ("bg1", AppColors.bg1), ("bg2", AppColors.bg2),
            ("bg3", AppColors.bg3), ("bg4", AppColors.bg4)
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let toast = hostedToast(style: style)
            try XCTSkipUnless(
                toast.traitCollection.userInterfaceStyle == style,
                "host window did not adopt \(style.debugName) — the measurement would be of the wrong theme"
            )
            let pill = try XCTUnwrap(toast.backgroundColor)
            let fill = pill.resolvedColor(with: toast.traitCollection)
            for (name, surface) in surfaces {
                let ratio = contrastRatio(fill, surface.resolved(style))
                XCTAssertGreaterThanOrEqual(
                    ratio, minimumSurfaceContrast,
                    "toast pill is \(String(format: "%.2f", ratio)):1 on \(name) in \(style.debugName)"
                )
            }
        }
    }

    /// Why the fix could not stay inside the surface ramp: not one step of it
    /// clears the 3:1 a UI surface needs against the page. If this ever starts
    /// failing, the palette moved and the toast can go back to being a surface.
    func testNoSurfaceStep_everSeparatesFromThePage() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for surface in [AppColors.bg1, AppColors.bg2, AppColors.bg3, AppColors.bg4] {
                let ratio = contrastRatio(surface.resolved(style), AppColors.bg0.resolved(style))
                XCTAssertLessThan(
                    ratio, minimumSurfaceContrast,
                    "a surface step now clears 3:1 on the page in \(style.debugName) "
                    + "(\(String(format: "%.2f", ratio)):1) — revisit the inverse-pill decision"
                )
            }
        }
    }

    /// The shipped defect, pinned by its number: `bg3` on the light page.
    func testPreviousToastFill_wasFlatAgainstTheLightPage() {
        let ratio = contrastRatio(AppColors.bg3.resolved(.light), AppColors.bg0.resolved(.light))
        XCTAssertLessThan(
            ratio, 1.25,
            "bg3 on the light page measured \(String(format: "%.2f", ratio)):1 — the reason #518 exists"
        )
    }

    /// Fill and ink have to flip as a pair. Every failure this file records
    /// (#496, #518) is one of the two moving without the other.
    func testToastFillAndInk_flipTogether() throws {
        let light = hostedToast(style: .light)
        let dark = hostedToast(style: .dark)
        try XCTSkipUnless(
            light.traitCollection.userInterfaceStyle == .light
                && dark.traitCollection.userInterfaceStyle == .dark,
            "host windows did not adopt their styles"
        )
        let lightFill = try XCTUnwrap(light.backgroundColor)
        let darkFill = try XCTUnwrap(dark.backgroundColor)
        XCTAssertNotEqual(
            hex(lightFill.resolvedColor(with: light.traitCollection)),
            hex(darkFill.resolvedColor(with: dark.traitCollection)),
            "pill fill must differ per theme"
        )
        XCTAssertNotEqual(
            hex(light.textColor.resolvedColor(with: light.traitCollection)),
            hex(dark.textColor.resolvedColor(with: dark.traitCollection)),
            "pill ink must differ per theme"
        )
    }

    /// The border caches a `cgColor`, which does not follow a theme flip on its
    /// own. A pill already on screen when the user flips the system theme has
    /// to repaint, not keep the hairline it was born with.
    func testToastBorder_repaintsWhenTheThemeFlipsUnderARenderedPill() throws {
        let toast = hostedToast(style: .light)
        try XCTSkipUnless(
            toast.traitCollection.userInterfaceStyle == .light,
            "host window did not adopt light"
        )
        let lightBorder = try XCTUnwrap(toast.layer.borderColor)
        let before = hex(UIColor(cgColor: lightBorder))

        toast.window?.overrideUserInterfaceStyle = .dark
        toast.window?.layoutIfNeeded()
        try XCTSkipUnless(
            toast.traitCollection.userInterfaceStyle == .dark,
            "host window did not adopt dark on flip"
        )
        let darkBorder = try XCTUnwrap(toast.layer.borderColor)
        let after = hex(UIColor(cgColor: darkBorder))
        XCTAssertNotEqual(before, after, "hairline kept its light-theme cgColor after the flip")
    }

    // MARK: - Toast placement

    /// The other half of #518: the pill was pinned to the window's bottom safe
    /// area, which sits *under* the tab bar, so it covered the "Кошелёк" item.
    /// The bar's height is UIKit's to decide, so the assertion is against its
    /// runtime frame rather than against a remembered number.
    func testToast_sitsClearOfTheTabBar_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let window = windowHostingATabBar(style: style)
            let bar = try XCTUnwrap(
                SettingsToastLayout.obstructingTabBar(in: window),
                "a mounted tab bar should be found from the window"
            )
            let barFrame = bar.convert(bar.bounds, to: window)
            try XCTSkipUnless(barFrame.height > 0, "UIKit gave the bar no height in this environment")

            let toast = SettingsToastLabel()
            toast.text = "Скопировано"
            SettingsToastLayout.install(toast, in: window)
            window.setNeedsLayout()
            window.layoutIfNeeded()

            XCTAssertFalse(
                toast.frame.intersects(barFrame),
                "toast \(toast.frame) overlaps the tab bar \(barFrame) in \(style.debugName)"
            )
            XCTAssertEqual(
                toast.frame.maxY, barFrame.minY - SettingsToastLayout.gap, accuracy: 0.5,
                "toast should rest one gap above the bar in \(style.debugName)"
            )
            XCTAssertGreaterThan(toast.frame.height, 0)
        }
    }

    /// Settings can also be reached with no tab bar on screen (the tour mounts
    /// it that way). Then the safe area is the right edge to sit above.
    func testToast_fallsBackToTheSafeArea_whenNoTabBarIsOnScreen() throws {
        let toast = hostedToast(style: .light)
        let window = try XCTUnwrap(toast.window)
        XCTAssertNil(SettingsToastLayout.obstructingTabBar(in: window))
        XCTAssertEqual(
            toast.frame.maxY,
            window.safeAreaLayoutGuide.layoutFrame.maxY - AppSpacing.sp6,
            accuracy: 0.5
        )
    }

    /// `hidesBottomBarWhenPushed` parks the bar below the window instead of
    /// hiding it. Anchoring to it there would drag the toast off screen too.
    func testTabBarParkedOffScreen_isNotTreatedAsAnObstacle() throws {
        let window = windowHostingATabBar(style: .light)
        let bar = try XCTUnwrap(SettingsToastLayout.obstructingTabBar(in: window))
        bar.frame.origin.y = window.bounds.maxY + 1
        XCTAssertNil(SettingsToastLayout.obstructingTabBar(in: window))
    }

    func testToastPill_carriesShadowAndBorder_soItDetachesFromLightContent() {
        let toast = hostedToast(style: .light)

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

    /// A toast hosted in a window under `style`, laid out, with no tab bar in
    /// the way.
    ///
    /// Hosting is not ceremony. The pill resolves its `cgColor`s at `init` and
    /// afterwards only from `registerForTraitChanges`, and UIKit delivers that
    /// callback down a real hierarchy — a detached label keeps whatever
    /// `UITraitCollection.current` happened to be when it was built, so both
    /// themes measure identical and broken code passes.
    private func hostedToast(style: UIUserInterfaceStyle) -> SettingsToastLabel {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        hostWindows.append(window)

        let toast = SettingsToastLabel()
        toast.text = "Скопировано"
        SettingsToastLayout.install(toast, in: window)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return toast
    }

    /// A window whose root is a three-tab controller — the shape Settings is
    /// pushed into. Plain `UIViewController`s stand in for the real screens:
    /// what is under test is the bar's geometry, not the tabs' content.
    private func windowHostingATabBar(style: UIUserInterfaceStyle) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = style
        let tabs = UITabBarController()
        tabs.viewControllers = [UIViewController(), UIViewController(), UIViewController()]
        window.rootViewController = tabs
        window.isHidden = false
        hostWindows.append(window)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return window
    }

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
