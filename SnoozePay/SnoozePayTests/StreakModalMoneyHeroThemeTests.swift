import UIKit
import XCTest
@testable import SnoozePay

/// The streak modal's money hero (`+350 ₽`) must be painted in the theme the
/// sheet is actually rendered in (#552).
///
/// ## The defect
///
/// `refreshLayerColors()` re-resolved the sheet border, the outer glow and the
/// flame badge's ramp — but never the hero's. `SPGradientTextLabel` hands its
/// stops to a `CAGradientLayer`, whose `CGColor`s are resolved once and never
/// follow a theme change, so the number kept whatever ramp was baked at
/// `configureLabels()` time. `configureLabels()` runs from `viewDidLoad`, where
/// the controller is not in a window yet and its `traitCollection` is the
/// **screen's** — the system theme, not the app's.
///
/// The consequence, from one screenshot in #552: the 96×96 flame tile painted
/// with the light ramp (`#096949`) while the glyphs one row below painted with
/// the dark one (`#12BB83`), on the same `#ECEEF6` sheet, in the same frame.
/// Measured on that sheet the dark ramp runs **1.54 / 2.19 / 4.61**:1 — the
/// sampled mid-ramp glyph was 2.14:1, under the 3:1 WCAG 1.4.3 large-text bar.
///
/// ## Why the obvious test would have been green on the broken code
///
/// Two traps, and both have been walked into in this repo before:
///
/// 1. **A synthetic host.** Building an `SPGradientTextLabel` by hand and
///    calling `setGradientColors` tests the primitive, which was never broken.
///    The bug was in the controller's refresh list, so these tests mount the
///    real `StreakModalViewController`.
/// 2. **A matching theme.** If the system theme and the app theme agree, the
///    bake is accidentally right and every assertion passes against the broken
///    code. So the fixtures deliberately bake under one style and present under
///    the other, and each direction is `XCTSkipUnless`-guarded on having
///    actually produced the mismatch — a harness that fails to reproduce it
///    skips loudly instead of passing quietly.
final class StreakModalMoneyHeroThemeTests: XCTestCase {

    /// WCAG 2.1 floor for large text. The hero is `moneyXl` — 56pt bold — so
    /// 3:1 is the applicable bar, and the broken ramp misses it in both
    /// directions (1.54:1 on the light sheet, 1.38:1 on the dark one).
    private let largeTextFloor: CGFloat = 3.0
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02
    private let sheetSize = CGSize(width: 393, height: 852)

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach {
            $0.isHidden = true
            $0.rootViewController = nil
        }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The defect: baked from the screen, never corrected

    /// System dark, app light — the exact combination #552 screenshotted.
    func testMoneyHero_bakedUnderSystemDark_repaintsForTheLightSheet() throws {
        try assertHeroFollowsTheApp(systemStyle: .dark, appStyle: .light)
    }

    /// The mirror image. Nothing about the mechanism is light-specific: a hero
    /// frozen in the light ramp on a dark sheet reads 1.38:1 at `money700`.
    func testMoneyHero_bakedUnderSystemLight_repaintsForTheDarkSheet() throws {
        try assertHeroFollowsTheApp(systemStyle: .light, appStyle: .dark)
    }

    private func assertHeroFollowsTheApp(
        systemStyle: UIUserInterfaceStyle,
        appStyle: UIUserInterfaceStyle
    ) throws {
        let hosted = try hostModal(systemStyle: systemStyle, appStyle: appStyle)

        // The whole point of the fixture. If the bake did not end up on the
        // wrong ramp, the defect is not on screen and asserting would be
        // vacuous — say so rather than report a pass.
        try XCTSkipUnless(
            hosted.bakedStops != ramp(appStyle),
            "harness did not reproduce a system/app mismatch: the hero baked "
            + "\(text(hosted.bakedStops)), which is already the \(appStyle.name) ramp"
        )
        try XCTSkipUnless(
            hosted.modal.amountLabel.traitCollection.userInterfaceStyle == appStyle,
            "window did not propagate overrideUserInterfaceStyle — a harness fact"
        )

        XCTAssertEqual(
            stops(of: hosted.modal.amountLabel), ramp(appStyle),
            "the hero is still painted in the \(systemStyle.name) ramp "
            + "(\(text(hosted.bakedStops))) on a \(appStyle.name) sheet — a CGColor in "
            + "CAGradientLayer.colors never re-resolves, and refreshLayerColors() "
            + "does not reach amountLabel"
        )
    }

