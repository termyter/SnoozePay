import UIKit
import XCTest
@testable import SnoozePay

/// `AlarmsStreakBannerView` had to survive a theme flip, and had to have an
/// edge at all (#531).
///
/// Two defects, one file. The gradient stops were plain `CGColor`s resolved
/// once in a property initializer — a `CGColor` has no link back to the
/// dynamic `UIColor` it came from, so the fill stayed on the launch theme
/// forever. `registerForTraitChanges` was already installed but repainted
/// only `borderColor`, which is why the file read as correct at a glance and
/// why a test asserting only the border would have passed against the bug.
/// Every flip assertion below therefore names the FILL first.
///
/// **The window is load-bearing.** A detached view never receives the
/// trait-change callback, keeps whatever it resolved at `init`, and both
/// themes measure identical — i.e. the test would pass against the broken
/// code. The override goes on the WINDOW.
///
/// **And the window has to be unhidden (#568).** It was not, and a window that
/// is never unhidden does not propagate its override: the guard in `flip` fired
/// on every run, so all four flip cases below reported `skipped` on every run
/// since the file was written. #531 was pinned by nothing. `isHidden = false`
/// is the whole difference — the same one measured in #565.
///
/// **No `XCTSkip` in this file, on purpose.** A guard that skips is a guard
/// that hides; a skip firing on every run is indistinguishable from a test
/// nobody wrote. The harness guards are `XCTFail`, so a harness that stops
/// propagating the flip fails loudly instead.
final class AlarmsStreakBannerThemeTests: XCTestCase {

    /// WCAG 2.1 non-text contrast floor (1.4.11).
    private let nonTextFloor: CGFloat = 3.0
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

    /// The assertion the bug actually needed: the FILL re-resolves under an
    /// already-rendered banner, and lands on the ramp the design system
    /// defines for the new theme — "the stops changed" alone would also be
    /// satisfied by changing them to something wrong.
    func testFill_reresolvesUnderAnAlreadyRenderedBanner() throws {
        let (banner, window) = makeHostedBanner()

        flip(window, to: .dark, banner)
        let inDark = banner.renderedFillStops.map { hex($0) }
        XCTAssertFalse(inDark.isEmpty, "the banner installed no fill gradient at all")

        flip(window, to: .light, banner)
        let inLight = banner.renderedFillStops.map { hex($0) }

        XCTAssertNotEqual(
            inDark, inLight,
            "the banner kept its dark fill after the flip — a CGColor in "
            + "CAGradientLayer.colors never re-resolves itself"
        )
        XCTAssertEqual(
            inLight,
            AlarmsStreakBannerView.fillColors(for: UITraitCollection(userInterfaceStyle: .light))
                .map { hex($0) },
            "the banner re-tinted to something other than the light money wash"
        )

        // And back — the defect is symmetric: a banner built in light and
        // flipped to dark froze just as hard.
        flip(window, to: .dark, banner)
        XCTAssertEqual(
            banner.renderedFillStops.map { hex($0) }, inDark,
            "the banner did not return to the dark fill"
        )
    }

    /// The 36×36 flame tile took the plain `SPSupport.moneyGradientColors`
    /// property, which snapshots `UITraitCollection.current`. Same freeze,
    /// second layer.
    func testIconTile_reresolvesItsMoneyRampOnAFlip() throws {
        let (banner, window) = makeHostedBanner()

        flip(window, to: .dark, banner)
        let inDark = banner.renderedIconStops.map { hex($0) }
        XCTAssertFalse(inDark.isEmpty, "the banner installed no icon gradient at all")

        flip(window, to: .light, banner)
        XCTAssertNotEqual(inDark, banner.renderedIconStops.map { hex($0) })
        XCTAssertEqual(
            banner.renderedIconStops.map { hex($0) },
            SPSupport.moneyGradientColors(for: UITraitCollection(userInterfaceStyle: .light))
                .map { hex($0) },
            "the flame tile drifted off --sp-grad-money for the light theme"
        )
    }

