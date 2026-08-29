import UIKit
import XCTest
@testable import SnoozePay

/// `.raised` must read as *higher* than `.surface` — in both themes (#543).
///
/// ## Why this measures a pair and not two hex values
///
/// Pinning "`.raised` is `#ECEEF6` in light" would have been green on the
/// defect: `#ECEEF6` is exactly what the broken code produced. The bug is not
/// in either fill on its own, it is in their **order**. `.sp-card--raised`
/// swaps the fill to `bg2`, which is a step *up* the ramp in dark
/// (`#161C2E` over a `#060912` page) and a step *down* in light (`#ECEEF6`
/// under a `#F4F6FB` page). Same token, opposite meaning — so on the alarms
/// list, where the tone pair encodes on/off, the switched-OFF alarm became the
/// brightest card on the screen.
///
/// ## The metric
///
/// Elevation is scored on two independent axes, both read off the rendered
/// view rather than off a table of constants:
///
/// 1. **Fill lift** = `luminance(fill) − luminance(bg0)`. Signed, and the sign
///    is theme-neutral: `bg1` is lighter than `bg0` in *both* themes
///    (`#0E1320` > `#060912`, `#FFFFFF` > `#F4F6FB`), so "further from the
///    page in the direction the card ramp starts" means "above the page" in
///    both. A negative lift is a recessed surface — which is precisely what
///    light-mode `bg2` is.
/// 2. **Shadow strength** = `opacity × (|offsetY| + radius)`. A single scalar
///    ordering `--sp-shadow-1` below `--sp-shadow-2` in either theme
///    (light 1.08 vs 2.60, dark 3.50 vs 14.40) without hardcoding a recipe.
///
/// The contract: `.raised` may not lose on either axis, and must win on at
/// least one. Dark wins on fill (the ramp step) and ties on shadow; light ties
/// on fill (both cards are white) and wins on shadow. Neither theme is told
/// *which* axis to win on — that is the point, since the design canon spends
/// a different one in each.
///
/// ## The window is load-bearing
///
/// A detached view never receives the trait-change callback, keeps whatever it
/// resolved at `init`, and both themes then measure identical — i.e. the test
/// would pass against the broken code. The override goes on the WINDOW, and
/// every direction is `XCTSkipUnless`-guarded so a harness that silently fails
/// to flip cannot assert the same theme twice and call it a pass.
final class SPCardElevationOrderTests: XCTestCase {

    /// Absorbs sRGB rounding on the luminance scale only. The smallest real
    /// gap this test has to see is the dark `bg1`→`bg2` step, ≈0.005.
    private let tolerance: CGFloat = 1e-4

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach {
            $0.rootViewController = nil
            $0.isHidden = true
        }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The pair

    func testRaisedCard_readsHigherThanSurface_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            // The windows stay alive through `hostWindows`; a released window
            // takes the trait override down with it.
            let (surface, _) = makeHostedCard(tone: .surface, style: style)
            let (raised, _) = makeHostedCard(tone: .raised, style: style)
            try requireStyle(style, surface, raised)