    // MARK: - What the user sees

    /// The stops the hero actually paints with, measured against the sheet fill
    /// they land on. This is the number from the issue, not a proxy for it.
    func testMoneyHero_clearsTheLargeTextBarOnTheSheetBehindIt() throws {
        for (systemStyle, appStyle) in [
            (UIUserInterfaceStyle.dark, UIUserInterfaceStyle.light),
            (UIUserInterfaceStyle.light, UIUserInterfaceStyle.dark)
        ] {
            let hosted = try hostModal(systemStyle: systemStyle, appStyle: appStyle)
            let sheet = AppColors.bg2.resolved(appStyle)
            let painted = stops(of: hosted.modal.amountLabel)
            XCTAssertFalse(
                painted.isEmpty,
                "the hero painted no gradient at all under \(appStyle.name) — an empty "
                + "stop list would make every ratio below vacuously true"
            )
            for (index, stop) in painted.enumerated() {
                let ratio = contrast(color(stop), sheet)
                XCTAssertGreaterThanOrEqual(
                    ratio, largeTextFloor - tolerance,
                    "hero stop \(index) (#\(hexText(stop))) reads \(ratio.ratioText):1 on the "
                    + "\(appStyle.name) sheet — #552 sampled 2.14:1 there"
                )
            }
        }
    }

    /// The issue's headline evidence, turned into an assertion: the flame tile
    /// and the number sit in one sheet and must not be painted in two themes.
    ///
    /// Deliberately compares them to each other *and* to the design system's
    /// ramp — "they agree" alone would pass if both regressed together.
    func testMoneyHero_andFlameBadge_agreeOnOneRamp() throws {
        let hosted = try hostModal(systemStyle: .dark, appStyle: .light)
        let hero = stops(of: hosted.modal.amountLabel)
        let badge = badgeStops(of: hosted.modal.flameBadge)

        XCTAssertEqual(
            hero, badge,
            "the flame tile paints \(text(badge)) and the number \(text(hero)) on the "
            + "SAME sheet in the SAME frame — exactly the #552 screenshot"
        )
        XCTAssertEqual(hero, ramp(.light), "both agreed, on the wrong ramp")
    }

    // MARK: - Surviving a live theme flip

    /// The other half of the same root cause: the user changes the app theme
    /// while the sheet is up. Both directions, each skip-guarded, so a harness
    /// that silently fails to flip cannot assert the same theme twice.
    func testMoneyHero_followsALiveThemeFlip() throws {
        let hosted = try hostModal(systemStyle: .dark, appStyle: .dark)
        let label = hosted.modal.amountLabel
        let inDark = stops(of: label)
        try XCTSkipUnless(!inDark.isEmpty, "the hero installed no gradient stops at all")

        hosted.window.overrideUserInterfaceStyle = .light
        layOut(hosted)
        try XCTSkipUnless(
            label.traitCollection.userInterfaceStyle == .light,
            "window did not propagate the flip to light — a harness fact"
        )
        XCTAssertEqual(
            stops(of: label), ramp(.light),
            "the hero kept \(text(inDark)) after the flip to light"
        )

        hosted.window.overrideUserInterfaceStyle = .dark
        layOut(hosted)
        try XCTSkipUnless(
            label.traitCollection.userInterfaceStyle == .dark,
            "window did not propagate the flip back to dark — a harness fact"
        )
        XCTAssertEqual(
            stops(of: label), ramp(.dark),
            "the hero did not return to the dark ramp"
        )
    }

    // MARK: - The cost, pinned

    /// Records what the two ramps are worth on the light sheet, so the numbers
    /// quoted in #552 stay derivable instead of being folklore. Green on the
    /// broken code by design — it measures tokens, which were never at fault.
    func testMoneyRamps_onTheLightSheet_areTheNumbersQuotedInTheIssue() {
        let sheet = AppColors.bg2.resolved(.light)
        let expected: [(stop: UIColor, ratio: CGFloat, note: String)] = [
            (AppColors.money400.resolved(.dark), 1.54, "dark #2EDB9F — what shipped"),
            (AppColors.money500.resolved(.dark), 2.19, "dark #10B981 — what shipped"),
            (AppColors.money400.resolved(.light), 4.55, "light #0B7B56 — what it must be"),
            (AppColors.money500.resolved(.light), 6.04, "light #096647 — what it must be")
        ]
        for entry in expected {
            let ratio = contrast(entry.stop, sheet)
            XCTAssertEqual(
                ratio, entry.ratio, accuracy: tolerance,
                "\(entry.note) measures \(ratio.ratioText):1 on bg2 light — if this moved, "
                + "re-derive the numbers in #552 rather than deleting the pin"
            )
        }
    }

