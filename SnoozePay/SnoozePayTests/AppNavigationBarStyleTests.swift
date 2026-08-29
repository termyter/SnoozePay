import UIKit
import XCTest
@testable import SnoozePay

/// Nav-bar chrome floor (#508).
///
/// Two things are pinned here, and the second is the one that matters.
///
/// 1. The bar reads as the page. `components.css` `.sp-navbar` is
///    `background: transparent` with no `border-bottom`, over a `--sp-bg-0`
///    screen — so the bar fill must BE `bg0` and the hairline must be gone.
///    The system default measured 1.08:1 against the page in light and 1.06:1
///    in dark: a visible edge with no design intent behind it.
/// 2. The bar keeps reading as the page **after a theme flip**. A
///    `UINavigationBarAppearance` is built once and kept; if the tokens were
///    snapshotted with `resolvedColor(with:)` (or `.cgColor`) before being
///    stored, the object would freeze one theme forever — the exact defect
///    fixed in five other places this week. Both flip tests host their subject
///    in a real `UIWindow`, because a detached bar never gets the trait-change
///    callback and would measure identical in both themes, passing against
///    broken code.
@MainActor
final class AppNavigationBarStyleTests: XCTestCase {

    /// Windows hosting the bars under test. Held for the lifetime of the test
    /// case: a released window takes its subtree's traits with it.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Canon