    /// The border was the ONE thing the old handler repainted. It still has
    /// to work after the rewrite — and now it is the banner's only edge, so
    /// it matters more than it did.
    func testBorder_reresolvesOnAFlip() throws {
        let (banner, window) = makeHostedBanner()

        flip(window, to: .dark, banner)
        let inDark = try XCTUnwrap(banner.renderedBorderColor)

        flip(window, to: .light, banner)
        let inLight = try XCTUnwrap(banner.renderedBorderColor)

        XCTAssertNotEqual(hex(inDark), hex(inLight), "the border kept its dark value")
        XCTAssertEqual(
            hex(inLight),
            hex(AlarmsStreakBannerView
                .borderColor(for: UITraitCollection(userInterfaceStyle: .light)).cgColor)
        )
    }

    /// `attributedText` snapshots its resolved colour exactly like `CGColor`
    /// does, so the caps title froze on the same flip.
    func testCapsTitle_reresolvesOnAFlip() throws {
        let (banner, window) = makeHostedBanner()
        banner.configure(streakDays: 5, savedAmount: 250)

        flip(window, to: .dark, banner)
        let inDark = try XCTUnwrap(capsColor(of: banner))

        flip(window, to: .light, banner)
        let inLight = try XCTUnwrap(capsColor(of: banner))

        XCTAssertNotEqual(
            hex(inDark), hex(inLight),
            "the caps title kept the dark money300 after the flip"
        )
    }

    // MARK: - The edge

    /// The recorded decision, measured rather than commented.
    ///
    /// The tint is a decorative wash and stays one: against the page (`bg0`)
    /// the dense stop measures ~1.20:1 dark / ~1.17:1 light and the sparse
    /// stop ~1.05:1 in both. Stepping the surface "one darker" is not on the
    /// table either — the whole `bg0…bg4` ramp measures 1.07–1.61:1 against
    /// the page (#518). So the banner deliberately has no surface of its own,
    /// and the border alone carries the edge.
    ///
    /// If these move, re-derive the numbers quoted in #531 and in the view's
    /// header rather than deleting the pin.
    func testSurface_staysADecorativeWashAgainstThePage() {
        let expected: [WashMeasurement] = [
            WashMeasurement(style: .dark, dense: 1.20, sparse: 1.05),
            WashMeasurement(style: .light, dense: 1.17, sparse: 1.05)
        ]
        for entry in expected {
            let trait = UITraitCollection(userInterfaceStyle: entry.style)
            let page = AppColors.bg0.resolvedColor(with: trait)
            let stops = AlarmsStreakBannerView.fillColors(for: trait).map { UIColor(cgColor: $0) }
            XCTAssertEqual(stops.count, 2, "the wash is a two-stop recipe")

            XCTAssertEqual(
                contrast(composite(stops[0], over: page), page), entry.dense, accuracy: tolerance,
                "\(entry.style) dense fill stop moved off its recorded measurement"
            )
            XCTAssertEqual(
                contrast(composite(stops[1], over: page), page), entry.sparse, accuracy: tolerance,
                "\(entry.style) sparse fill stop moved off its recorded measurement"
            )
        }
    }

    private struct WashMeasurement {
        let style: UIUserInterfaceStyle
        let dense: CGFloat
        let sparse: CGFloat
    }

    /// Because the border is the ONLY edge, it has to be one. At the canon
    /// `money400@18%` it measured 1.38:1 dark / 1.28:1 light against the page
    /// — a 1pt line at that ratio is not an edge, and that is the half of
    /// #531 the frozen gradient was hiding.
    func testBorder_clearsTheNonTextFloorAgainstThePage() {
        let expected: [(style: UIUserInterfaceStyle, ratio: CGFloat)] = [
            (.dark, 3.40),
            (.light, 3.15)
        ]
        for entry in expected {
            let trait = UITraitCollection(userInterfaceStyle: entry.style)
            let page = AppColors.bg0.resolvedColor(with: trait)
            let border = AlarmsStreakBannerView.borderColor(for: trait)
            let ratio = contrast(composite(border, over: page), page)

            XCTAssertGreaterThanOrEqual(
                ratio, nonTextFloor - tolerance,
                "\(entry.style) border reads \(ratio.ratioText):1 on the page — below the 3:1 "
                + "floor the banner's only edge has to clear"
            )
            XCTAssertEqual(
                ratio, entry.ratio, accuracy: tolerance,
                "\(entry.style) border moved off its recorded measurement"
            )
        }
    }

