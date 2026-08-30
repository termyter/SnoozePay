import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme floor for the alarm form, its pickers and the confirm-delete
/// sheet (#492).
///
/// Everything pinned here is a *snapshot* defect — a value that was resolved
/// once, cached as a bitmap or a `cgColor`, and then never re-resolved. That
/// class of bug is invisible to a dark-only eyeball pass and invisible to a
/// detached-view test: a view that is never in a window never receives the
/// trait-change callback, keeps its `init`-time resolution, and measures
/// identical in both themes. Every case below that cares about the theme
/// hosts its subject in a `UIWindow` and overrides the style on the WINDOW.
@MainActor
final class CreateAlarmLightThemeTests: XCTestCase {

    /// Windows hosting the surfaces under test. Held for the lifetime of the
    /// test case: a released window takes its subtree's traits with it.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Slider thumb

    /// The regression this renderer exists for: both sliders used to build
    /// their thumb from a `static` helper during property initialisation, so
    /// the bitmap froze whichever theme was current then.
    func testSliderThumb_rendersADifferentBitmapPerTheme() {
        let light = SPSliderThumb.image(diameter: SPSliderThumb.diameter, trait: trait(.light))
        let dark = SPSliderThumb.image(diameter: SPSliderThumb.diameter, trait: trait(.dark))
        XCTAssertNotEqual(
            light.pngData(), dark.pngData(),
            "the thumb renders identically in both themes — it is not resolving its tokens per trait"
        )
    }