    func testAppearance_fillsWithTheBg0Token_inBothThemes() throws {
        let appearance = AppNavigationBarStyle.makeAppearance()
        let fill = try XCTUnwrap(
            appearance.backgroundColor,
            "the bar has no fill — it would fall back to system chrome"
        )
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                channels(fill.resolved(style)),
                channels(AppColors.bg0.resolved(style)),
                "bar fill is off `bg0` in \(style.debugName)"
            )
        }
    }

    /// `.sp-navbar` carries no `border-bottom` — unlike `.sp-tabbar`, which the
    /// same stylesheet deliberately gives a `border-top`. UIKit models the
    /// bar's bottom edge as its "shadow", and it is what stays visible as a
    /// hard line even once the fill matches the page.
    ///
    /// UIKit stores "no line" two ways and treats them as one: we assign
    /// `.clear`, and reading the property back yields `nil`. It normalises the
    /// explicit clear into nil, which it would not do if nil meant "draw the
    /// system default" — so both spellings are accepted here. What the bar
    /// actually renders is settled by `testRenderedBar_repaintsOnAThemeFlip`,
    /// which samples pixels instead of trusting the model.
    func testAppearance_hasNoBottomHairline() {
        let appearance = AppNavigationBarStyle.makeAppearance()
        if let shadow = appearance.shadowColor {
            XCTAssertEqual(
                channels(shadow.resolved(.light)),
                channels(UIColor.clear),
                "a hairline under the bar is exactly the seam #508 is about"
            )
        }
        XCTAssertNil(appearance.shadowImage)
    }

    /// The whole point: bar and page are the same colour, so the seam is 1.00:1
    /// — no edge at all, in either theme.
    func testBarFill_matchesThePage_inBothThemes() throws {
        let fill = try XCTUnwrap(AppNavigationBarStyle.makeAppearance().backgroundColor)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrastRatio(fill.resolved(style), AppColors.bg0.resolved(style))
            XCTAssertEqual(
                ratio, 1.0, accuracy: 0.001,
                "bar/page seam measures \(ratio.ratioText):1 in \(style.debugName)"
            )
        }
    }

    /// Documents what the default measured, so a future "simplification" back
    /// to system chrome can see the number it reintroduces.
    func testSystemDefaultChrome_wasASeam_againstThePage() {
        let light = contrastRatio(UIColor.systemBackground.resolved(.light), AppColors.bg0.resolved(.light))
        let dark = contrastRatio(UIColor.systemBackground.resolved(.dark), AppColors.bg0.resolved(.dark))
        XCTAssertGreaterThan(light, 1.0, "system light chrome used to differ from the page")
        XCTAssertGreaterThan(dark, 1.0, "system dark chrome used to differ from the page")
        XCTAssertLessThan(light, 1.15, "if this jumped, the palette moved and the doc comment needs revisiting")
        XCTAssertLessThan(dark, 1.15, "if this jumped, the palette moved and the doc comment needs revisiting")
    }

    func testTitleTokens_comeFromTheDesignSystem() throws {
        let appearance = AppNavigationBarStyle.makeAppearance()
        XCTAssertEqual(appearance.titleTextAttributes[.font] as? UIFont, AppTypography.h4)
        let ink = try XCTUnwrap(appearance.titleTextAttributes[.foregroundColor] as? UIColor)
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                channels(ink.resolved(style)),
                channels(AppColors.fg1.resolved(style)),
                "title ink is off `fg1` in \(style.debugName)"
            )
        }
        XCTAssertEqual(appearance.largeTitleTextAttributes[.font] as? UIFont, AppTypography.h1)
        let kerning = try XCTUnwrap(appearance.largeTitleTextAttributes[.kern] as? NSNumber)
        XCTAssertEqual(
            CGFloat(kerning.doubleValue), AppTypography.kern(em: -0.02, size: 32), accuracy: 0.0001,
            "`.sp-navbar__largeTitle` overrides `.sp-h1` tracking to -.02em"
        )
    }

    // MARK: - Installation

    /// Setting only `standardAppearance` leaves the bar system-white at rest,
    /// which is the state the seam was reported in.
    func testFactory_installsTheRecipeOnEveryAppearanceSlot() throws {
        let bar = AppNavigationBarStyle
            .makeNavigationController(rootViewController: UIViewController())
            .navigationBar
        let slots: [(String, UINavigationBarAppearance?)] = [
            ("standard", bar.standardAppearance),
            ("scrollEdge", bar.scrollEdgeAppearance),
            ("compact", bar.compactAppearance),
            ("compactScrollEdge", bar.compactScrollEdgeAppearance)
        ]
        for (name, slot) in slots {
            let fill = try XCTUnwrap(slot?.backgroundColor, "\(name) appearance is unset")
            XCTAssertEqual(
                channels(fill.resolved(.light)),
                channels(AppColors.bg0.resolved(.light)),
                "\(name) appearance is not on `bg0`"
            )
        }
    }

    /// Every navigation controller the tab bar builds goes through the factory.
    /// Wallet is the tab the reported screens (history, settings, referral) are
    /// pushed from, so an unstyled tab here reintroduces the whole issue.
    func testMainTabBar_stylesEveryTabsNavigationBar() throws {
        let tabBarController = try XCTUnwrap(SceneDelegate.makeMainTabBar() as? UITabBarController)
        let stacks = try XCTUnwrap(tabBarController.viewControllers)
            .compactMap { $0 as? UINavigationController }
        XCTAssertEqual(stacks.count, 3, "a tab stopped being a navigation stack")
        for stack in stacks {
            XCTAssertEqual(
                channels(stack.navigationBar.standardAppearance.backgroundColor?.resolved(.light)),
                channels(AppColors.bg0.resolved(.light)),
                "\(stack.tabBarItem.title ?? "?") tab kept the system bar"
            )
        }
    }

    /// The bar must FOLLOW the theme, never pin one. Six screens deliberately
    /// force themselves dark; a bar that hard-set its own style would fight
    /// them (and would fight `ThemeService` on every other screen).
    func testStyling_neverPinsAnInterfaceStyleOnTheBar() {
        let stack = AppNavigationBarStyle.makeNavigationController(rootViewController: UIViewController())
        XCTAssertEqual(stack.navigationBar.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(stack.overrideUserInterfaceStyle, .unspecified)
    }

    // MARK: - Theme flip

    /// The hazard this file exists for. `UINavigationBarAppearance` holds
    /// resolved colours; an object built once must still hand UIKit a *dynamic*
    /// `UIColor` so the bar re-resolves it against its own traits. Hosted in a
    /// window — a detached bar keeps its init-time traits and both themes
    /// measure identical, so without the window this passes against a
    /// snapshotted (broken) appearance.
    func testStoredFill_reresolvesAgainstTheBarsLiveTraits_onAThemeFlip() throws {
        let window = makeHostWindow()
        let stack = AppNavigationBarStyle.makeNavigationController(rootViewController: UIViewController())
        window.rootViewController = stack
        let bar = stack.navigationBar

        // The override goes on the CONTROLLER: an invisible, scene-less window
        // does not push a style change down through its `rootViewController`.
        stack.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        try XCTSkipUnless(
            bar.traitCollection.userInterfaceStyle == .dark,
            "controller override did not propagate — a harness fact, not a component one"
        )
        let inDark = channels(bar.standardAppearance.backgroundColor?.resolvedColor(with: bar.traitCollection))

        stack.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        try XCTSkipUnless(
            bar.traitCollection.userInterfaceStyle == .light,
            "controller override did not propagate — a harness fact, not a component one"
        )
        let inLight = channels(bar.standardAppearance.backgroundColor?.resolvedColor(with: bar.traitCollection))

        XCTAssertNotNil(inDark)
        XCTAssertNotEqual(
            inDark, inLight,
            "the appearance kept one theme's fill after the flip — a token was snapshotted before storing"
        )
        XCTAssertEqual(inDark, channels(AppColors.bg0.resolved(.dark)))
        XCTAssertEqual(inLight, channels(AppColors.bg0.resolved(.light)))
    }

    /// The stronger half of the same claim: not just "the stored colour is
    /// dynamic" but "UIKit actually repaints the bar with the other theme's
    /// value". Renders the bar's layer tree and samples a pixel. Skip-guarded
    /// on the render succeeding at all, so it can only fail by measuring two
    /// opaque, identical bars — i.e. by the appearance genuinely not tracking.
    func testRenderedBar_repaintsOnAThemeFlip() throws {
        let window = makeHostWindow()
        let stack = AppNavigationBarStyle.makeNavigationController(rootViewController: UIViewController())
        window.rootViewController = stack
        let bar = stack.navigationBar

        stack.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        let dark = renderCentrePixel(of: bar)
        try XCTSkipUnless((dark?.last ?? 0) > 200, "bar background did not render offscreen — a harness fact")

        stack.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        let light = renderCentrePixel(of: bar)
        try XCTSkipUnless((light?.last ?? 0) > 200, "bar background did not render offscreen — a harness fact")

        XCTAssertNotEqual(
            dark, light,
            "the bar rendered the same pixels in both themes — the appearance is not re-resolving"
        )
        // Light `bg0` is #F4F6FB, dark is #060912. Only the direction is
        // asserted, so a palette tweak doesn't false-fail this test.
        XCTAssertGreaterThan(
            light?.first ?? 0, dark?.first ?? 0,
            "the light bar must be the brighter of the two"
        )
    }

    // MARK: - Helpers

    private func makeHostWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        hostWindows.append(window)
        return window
    }

    /// Render `view`'s layer tree into a 1×1 bitmap positioned over the view's
    /// centre. Returns nil when the view has no drawable area.
    private func renderCentrePixel(of view: UIView) -> [UInt8]? {
        let size = view.bounds.size
        guard size.width > 2, size.height > 2 else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: -size.width / 2, y: -size.height / 2)
            view.layer.render(in: context)
            return true
        }
        return rendered ? pixel : nil
    }

    /// RGBA as a comparable array — tuples aren't `Equatable`, and rounding
    /// keeps float noise out of the comparison.
    private func channels(_ color: UIColor?) -> [CGFloat]? {
        guard let color = color else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return [red, green, blue, alpha].map { ($0 * 10_000).rounded() / 10_000 }
    }

    private func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let lighter = max(luminance(lhs), luminance(rhs))
        let darker = min(luminance(lhs), luminance(rhs))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String {
        self == .light ? "light" : "dark"
    }
}

private extension CGFloat {
    var ratioText: String { String(format: "%.2f", self) }
}