    // MARK: - Fixtures

    private struct Hosted {
        let modal: StreakModalViewController
        let window: UIWindow
        /// The ramp the hero was frozen with before it ever reached a window.
        let bakedStops: [UInt32]
    }

    /// Mount a real modal that was **built** under `systemStyle` and is
    /// **presented** under `appStyle`.
    ///
    /// The two steps are separated on purpose, because that separation is the
    /// bug. `present()` loads and lays out the sheet before it inherits the
    /// window's traits, so `viewDidLoad` sees the screen — the system theme.
    /// A controller-level override stands in for the screen here (a test
    /// process cannot change the device's appearance), and is cleared before
    /// the sheet reaches the window so the app theme, which `ThemeService`
    /// really does put on the WINDOW, is what wins from then on.
    private func hostModal(
        systemStyle: UIUserInterfaceStyle,
        appStyle: UIUserInterfaceStyle
    ) throws -> Hosted {
        let modal = StreakModalViewController(streakDays: 7, savedAmount: 350)
        modal.overrideUserInterfaceStyle = systemStyle
        modal.loadViewIfNeeded()
        // A detached layout pass, so the hero's mask (and with it the gradient
        // sublayer carrying the baked stops) exists to be measured.
        modal.view.frame = CGRect(origin: .zero, size: sheetSize)
        modal.view.setNeedsLayout()
        modal.view.layoutIfNeeded()
        let baked = stops(of: modal.amountLabel)

        modal.overrideUserInterfaceStyle = .unspecified
        let window = UIWindow(frame: CGRect(origin: .zero, size: sheetSize))
        window.overrideUserInterfaceStyle = appStyle
        window.isHidden = false
        window.rootViewController = modal
        hostWindows.append(window)

        let hosted = Hosted(modal: modal, window: window, bakedStops: baked)
        layOut(hosted)
        return hosted
    }

    /// Force a full layout pass down to the hero. The frame is set explicitly
    /// because a window that was never made key is not guaranteed to have sized
    /// its root view, and a zero-width label rasterises no mask at all.
    private func layOut(_ hosted: Hosted) {
        hosted.modal.view.frame = hosted.window.bounds
        hosted.window.setNeedsLayout()
        hosted.window.layoutIfNeeded()
        hosted.modal.view.setNeedsLayout()
        hosted.modal.view.layoutIfNeeded()
    }

    // MARK: - Reading the rendered hero

    /// The stops the hero's gradient layer is currently painting with.
    ///
    /// Read off the `CAGradientLayer` that `applyGradientMask` installs as a
    /// sublayer of the label — i.e. the layer that ends up on screen — rather
    /// than off any bookkeeping property.
    private func stops(of label: UILabel) -> [UInt32] {
        guard let gradient = (label.layer.sublayers ?? [])
            .compactMap({ $0 as? CAGradientLayer }).first else { return [] }
        var found: [UInt32] = []
        for case let color as CGColor in gradient.colors ?? [] {
            found.append(hex(UIColor(cgColor: color)))
        }
        return found
    }

    /// The flame tile IS a gradient layer (`SPGradientView.layerClass`), so it
    /// is read from the view's own layer, not from a sublayer.
    private func badgeStops(of badge: UIView) -> [UInt32] {
        guard let gradient = badge.layer as? CAGradientLayer else { return [] }
        var found: [UInt32] = []
        for case let color as CGColor in gradient.colors ?? [] {
            found.append(hex(UIColor(cgColor: color)))
        }
        return found
    }

    private func ramp(_ style: UIUserInterfaceStyle) -> [UInt32] {
        SPSupport.moneyGradientColors(for: UITraitCollection(userInterfaceStyle: style))
            .map { hex(UIColor(cgColor: $0)) }
    }

    private func text(_ stops: [UInt32]) -> String {
        "[" + stops.map { "#" + hexText($0) }.joined(separator: ", ") + "]"
    }

    private func hexText(_ value: UInt32) -> String { String(format: "%06X", value) }

    // MARK: - Colour maths

    private func hex(_ color: UIColor) -> UInt32 {
        let rgb = channels(color)
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(rgb.red) << 16) | (toByte(rgb.green) << 8) | toByte(rgb.blue)
    }

    private func color(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0)
        }
        return Channels(red: red, green: green, blue: blue)
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