    /// The gloss is a highlight, not text, so it doesn't owe 4.5:1 — but it
    /// has to stay visible on the disc in both themes. `fgOnMoney` inverts
    /// with the fill, which is exactly why it can serve both.
    func testSliderThumbGloss_staysVisibleOnTheDisc_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let disc = AppColors.money500.resolved(style)
            let gloss = composite(
                AppColors.fgOnMoney.resolved(style).withAlphaComponent(0.45),
                over: disc
            )
            let ratio = contrastRatio(gloss, disc)
            XCTAssertGreaterThanOrEqual(
                ratio, 2.0,
                "gloss is \(String(format: "%.2f", ratio)):1 on the disc in \(style.debugName)"
            )
        }
    }

    /// A white gloss was fine on the dark theme's bright mint but is what the
    /// old hardcoded literal shipped in both. Kept as the counter-example so
    /// nobody "simplifies" it back.
    func testWhiteGloss_wasTheWeakerChoiceOnTheDarkDisc() {
        let disc = AppColors.money500.resolved(.dark)
        let old = composite(UIColor.white.withAlphaComponent(0.35), over: disc)
        let new = composite(
            AppColors.fgOnMoney.resolved(.dark).withAlphaComponent(0.45),
            over: disc
        )
        XCTAssertLessThan(contrastRatio(old, disc), contrastRatio(new, disc))
    }

    // MARK: - Slider track

    /// The unfilled remainder is `rgba(255,255,255,.10)` in the JSX. UIKit's
    /// default maximum track is a fixed system grey that follows neither.
    func testSnoozeSlider_paintsBothTrackHalvesWithTokens() {
        let cell = SnoozeSliderCell(style: .default, reuseIdentifier: nil)
        guard let slider = firstSlider(in: cell.contentView) else {
            return XCTFail("SnoozeSliderCell must own a UISlider")
        }
        // The filled half is the warn FILL, not the warn ink (#520): on the ink
        // tone this track was `#7C5006` against a `#096647` thumb in light.
        XCTAssertEqual(hex(slider.minimumTrackTintColor ?? .clear), hex(AppColors.warnFill500))
        XCTAssertEqual(hex(slider.minimumTrackTintColor?.resolved(.light) ?? .clear), "F59E0B@1.00")
        XCTAssertEqual(hex(slider.maximumTrackTintColor ?? .clear), hex(AppColors.whiteOverlay12))
        XCTAssertNotNil(slider.thumbImage(for: .normal))
        XCTAssertNotNil(slider.thumbImage(for: .highlighted))
    }

    // MARK: - Progressive card

    func testProgressiveCard_fillsTheBrandCardToken_notTheSystemGrey() {
        let surface = ProgressiveCardSurface()
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                hex(surface.backgroundColor?.resolved(style) ?? .clear),
                hex(AppColors.bg1.resolved(style)),
                "progressive card fill in \(style.debugName) must match its sibling sections"
            )
        }
    }

    /// A white card on a `#F4F6FB` page is 1.06:1 of separation, so the
    /// disarmed card needs its hairline too — it used to draw one only while
    /// pain-tinted.
    func testProgressiveCard_carriesShadowAndOutline_inBothThemes_disarmedToo() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let surface = hostedProgressiveCard(painTinted: false, style: style)
            XCTAssertGreaterThan(
                surface.layer.borderWidth, 0,
                "disarmed progressive card has no outline in \(style.debugName)"
            )
            XCTAssertNotNil(surface.layer.borderColor)
            XCTAssertGreaterThan(surface.layer.shadowOpacity, 0)
            XCTAssertNotNil(surface.layer.shadowPath)
            XCTAssertFalse(surface.layer.masksToBounds, "masksToBounds would clip the shadow away")
        }
    }

    /// The decoration caches `cgColor`s, so a flip under an already-rendered
    /// card has to repaint them.
    func testProgressiveCardOutline_differsPerTheme() {
        let light = hostedProgressiveCard(painTinted: false, style: .light)
        let dark = hostedProgressiveCard(painTinted: false, style: .dark)
        XCTAssertNotEqual(
            light.layer.borderColor.map { hex(UIColor(cgColor: $0)) },
            dark.layer.borderColor.map { hex(UIColor(cgColor: $0)) }
        )
        XCTAssertNotEqual(light.layer.shadowRadius, dark.layer.shadowRadius)
    }

    /// Arming the card must still swap the neutral hairline for the pain tint.
    func testProgressiveCard_armedOutlineIsPainTinted() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let armed = hostedProgressiveCard(painTinted: true, style: style)
            guard let border = armed.layer.borderColor else {
                return XCTFail("armed card has no outline in \(style.debugName)")
            }
            let expected = AppColors.pain500.resolved(style).withAlphaComponent(0.25)
            XCTAssertEqual(
                hex(UIColor(cgColor: border)),
                hex(expected),
                "armed outline in \(style.debugName)"
            )
        }
    }

    /// The card's outline is the same weight as every other card's, in both
    /// states and both themes (#675).
    ///
    /// The armed state used to hard-code `borderWidth = 1` — the only 1.0pt
    /// outline in the app — so switching the control off dropped this card's
    /// own outline to a third of what it had just been while its neighbours
    /// never moved. That step is what was reported as a lost border.
    ///
    /// ⚠️ The sibling's outline is selected by `strokeColor != nil`, NOT by
    /// position. `AppShadow.ambientShadow1` is also a `CAShapeLayer`, sits at
    /// sublayer index 0 in light, is fill-only and never stroked, and carries
    /// `CAShapeLayer`'s default `lineWidth` of 1. Reading `.first` returns
    /// that layer in light and the real outline in dark, which is exactly how
    /// two revisions of this fix ended up chasing a theme-dependent width that
    /// does not exist. A helper that reports a shadow's default as a hairline
    /// is worse than no helper.
    func testProgressiveCardOutline_isTheSameWeightAsASiblingCardRow() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let sibling = try XCTUnwrap(
                hostedSiblingCardRowOutlineWidth(style: style),
                "the sibling card row draws no stroked outline to compare against"
            )
            for armed in [false, true] {
                let card = hostedProgressiveCard(painTinted: armed, style: style)
                XCTAssertEqual(
                    card.layer.borderWidth, sibling, accuracy: 0.001,
                    """
                    \(style.debugName), armed: \(armed) — the progressive card draws a \
                    \(card.layer.borderWidth)pt outline where its sibling card row draws \
                    \(sibling)pt
                    """
                )
            }
        }
    }

    /// …and that weight does not depend on the theme.
    ///
    /// Asserted across themes rather than within one, because a comparison
    /// inside a single theme stays green when two classes regress together.
    func testTheCardHairlineWeightDoesNotDependOnTheTheme() throws {
        let light = try XCTUnwrap(hostedSiblingCardRowOutlineWidth(style: .light))
        let dark = try XCTUnwrap(hostedSiblingCardRowOutlineWidth(style: .dark))
        XCTAssertEqual(light, dark, accuracy: 0.001, "the card hairline is theme-dependent")

        let cardLight = hostedProgressiveCard(painTinted: false, style: .light)
        let cardDark = hostedProgressiveCard(painTinted: false, style: .dark)
        XCTAssertEqual(
            cardLight.layer.borderWidth, cardDark.layer.borderWidth, accuracy: 0.001,
            "the progressive card's hairline is theme-dependent"
        )
    }

    // MARK: - Confirm-delete sheet

    /// The sheet's copy is composed, not literal, so the empty-string case is
    /// worth pinning: an empty body would collapse the sheet to a strip.
    /// Both overloads are unconditionally non-empty — the reassurance sentence
    /// always renders, with or without an alarm context line.
    func testDeletionCopy_isNeverEmpty_withOrWithoutAlarmContext() {
        XCTAssertFalse(AlarmDeletionCopy.body(balance: 0).isEmpty)
        XCTAssertFalse(AlarmDeletionCopy.body(contextLine: nil, balance: 840).isEmpty)
        XCTAssertFalse(AlarmDeletionCopy.body(contextLine: "", balance: 840).isEmpty)
        XCTAssertFalse(
            AlarmDeletionCopy.body(contextLine: "Будни · Пн–Пт · 07:00", balance: 840).isEmpty
        )
    }

    /// Was a pinned KNOWN DEFECT for #467; now a real assertion (#485).
    ///
    /// This test was written to prove the sheet's layout was sound and that
    /// #467's zero-height labels were a harness artefact of `UITourLauncher`
    /// presenting from a controller not yet in the hierarchy. It proved the
    /// opposite: hosted in a plain 390×844 window, with both labels present
    /// and carrying non-empty text, headline and body still measured 0pt in
    /// BOTH themes. So the defect was in the sheet, not in the tour — this
    /// measurement is what ruled the router out.
    ///
    /// The cause was `deleteButton`/`cancelButton` keeping
    /// `translatesAutoresizingMaskIntoConstraints`, which pinned both to a
    /// required 0×0 frame and made Auto Layout break the badge's height and
    /// both labels' intrinsic heights to satisfy the card's vertical chain.
    /// With the flag cleared the headline now measures 33pt at y=104
    /// (24 top margin + 64 badge + 16), so the expectation is promoted to a
    /// plain assertion exactly as this comment used to instruct.
    ///
    /// The copy is not involved — `testDeletionCopy_isNeverEmpty…` above
    /// covers that, and the labels are found here *by their text*. The
    /// measurements still print to the CI log so a regression arrives with
    /// geometry rather than a symptom.
    func testConfirmDeleteSheet_titleAndBodyMeasure_whenHosted() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let sheet = hostedConfirmDeleteSheet(style: style)
            let labels = allLabels(in: sheet.view)
            let title = labels.first { $0.text == "Удалить будильник?" }
            let body = labels.first { $0.text?.hasPrefix("Баланс") == true }
            XCTAssertNotNil(title, "headline label missing in \(style.debugName)")
            XCTAssertNotNil(body, "body label missing in \(style.debugName)")
            print(
                "[#467] \(style.debugName): root=\(sheet.view.bounds.size) "
                + "title=\(title?.frame ?? .zero) intrinsic=\(title?.intrinsicContentSize ?? .zero) "
                + "ambiguous=\(title?.hasAmbiguousLayout ?? false) "
                + "body=\(body?.frame ?? .zero) intrinsic=\(body?.intrinsicContentSize ?? .zero) "
                + "bodyText=\((body?.text ?? "").count)ch"
            )
            XCTAssertGreaterThan(title?.bounds.height ?? 0, 0, "headline height in \(style.debugName)")
            XCTAssertGreaterThan(body?.bounds.height ?? 0, 0, "body height in \(style.debugName)")
        }
    }

    /// The scrim dims whatever is behind it, so it stays dark in BOTH themes.
    /// A theme-following scrim would leave a near-white sheet floating on a
    /// near-white haze.
    func testConfirmDeleteScrim_staysDark_evenInLight() {
        let sheet = hostedConfirmDeleteSheet(style: .light)
        // The blur view sits below the scrim and may carry its own faint
        // fill, so match on the scrim's own alpha rather than "first
        // translucent subview".
        let scrim = sheet.view.subviews.first { subview in
            guard !(subview is UIVisualEffectView),
                  let alpha = subview.backgroundColor?.cgColor.alpha else { return false }
            return abs(alpha - 0.55) < 0.001
        }
        guard let fill = scrim?.backgroundColor else {
            return XCTFail("confirm-delete sheet must install a scrim")
        }
        XCTAssertLessThan(luminance(fill.withAlphaComponent(1)), 0.02, "scrim resolved light")
        XCTAssertEqual(fill.cgColor.alpha, 0.55, accuracy: 0.001)
    }

    // MARK: - Fixtures

    private func trait(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: style)
    }

    private func host<T: UIView>(_ view: T, style: UIUserInterfaceStyle, size: CGSize) -> T {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        hostWindows.append(window)
        view.frame = window.bounds
        window.addSubview(view)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return view
    }

    /// The hairline weight a plain sibling card row draws, read off the real
    /// stroked layer.
    ///
    /// `CardRowBackgroundView.outline` is private, so this finds it by the one
    /// property that distinguishes it: it strokes. Filtering by position
    /// instead picks up `AppShadow.ambientShadow1` in light — see the note on
    /// `testProgressiveCardOutline_isTheSameWeightAsASiblingCardRow`. Returns
    /// `nil` rather than a default, so a missing layer fails the unwrap
    /// instead of passing a comparison against 0.
    private func hostedSiblingCardRowOutlineWidth(style: UIUserInterfaceStyle) -> CGFloat? {
        let row = host(
            CardRowBackgroundView(position: .single, cornerRadius: AppRadius.sm),
            style: style,
            size: CGSize(width: 343, height: 52)
        )
        return row.layer.sublayers?
            .compactMap { $0 as? CAShapeLayer }
            .first { $0.strokeColor != nil }?
            .lineWidth
    }

    private func hostedProgressiveCard(
        painTinted: Bool,
        style: UIUserInterfaceStyle
    ) -> ProgressiveCardSurface {
        let surface = host(
            ProgressiveCardSurface(),
            style: style,
            size: CGSize(width: 343, height: 120)
        )
        surface.setPainTinted(painTinted)
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        return surface
    }

    private func hostedConfirmDeleteSheet(
        style: UIUserInterfaceStyle
    ) -> ConfirmDeleteAlarmViewController {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = style
        hostWindows.append(window)
        let sheet = ConfirmDeleteAlarmViewController()
        window.rootViewController = sheet
        window.isHidden = false
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return sheet
    }

    private func firstSlider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let nested = firstSlider(in: subview) { return nested }
        }
        return nil
    }

    private func allLabels(in view: UIView) -> [UILabel] {
        view.subviews.reduce(into: [UILabel]()) { result, subview in
            if let label = subview as? UILabel { result.append(label) }
            result.append(contentsOf: allLabels(in: subview))
        }
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
