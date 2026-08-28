import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme guarantees for the alarms list — the app's main screen (#491).
///
/// Three regressions are pinned here, all of them variants of "the dark theme
/// was the only one anybody looked at":
///
/// 1. **Ink on a wash.** The balance pill tints itself `warn500`/`pain500` at
///    10–12% and used to ink that with `warn300`/`pain300`. On the dark wash
///    those glow; on the light one they measure 2.70:1 and 2.77:1. The
///    `fgOn*Wash` pair exists precisely so the light branch can be the dark
///    end of the scale instead.
/// 2. **`cgColor` snapshots.** Gradient stops and layer colours are resolved
///    once and never follow a theme flip. Every one of them here is checked
///    through a *hosted* view whose window changes style.
/// 3. **Separation on a near-white page.** `bg2` on `bg0` is 1.07:1 in light.
///    A shadow alone does not carry that edge — the surface needs a border too.
///
/// Views are hosted in a real `UIWindow` and the style is set on the WINDOW.
/// A detached view never receives the trait-change callback, so it keeps
/// whatever it resolved at `init` and both themes measure identical.
final class AlarmsListLightThemeTests: XCTestCase {

    /// WCAG 2.1 floor for normal-size text — the pill's hint (13pt) and
    /// amount (14pt regular-weight mono) are both normal size.
    private let normalTextFloor: CGFloat = 4.5
    /// WCAG 2.1 floor for large text. The 56pt hero balance qualifies.
    private let largeTextFloor: CGFloat = 3.0
    /// Absorbs sRGB rounding only.
    private let tolerance: CGFloat = 0.05

    // MARK: - Ink on the tinted pill

    func testWashInks_readOnTheTintedPill_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let warnRatio = contrast(AppColors.fgOnWarnWash.resolved(style), warnWash(style))
            XCTAssertGreaterThanOrEqual(
                warnRatio, normalTextFloor - tolerance,
                "low-balance hint is \(warnRatio.ratioText):1 on the warn wash in \(style.name)"
            )