    /// The alphas that produce those ratios are a deliberate departure from
    /// the prototype's flat 18%, and they are asymmetric because the light
    /// money scale is a dark green while the dark one glows. Pin them so a
    /// later "tidy-up" back to one shared value is a failing test, not a
    /// silent regression.
    func testBorderAlphas_stayAsymmetricAndAboveTheCanonEighteenPercent() {
        XCTAssertEqual(AlarmsStreakBannerView.borderAlphas.dark, 0.50, accuracy: 0.001)
        XCTAssertEqual(AlarmsStreakBannerView.borderAlphas.light, 0.75, accuracy: 0.001)
        XCTAssertGreaterThan(
            AlarmsStreakBannerView.borderAlphas.light,
            AlarmsStreakBannerView.borderAlphas.dark,
            "light needs the heavier stroke — #0B7B56 on #F4F6FB is a weaker separation "
            + "than #2EDB9F on #060912"
        )
    }

    // MARK: - Fixtures

    /// A banner in a window that actually propagates its override.
    ///
    /// `isHidden = false` is load-bearing and was the single reason every flip
    /// case in this file skipped (#568): a window that is never unhidden hands
    /// its `overrideUserInterfaceStyle` to nobody, so the banner kept the
    /// launch theme and `flip` could never confirm the direction it asked for.
    private func makeHostedBanner() -> (AlarmsStreakBannerView, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.isHidden = false
        let host = UIViewController()
        let banner = AlarmsStreakBannerView(frame: CGRect(x: 0, y: 0, width: 393, height: 84))
        host.view.addSubview(banner)
        window.rootViewController = host
        hostWindows.append(window)
        return (banner, window)
    }

    /// Flip the window and confirm it landed. `XCTFail`, not `XCTSkip`: a
    /// harness that stops propagating has to say so in red, or this file goes
    /// back to reporting four cases that never ran.
    private func flip(
        _ window: UIWindow,
        to style: UIUserInterfaceStyle,
        _ banner: AlarmsStreakBannerView
    ) {
        window.overrideUserInterfaceStyle = style
        window.layoutIfNeeded()
        XCTAssertEqual(
            banner.traitCollection.userInterfaceStyle, style,
            "the harness stopped propagating the flip to \(style) — fix the harness, "
            + "do not skip"
        )
    }

    /// The caps title is the only label carrying `.kern` — picking it by
    /// "first label with an attributed string" would find the meta line too,
    /// because `UILabel.text` synthesises one.
    private func capsColor(of banner: AlarmsStreakBannerView) -> CGColor? {
        for case let label as UILabel in banner.subviews {
            guard let attributed = label.attributedText, attributed.length > 0 else { continue }
            guard attributed.attribute(.kern, at: 0, effectiveRange: nil) != nil else { continue }
            let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            return color?.cgColor
        }
        return nil
    }

    // MARK: - Colour maths

    /// Source-over composite of a translucent colour onto an opaque one.
    private func composite(_ color: UIColor, over background: UIColor) -> UIColor {
        let top = channels(color)
        let base = channels(background)
        let alpha = top.alpha
        return UIColor(
            red: top.red * alpha + base.red * (1 - alpha),
            green: top.green * alpha + base.green * (1 - alpha),
            blue: top.blue * alpha + base.blue * (1 - alpha),
            alpha: 1
        )
    }

    private func hex(_ color: CGColor) -> UInt32 {
        hex(UIColor(cgColor: color))
    }

    /// RGBA, not RGB: the fill stops differ from each other only in alpha, so
    /// dropping it would make the two-stop wash compare equal to itself.
    private func hex(_ color: UIColor) -> UInt32 {
        let rgb = channels(color)
        let toByte: (CGFloat) -> UInt32 = {
            UInt32(Swift.min(Swift.max(($0 * 255).rounded(), 0), 255))
        }
        return (toByte(rgb.red) << 24) | (toByte(rgb.green) << 16)
            | (toByte(rgb.blue) << 8) | toByte(rgb.alpha)
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

private extension CGFloat {
    /// Two decimals — a failure message should carry the measurement.
    var ratioText: String { String(format: "%.2f", self) }
}
