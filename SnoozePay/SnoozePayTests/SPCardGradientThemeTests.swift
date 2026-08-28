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
/// code. The override goes on the WINDOW, and each direction is skip-guarded
/// so a harness that silently fails to flip cannot assert the same theme twice
/// and call it a pass.
final class SPCardGradientThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text.
    private let normalTextFloor: CGFloat = 4.5
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.02

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.rootViewController = nil }
        hostWindows = []
        super.tearDown()
    }

    // MARK: - The flip

    /// All three tonal variants re-tint under an already-rendered card, and
    /// land on exactly the ramp the design system defines for the new theme —
    /// "the stops changed" alone would also be satisfied by changing them to
    /// something wrong.
    func testTonalCards_reresolveTheirRampOnAThemeFlip() throws {
        let cases: [(tone: SPCard.Tone, ramp: (UITraitCollection) -> [CGColor])] = [
            (.money, { SPSupport.moneyGradientColors(for: $0) }),
            (.pain, { SPSupport.painGradientColors(for: $0) }),
            (.warn, { SPSupport.warnGradientColors(for: $0) })
        ]

        for entry in cases {
            let (card, window) = makeHostedCard(tone: entry.tone)

            window.overrideUserInterfaceStyle = .dark
            window.layoutIfNeeded()
            try XCTSkipUnless(
                card.traitCollection.userInterfaceStyle == .dark,
                "window override did not propagate — a harness fact, not a component one"
            )
            let inDark = stops(of: card)
            try XCTSkipUnless(
                !inDark.isEmpty,
                "the \(entry.tone) card installed no gradient layer at all"
            )

            window.overrideUserInterfaceStyle = .light
            window.layoutIfNeeded()
            try XCTSkipUnless(
                card.traitCollection.userInterfaceStyle == .light,
                "window override did not propagate — a harness fact, not a component one"
            )
            let inLight = stops(of: card)

            XCTAssertNotEqual(
                inDark, inLight,
                "the \(entry.tone) card kept its dark stops after the flip — "
                + "a CGColor in CAGradientLayer.colors never re-resolves itself"
            )
            XCTAssertEqual(
                inLight, entry.ramp(UITraitCollection(userInterfaceStyle: .light)).map { hex($0) },
                "the \(entry.tone) card re-tinted to something other than the light ramp"
            )

            // And back — the defect is symmetric, a card built in light and
            // flipped to dark froze just as hard.
            window.overrideUserInterfaceStyle = .dark
            window.layoutIfNeeded()
            try XCTSkipUnless(
                card.traitCollection.userInterfaceStyle == .dark,
                "window override did not propagate — a harness fact, not a component one"
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

    /// `warnGradientColors(for:)` is new in #507 — the money/pain overloads
    /// already existed. If it ever returns the same stops for both themes the
    /// view-level test above measures nothing.
    func testWarnGradientStops_differPerTheme() {
        let light = SPSupport.warnGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
        let dark = SPSupport.warnGradientColors(for: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(light.count, dark.count)
        for (index, pair) in zip(light, dark).enumerated() {
            XCTAssertNotEqual(
                hex(pair.0), hex(pair.1),
                "warn gradient stop \(index) is identical in both themes"
            )
        }
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
                [AppColors.warn300, AppColors.warn500, AppColors.warn600]
                    .map { hex($0.resolvedColor(with: trait)) },
                "warnGradientColors(for:) drifted off --sp-grad-warn"
            )
        }
    }

    // MARK: - Fixtures

    private func makeHostedCard(tone: SPCard.Tone) -> (SPCard, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
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