            assertReadsHigher(
                raised, than: surface,
                style: style,
                what: "SPCard(tone: .raised) against SPCard(tone: .surface)"
            )
        }
    }

    /// Same guarantee on ONE instance carried across a live flip, because the
    /// fill is a dynamic `UIColor` (auto-resolving) while the border and the
    /// shadow are CALayer `cgColor` state (frozen at install). A card that only
    /// gets the pair right at `init` still inverts the moment the user changes
    /// theme with the list on screen.
    func testTheOrderSurvivesALiveThemeFlip() throws {
        let (surface, surfaceWindow) = makeHostedCard(tone: .surface, style: .dark)
        let (raised, raisedWindow) = makeHostedCard(tone: .raised, style: .dark)
        try requireStyle(.dark, surface, raised)
        assertReadsHigher(raised, than: surface, style: .dark, what: "the freshly built dark pair")

        for window in [surfaceWindow, raisedWindow] {
            window.overrideUserInterfaceStyle = .light
            window.layoutIfNeeded()
        }
        try requireStyle(.light, surface, raised)
        assertReadsHigher(raised, than: surface, style: .light, what: "the pair after dark → light")

        for window in [surfaceWindow, raisedWindow] {
            window.overrideUserInterfaceStyle = .dark
            window.layoutIfNeeded()
        }
        try requireStyle(.dark, surface, raised)
        assertReadsHigher(raised, than: surface, style: .dark, what: "the pair after light → dark")
    }

    // MARK: - The screen the defect was found on

    /// `AlarmCell` keeps its own copy of the recipe (the tone flips per row,
    /// and `SPCard`'s tone is immutable at `init`), so the design-system fix
    /// does not reach it automatically. This is the assertion that actually
    /// describes the reported symptom: an ENABLED alarm must read higher than
    /// a disabled one.
    func testEnabledAlarmRow_readsHigherThanADisabledOne_inBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let (enabledCard, _) = makeHostedAlarmCard(enabled: true, style: style)
            let (disabledCard, _) = makeHostedAlarmCard(enabled: false, style: style)
            try requireStyle(style, enabledCard, disabledCard)

            assertReadsHigher(
                enabledCard, than: disabledCard,
                style: style,
                what: "an enabled alarm row against a disabled one"
            )
        }
    }

    // MARK: - Why the token exists

    /// The measurement that makes the defect concrete rather than theoretical,
    /// and the reason `AppColors.bgRaised` is not simply an alias of `bg2`.
    ///
    /// Against its own page, `bg2` lifts in dark and *sinks* in light. Anything
    /// that maps "raised" onto it unconditionally is therefore correct in
    /// exactly one theme of two.
    func testTheRawBg2Step_liftsInDarkAndSinksInLight() {
        let darkLift = fillLift(AppColors.bg2, style: .dark)
        XCTAssertGreaterThan(
            darkLift, tolerance,
            "dark bg2 (#161C2E) is supposed to sit above the #060912 page"
        )

        let lightLift = fillLift(AppColors.bg2, style: .light)
        XCTAssertLessThan(
            lightLift, -tolerance,
            "light bg2 (#ECEEF6) measures \(lightLift.liftText) against the #F4F6FB page — "
            + "if this ever goes positive the whole premise of #543 is gone"
        )

        XCTAssertGreaterThan(
            fillLift(AppColors.bg1, style: .light), tolerance,
            "light bg1 (#FFFFFF) is the raised surface; bg2 is the recessed one"
        )
    }

    /// Dark is the canon and this issue changed light only: `bgRaised` must
    /// still resolve to the exact `bg2` ramp step there.
    func testRaisedFill_leavesTheDarkRampExactlyWhereItWas() {
        XCTAssertEqual(
            hex(AppColors.bgRaised.resolved(.dark)), hex(AppColors.bg2.resolved(.dark)),
            "the dark raised fill drifted off bg2"
        )
        XCTAssertEqual(
            hex(AppColors.bgRaised.resolved(.light)), hex(AppColors.bg1.resolved(.light)),
            "the light raised fill has to be the white card, not the recessed bg2 tone"
        )
    }

    /// The light card is white on a near-white page — 1.03:1 of separation.
    /// Once the fill stops carrying the step, the hairline is the only thing
    /// left drawing the card's edge, so it is not optional there.
    func testLightRaisedCard_keepsItsHairline_darkStaysBorderless() throws {
        let (light, _) = makeHostedCard(tone: .raised, style: .light)
        try requireStyle(.light, light)
        XCTAssertGreaterThan(
            light.layer.borderWidth, 0,
            "a #FFFFFF card on a #F4F6FB page needs a stroke — a shadow alone does not carry it"
        )
        XCTAssertFalse(light.layer.masksToBounds, "a clipped layer renders no shadow at all")

        let (dark, _) = makeHostedCard(tone: .raised, style: .dark)
        try requireStyle(.dark, dark)
        XCTAssertEqual(dark.layer.borderWidth, 0, "dark keeps the borderless card")
    }

    // MARK: - Assertions

    /// The contract: no loss on either axis, a win on at least one.
    private func assertReadsHigher(
        _ higher: UIView,
        than lower: UIView,
        style: UIUserInterfaceStyle,
        what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let higherLift = fillLift(of: higher)
        let lowerLift = fillLift(of: lower)
        let higherShadow = shadowStrength(of: higher)
        let lowerShadow = shadowStrength(of: lower)

        XCTAssertGreaterThanOrEqual(
            higherLift, lowerLift - tolerance,
            "\(what) sits BELOW it on the \(style.name) page: "
            + "\(higherLift.liftText) vs \(lowerLift.liftText) of lift off bg0",
            file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(
            higherShadow, lowerShadow - tolerance,
            "\(what) casts the weaker shadow in \(style.name): "
            + "\(higherShadow.liftText) vs \(lowerShadow.liftText)",
            file: file, line: line
        )
        XCTAssertTrue(
            higherLift > lowerLift + tolerance || higherShadow > lowerShadow + tolerance,
            "\(what) is indistinguishable in \(style.name) — equal fill lift "
            + "(\(higherLift.liftText)) AND equal shadow (\(higherShadow.liftText)). "
            + "Elevation has to be spent on one axis or the other.",
            file: file, line: line
        )
    }

    /// Each theme direction is skip-guarded: a harness that silently fails to
    /// propagate the override would otherwise measure one theme twice.
    private func requireStyle(
        _ style: UIUserInterfaceStyle,
        _ views: UIView...
    ) throws {
        for view in views {
            try XCTSkipUnless(
                view.traitCollection.userInterfaceStyle == style,
                "window override did not propagate — a harness fact, not a component one"
            )
        }
    }

    // MARK: - The metric

    /// `luminance(fill) − luminance(bg0)`, resolved against the view's OWN
    /// traits. Positive = the surface sits above the page.
    private func fillLift(of view: UIView) -> CGFloat {
        guard let fill = view.backgroundColor else {
            XCTFail("view paints no fill: \(view)")
            return 0
        }
        let trait = view.traitCollection
        return luminance(fill.resolvedColor(with: trait))
            - luminance(AppColors.bg0.resolvedColor(with: trait))
    }

    private func fillLift(_ color: UIColor, style: UIUserInterfaceStyle) -> CGFloat {
        luminance(color.resolved(style)) - luminance(AppColors.bg0.resolved(style))
    }

    /// One scalar that orders shadow recipes without pinning any of them:
    /// `opacity × (|offsetY| + radius)`. The ambient sublayer that light-mode
    /// `shadow-1` adds is folded in for the same reason — it is part of what
    /// the surface casts.
    private func shadowStrength(of view: UIView) -> CGFloat {
        strength(of: view.layer)
            + (view.layer.sublayers ?? [])
                .filter { $0.name == AppShadow.ambientShadow1LayerName }
                .reduce(0) { $0 + strength(of: $1) }
    }

    private func strength(of layer: CALayer) -> CGFloat {
        CGFloat(layer.shadowOpacity) * (abs(layer.shadowOffset.height) + layer.shadowRadius)
    }

    // MARK: - Fixtures

    private func makeHostedCard(
        tone: SPCard.Tone,
        style: UIUserInterfaceStyle
    ) -> (SPCard, UIWindow) {
        let card = SPCard(tone: tone)
        let window = makeWindow(style: style, hosting: card)
        return (card, window)
    }

    /// The alarm row's card surface — `AlarmCell` applies the chrome to a
    /// private `cardView`, so reach it the way the screen renders it: the only
    /// `AppRadius.lg`-rounded child of `contentView`.
    private func makeHostedAlarmCard(
        enabled: Bool,
        style: UIUserInterfaceStyle
    ) -> (UIView, UIWindow) {
        let cell = AlarmCell(style: .default, reuseIdentifier: AlarmCell.reuseID)
        let window = makeWindow(style: style, hosting: cell)
        cell.configure(
            time: "07:00",
            daysCaps: "БУДНИ · ПН–ПТ",
            priceText: "50 ₽",
            multiplier: "×2",
            soundName: "Soft Dawn",
            enabled: enabled
        )
        window.layoutIfNeeded()
        let card = cell.contentView.subviews.first { $0.layer.cornerRadius == AppRadius.lg }
        guard let card else {
            XCTFail("alarm row has no card surface — the cell's layout changed")
            return (cell, window)
        }
        return (card, window)
    }

    /// Host `view` in a real window and set the style on the WINDOW — an
    /// `overrideUserInterfaceStyle` on a detached view does not deliver the
    /// trait-change callbacks the card refreshes its layers from.
    private func makeWindow(style: UIUserInterfaceStyle, hosting view: UIView) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = style
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        view.frame = CGRect(x: 0, y: 0, width: 353, height: 140)
        host.view.addSubview(view)
        window.layoutIfNeeded()
        hostWindows.append(window)
        return window
    }

    // MARK: - Colour maths

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
    /// Four decimals — the dark ramp steps live in the third one, and a
    /// failure message should carry the measurement rather than a shrug.
    var liftText: String { String(format: "%.4f", self) }
}