            let painRatio = contrast(AppColors.fgOnPainWash.resolved(style), painWash(style))
            XCTAssertGreaterThanOrEqual(
                painRatio, normalTextFloor - tolerance,
                "zero-balance hint is \(painRatio.ratioText):1 on the pain wash in \(style.name)"
            )
        }
    }

    /// The measurement the `fgOn*Wash` tokens exist to answer. If someone
    /// "simplifies" the pill back onto the 300 step, this is the number they
    /// have to argue with.
    func testTheThreeHundredStep_cannotInkTheLightWash() {
        let warnRatio = contrast(AppColors.warn300.resolved(.light), warnWash(.light))
        XCTAssertLessThan(
            warnRatio, normalTextFloor,
            "warn300 on the light warn wash measures \(warnRatio.ratioText):1"
        )

        let painRatio = contrast(AppColors.pain300.resolved(.light), painWash(.light))
        XCTAssertLessThan(
            painRatio, normalTextFloor,
            "pain300 on the light pain wash measures \(painRatio.ratioText):1"
        )
    }

    /// Dark is the canon: the wash inks must still resolve to the exact 300
    /// step there, so this issue changed light only.
    func testWashInks_leaveTheDarkThemeExactlyWhereItWas() {
        XCTAssertEqual(
            key(AppColors.fgOnWarnWash.resolved(.dark)), key(AppColors.warn300.resolved(.dark)),
            "dark low-balance ink drifted off warn300"
        )
        XCTAssertEqual(
            key(AppColors.fgOnPainWash.resolved(.dark)), key(AppColors.pain300.resolved(.dark)),
            "dark zero-balance ink drifted off pain300"
        )
    }

    // MARK: - The pill, as the header actually builds it

    func testZeroBalancePill_inksItsTextWithTheWashPair_notTheGlowStep() throws {
        let (header, window) = makeHostedHeader(style: .light)
        defer { window.isHidden = true }
        header.setBalance(0, hint: "Пополни, чтобы откладывать")
        window.layoutIfNeeded()

        let labels = try pillLabels(of: header)
        // Insertion order inside the pill: caps "БАЛАНС", the amount, the hint.
        // Asserted so a reordering fails loudly instead of measuring the wrong
        // label. The caps label is `fg3` — a design-system-wide meta tone, out
        // of this issue's scope — so only the two tone-driven inks are checked.
        XCTAssertEqual(labels.count, 3, "pill layout changed — re-check which label is which")

        let amountInk = try XCTUnwrap(foregroundColor(of: labels[1]), "amount has no ink")
        let amountRatio = contrast(amountInk.resolved(.light), painWash(.light))
        XCTAssertGreaterThanOrEqual(
            amountRatio, normalTextFloor - tolerance,
            "0 ₽ amount is \(amountRatio.ratioText):1 on the light pain wash"
        )

        let hintRatio = contrast(labels[2].textColor.resolved(.light), painWash(.light))
        XCTAssertGreaterThanOrEqual(
            hintRatio, normalTextFloor - tolerance,
            "zero-balance hint is \(hintRatio.ratioText):1 on the light pain wash"
        )
    }

    func testLowBalancePill_inksItsHintAgainstItsOwnTint() throws {
        let (header, window) = makeHostedHeader(style: .light)
        defer { window.isHidden = true }
        header.setBalance(50, hint: "Хватит на 1 откладывание")
        window.layoutIfNeeded()

        let labels = try pillLabels(of: header)
        let pill = try XCTUnwrap(findPill(in: header))
        // The warn tone paints a real background colour, so measure against
        // the pill's own fill composited over the page rather than a model of it.
        let fill = try XCTUnwrap(pill.backgroundColor, "warn tone painted no fill")
        let surface = composite(fill.resolved(.light), over: AppColors.bg0.resolved(.light))
        let ratio = contrast(labels[2].textColor.resolved(.light), surface)
        XCTAssertGreaterThanOrEqual(
            ratio, normalTextFloor - tolerance,
            "low-balance hint is \(ratio.ratioText):1 on the light warn tint"
        )
    }

    /// `bg2` on `bg0` is 1.07:1 in light — the pill has to be lifted as well
    /// as outlined. Dark keeps the flat outlined pill it always had.
    func testPill_liftsOffTheLightPage_andStaysFlatInDark() throws {
        let (light, lightWindow) = makeHostedHeader(style: .light)
        defer { lightWindow.isHidden = true }
        light.setBalance(840, hint: "Хватит на ~16 откладываний")
        lightWindow.layoutIfNeeded()
        let lightPill = try XCTUnwrap(findPill(in: light))
        XCTAssertGreaterThan(lightPill.layer.shadowOpacity, 0, "light pill needs --sp-shadow-1")
        XCTAssertGreaterThan(lightPill.layer.borderWidth, 0, "a shadow alone does not carry the edge")

        let (dark, darkWindow) = makeHostedHeader(style: .dark)
        defer { darkWindow.isHidden = true }
        dark.setBalance(840, hint: "Хватит на ~16 откладываний")
        darkWindow.layoutIfNeeded()
        let darkPill = try XCTUnwrap(findPill(in: dark))
        XCTAssertEqual(darkPill.layer.shadowOpacity, 0, "dark keeps the flat pill — bg2 on bg0 already steps")
    }

    // MARK: - The balance card

    /// The gradient is KEPT: on the light `bg2` card the ramp runs
    /// 4.55 → 6.04 → 10.61:1, so even the brightest stop clears normal text.
    /// (In dark the deep end is 3.17:1, which is why the floor here is the
    /// large-text one — the hero number is 56pt.)
    func testMoneyRamp_carriesTheHeroNumber_inBothThemes() {
        let stops = [AppColors.money400, AppColors.money500, AppColors.money700]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = AppColors.bg2.resolved(style)
            for (index, stop) in stops.enumerated() {
                let ratio = contrast(stop.resolved(style), card)
                XCTAssertGreaterThanOrEqual(
                    ratio, largeTextFloor - tolerance,
                    "money ramp stop \(index) is \(ratio.ratioText):1 on the \(style.name) card"
                )
            }
        }
    }

    func testHeroGradient_followsAThemeFlip() throws {
        let card = SPBalanceCard(balance: 12_345)
        let window = makeWindow(style: .light, hosting: card, size: CGSize(width: 350, height: 200))
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let lightStops = try XCTUnwrap(heroGradientStops(in: card), "hero number has no gradient")

        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        let darkStops = try XCTUnwrap(heroGradientStops(in: card), "hero number lost its gradient")

        XCTAssertNotEqual(
            keys(lightStops), keys(darkStops),
            "the ramp is a cached CGColor snapshot — it kept the light stops on a dark card"
        )
    }

    func testBalanceCard_carriesBorderAndShadowInLight_borderlessInDark() {
        let light = SPBalanceCard(balance: 12_345)
        let lightWindow = makeWindow(style: .light, hosting: light, size: CGSize(width: 350, height: 200))
        defer { lightWindow.isHidden = true }
        lightWindow.layoutIfNeeded()
        XCTAssertGreaterThan(light.layer.shadowOpacity, 0, "a #ECEEF6 card on a #F4F6FB page needs a shadow")
        XCTAssertGreaterThan(light.layer.borderWidth, 0, "1.07:1 of separation also needs a hairline")
        XCTAssertFalse(light.layer.masksToBounds, "a clipped layer renders no shadow at all")

        let dark = SPBalanceCard(balance: 12_345)
        let darkWindow = makeWindow(style: .dark, hosting: dark, size: CGSize(width: 350, height: 200))
        defer { darkWindow.isHidden = true }
        darkWindow.layoutIfNeeded()
        XCTAssertEqual(dark.layer.borderWidth, 0, "dark keeps the borderless card")
    }

    // MARK: - Gradient stops resolve per theme

    func testSharedGradientHelpers_resolvePerTrait() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertNotEqual(
            keys(SPSupport.moneyGradientColors(for: light)),
            keys(SPSupport.moneyGradientColors(for: dark)),
            "money ramp resolves to the same stops in both themes"
        )
        XCTAssertNotEqual(
            keys(SPSupport.painGradientColors(for: light)),
            keys(SPSupport.painGradientColors(for: dark)),
            "pain ramp resolves to the same stops in both themes"
        )
    }

    // MARK: - Fixtures

    private func makeHostedHeader(style: UIUserInterfaceStyle) -> (SPAlarmsListHeader, UIWindow) {
        let header = SPAlarmsListHeader()
        let window = makeWindow(style: style, hosting: header, size: CGSize(width: 390, height: 180))
        return (header, window)
    }

    /// Host `view` in a real window and set the style on the WINDOW — an
    /// `overrideUserInterfaceStyle` on a detached view does not deliver the
    /// trait-change callbacks the components refresh their layers from.
    private func makeWindow(
        style: UIUserInterfaceStyle,
        hosting view: UIView,
        size: CGSize
    ) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.view.topAnchor),
            view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor)
        ])
        window.layoutIfNeeded()
        return window
    }

    /// The balance pill — the only 14pt-radius `UIControl` in the header
    /// (the gear and "+" buttons are 20pt circles).
    private func findPill(in header: SPAlarmsListHeader) -> UIControl? {
        header.subviews
            .compactMap { $0 as? UIControl }
            .first { $0.layer.cornerRadius == 14 }
    }

    private func pillLabels(of header: SPAlarmsListHeader) throws -> [UILabel] {
        let pill = try XCTUnwrap(findPill(in: header), "header has no balance pill")
        return pill.subviews.compactMap { $0 as? UILabel }
    }

    /// The ink a label actually renders with: `attributedText` wins over
    /// `textColor` when it carries an explicit foreground.
    private func foregroundColor(of label: UILabel) -> UIColor? {
        if let attributed = label.attributedText, attributed.length > 0,
           let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor {
            return color
        }
        return label.textColor
    }

    private func heroGradientStops(in card: SPBalanceCard) -> [CGColor]? {
        func search(_ view: UIView) -> SPGradientTextLabel? {
            if let label = view as? SPGradientTextLabel { return label }
            for sub in view.subviews {
                if let found = search(sub) { return found }
            }
            return nil
        }
        guard let label = search(card) else { return nil }
        return (label.layer.sublayers ?? [])
            .compactMap { $0 as? CAGradientLayer }
            .first?
            .colors as? [CGColor]
    }

    // MARK: - Colour maths

    /// The low-balance pill fill: `warn500` at 12% over the page.
    private func warnWash(_ style: UIUserInterfaceStyle) -> UIColor {
        composite(
            AppColors.warn500.resolved(style).withAlphaComponent(0.12),
            over: AppColors.bg0.resolved(style)
        )
    }

    /// The zero-balance pill fill at its strongest stop — the wash runs
    /// `pain500` 10% → 2%, so 10% is the surface the ink has to survive.
    private func painWash(_ style: UIUserInterfaceStyle) -> UIColor {
        composite(
            AppColors.pain500.resolved(style).withAlphaComponent(0.10),
            over: AppColors.bg0.resolved(style)
        )
    }

    /// Stable textual identity of a colour. `CGColor` equality is not
    /// something to lean on across colour spaces, and a component string makes
    /// a failure message readable.
    private func key(_ color: UIColor) -> String {
        let rgb = channels(color)
        return String(format: "%.4f,%.4f,%.4f,%.4f", rgb.red, rgb.green, rgb.blue, rgb.alpha)
    }

    private func keys(_ colors: [CGColor]) -> [String] {
        colors.map { key(UIColor(cgColor: $0)) }
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
    /// Two decimals — failure messages carry the measurement, not a shrug.
    var ratioText: String { String(format: "%.2f", self) }
}
