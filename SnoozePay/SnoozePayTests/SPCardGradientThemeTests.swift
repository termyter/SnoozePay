import UIKit
import XCTest
@testable import SnoozePay

/// `SPCard` tonal fills must survive a theme flip (#507).
///
/// `CAGradientLayer.colors` is an array of plain `CGColor`. A `CGColor` has no
/// link back to the dynamic `UIColor` it was resolved from, so a ramp painted
/// at `init` stays frozen for the life of the layer while every label on top
/// of it re-resolves. That asymmetry is the bug: the fill keeps one theme, the
/// ink switches to the other.
///
/// **The window is load-bearing.** A detached view never receives the
/// trait-change callback, keeps whatever it resolved at `init`, and both
/// themes measure identical — i.e. the test would pass against the broken
/// code. The override goes on the WINDOW — and the window is UNHIDDEN, which
/// it was not until #568: a window that is never shown propagates its override
/// to nobody, so the guard fired and the flip case below reported `skipped` on
/// every single run. #507 was pinned by nothing.
///
/// **No `XCTSkip` in this file, on purpose.** A skip that fires every run is
/// indistinguishable from a test nobody wrote. The harness guards are
/// `XCTFail`.
final class SPCardGradientThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text.
    private let normalTextFloor: CGFloat = 4.5
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach {
            $0.isHidden = true
            $0.rootViewController = nil
        }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The flip

    /// All three tonal variants land on exactly the ramp the design system
    /// defines for the current theme, before and after a flip — "the stops
    /// changed" alone would also be satisfied by changing them to something
    /// wrong, and is checked separately for the ramps that do change.
    ///
    /// `.warn` carries `variesPerTheme: false` since #520: the warn FILL ramp
    /// is the canon amber in both themes, so this card genuinely has nothing to
    /// re-resolve. That is a narrower guarantee than the money/pain cards get,
    /// and the honest place to say so is here rather than in an assertion that
    /// would have to be weakened to stay green.
    func testTonalCards_reresolveTheirRampOnAThemeFlip() throws {
        let cases: [(tone: SPCard.Tone, ramp: (UITraitCollection) -> [CGColor], variesPerTheme: Bool)] = [
            (.money, { SPSupport.moneyGradientColors(for: $0) }, true),
            (.pain, { SPSupport.painGradientColors(for: $0) }, true),
            (.warn, { SPSupport.warnGradientColors(for: $0) }, false)
        ]

        for entry in cases {
            let (card, window) = makeHostedCard(tone: entry.tone)

            window.overrideUserInterfaceStyle = .dark
            window.layoutIfNeeded()
            XCTAssertEqual(
                card.traitCollection.userInterfaceStyle, .dark,
                "the harness stopped propagating dark — fix the harness, do not skip"
            )
            let inDark = stops(of: card)
            XCTAssertFalse(
                inDark.isEmpty,
                "the \(entry.tone) card installed no gradient layer at all"
            )
            XCTAssertEqual(
                inDark, entry.ramp(UITraitCollection(userInterfaceStyle: .dark)).map { hex($0) },
                "the \(entry.tone) card built itself off something other than the dark ramp"
            )

            window.overrideUserInterfaceStyle = .light
            window.layoutIfNeeded()
            XCTAssertEqual(
                card.traitCollection.userInterfaceStyle, .light,
                "the harness stopped propagating the flip to light — fix the harness, do not skip"
            )
            let inLight = stops(of: card)

            if entry.variesPerTheme {
                XCTAssertNotEqual(
                    inDark, inLight,
                    "the \(entry.tone) card kept its dark stops after the flip — "
                    + "a CGColor in CAGradientLayer.colors never re-resolves itself"
                )
            }
            XCTAssertEqual(
                inLight, entry.ramp(UITraitCollection(userInterfaceStyle: .light)).map { hex($0) },
                "the \(entry.tone) card re-tinted to something other than the light ramp"
            )

            // And back — the defect is symmetric, a card built in light and
            // flipped to dark froze just as hard.
            window.overrideUserInterfaceStyle = .dark
            window.layoutIfNeeded()
            XCTAssertEqual(
                card.traitCollection.userInterfaceStyle, .dark,
                "the harness stopped propagating the flip back to dark — fix the harness, "
                + "do not skip"
            )
            XCTAssertEqual(
                stops(of: card), inDark,
                "the \(entry.tone) card did not return to the dark ramp"
            )
        }
    }

    /// Non-tonal tones own no gradient layer — the fix must not have grown one
    /// for them (the layer tree stays shallow for the 30+ `.surface` cards).
    func testNonTonalCards_ownNoGradientLayer() {
        for tone in [SPCard.Tone.surface, .raised, .outline] {
            let (card, _) = makeHostedCard(tone: tone)
            XCTAssertNil(card.gradientLayer, "\(tone) card grew a gradient layer")
        }
    }

    // MARK: - What the freeze costs

    /// The measurement that makes the defect concrete rather than theoretical.
    ///
    /// Launch in dark, flip to light: the fill stays on the dark money ramp
    /// while `fgOnMoney` re-resolves from dark mint ink to white. White on the
    /// frozen dark `money400` (`#2EDB9F`) is **1.79:1** — comparable to the
    /// 1.9:1 measured on the wallet chart in #494. On the ramp the card is
    /// supposed to show after the flip (light `money400`, `#0B7B56`) the same
    /// ink clears the body-text bar.
    func testFrozenDarkMoneyRamp_sinksLightInkBelowTheTextBar() throws {
        let lightInk = AppColors.fgOnMoney.resolved(.light)

        let frozen = UIColor(cgColor: try XCTUnwrap(
            SPSupport.moneyGradientColors(for: UITraitCollection(userInterfaceStyle: .dark)).first
        ))
        let frozenRatio = contrast(lightInk, frozen)
        XCTAssertEqual(
            frozenRatio, 1.79, accuracy: tolerance,
            "the frozen dark money400 measures \(frozenRatio.ratioText):1 under light ink — "
            + "if this moved, re-derive the number quoted in #507 rather than deleting the pin"
        )

        let correct = UIColor(cgColor: try XCTUnwrap(
            SPSupport.moneyGradientColors(for: UITraitCollection(userInterfaceStyle: .light)).first
        ))
        let correctRatio = contrast(lightInk, correct)
        XCTAssertGreaterThanOrEqual(
            correctRatio, normalTextFloor - tolerance,
            "the light money ramp reads \(correctRatio.ratioText):1 under fgOnMoney — "
            + "re-resolving the fill is only worth it if the light ramp is legible"
        )
    }

    // MARK: - The seam

    /// The inverse of what this test asserted before #520.
    ///
    /// It used to require that the warn stops differ per theme, which was true
    /// while the ramp ran on the bronze ink scale. `tokens.css` never overrides
    /// the warn scale inside `[data-theme="light"]`, so the canon ramp is the
    /// same amber in both themes and the light stops are now *supposed* to
    /// equal the dark ones. Pinned to the literal CSS values rather than to
    /// "they match", because a pair that is wrong in both themes would also
    /// match.
    func testWarnGradientStops_areTheCanonAmberInBothThemes() {
        let canon: [UInt32] = [0xFFD479, 0xF59E0B, 0xC97A06]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ramp = SPSupport.warnGradientColors(for: UITraitCollection(userInterfaceStyle: style))
                .map { hex($0) }
            XCTAssertEqual(
                ramp, canon,
                "the warn ramp drifted off --sp-grad-warn in "
                + "\(style == .light ? "light" : "dark")"
            )
        }
    }

    /// The two warn ramps must NOT collapse into each other.
    ///
    /// They look like duplicates — same three steps, same locations — and the
    /// obvious cleanup is to delete one. That cleanup is the #520 regression
    /// replayed: `warnGradientColors` is a CTA surface solved against the
    /// `fgOnWarn` sitting on it, `warnInkGradientColors` is a data fill solved
    /// against the card behind it. In light they are bronze and amber and only
    /// one of them can be right for a given call site.
    func testWarnRamps_stayDistinctInLight() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let fill = SPSupport.warnGradientColors(for: light).map { hex($0) }
        var ink: [UInt32] = []
        light.performAsCurrent { ink = SPSupport.warnInkGradientColors.map { hex($0) } }
        XCTAssertNotEqual(
            fill, ink,
            "the warn fill and ink ramps resolved identically in light — one of "
            + "them lost its role, and the heatmap or the CTA is now wrong"
        )
        XCTAssertEqual(ink, [0xBE7B09, 0x7C5006, 0x634004], "the ink ramp drifted off the warn ink scale")
    }

    /// In DARK the two ramps are *supposed* to be identical: the ink and fill
    /// halves of the warn role only diverge on a light surface. Pinned so the
    /// test above is not read as "these must always differ".
    func testWarnRamps_areIdenticalInDark() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let fill = SPSupport.warnGradientColors(for: dark).map { hex($0) }
        var ink: [UInt32] = []
        dark.performAsCurrent { ink = SPSupport.warnInkGradientColors.map { hex($0) } }
        XCTAssertEqual(fill, ink, "the warn ramps diverged in dark, where both are the brand amber")
    }

    /// The new overload must describe the SAME ramp as the canon
    /// `--sp-grad-warn` scale its computed-property twin uses — otherwise
    /// switching a call site from one to the other silently re-skins the
    /// component instead of only fixing when it resolves.
    func testWarnOverload_staysOnTheCanonWarnScale() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let trait = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(
                SPSupport.warnGradientColors(for: trait).map { hex($0) },
                [AppColors.warnFill300, AppColors.warnFill500, AppColors.warnFill600]
                    .map { hex($0.resolvedColor(with: trait)) },
                "warnGradientColors(for:) drifted off --sp-grad-warn"
            )
        }
    }

    // MARK: - Fixtures

    /// A card in a window that actually propagates its theme.
    ///
    /// `isHidden = false` is the whole fix for #568 here: a window that is never
    /// unhidden hands its `overrideUserInterfaceStyle` to nobody, so the guard in
    /// the flip case fired on every run and the case never executed.
    private func makeHostedCard(tone: SPCard.Tone) -> (SPCard, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.isHidden = false
        let host = UIViewController()
        let card = SPCard(tone: tone)
        card.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        host.view.addSubview(card)
        window.rootViewController = host
        hostWindows.append(window)
        return (card, window)
    }

    /// The stops the card actually renders, flattened to hex so two snapshots
    /// compare across a flip.
    private func stops(of card: SPCard) -> [UInt32] {
        var found: [UInt32] = []
        for case let color as CGColor in card.gradientLayer?.colors ?? [] {
            found.append(hex(color))
        }
        return found
    }

    // MARK: - Colour maths

    private func hex(_ color: CGColor) -> UInt32 {
        hex(UIColor(cgColor: color))
    }

    private func hex(_ color: UIColor) -> UInt32 {
        let rgb = channels(color)
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(rgb.red) << 16) | (toByte(rgb.green) << 8) | toByte(rgb.blue)
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
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension CGFloat {
    /// Two decimals — a failure message should carry the measurement.
    var ratioText: String { String(format: "%.2f", self) }
}
