import XCTest
@testable import SnoozePay

/// The snooze price's ink — one treatment on both screens that show it (#683).
///
/// Canon paints the price `var(--sp-warn-400)` on the alarm form
/// (`docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:240`) and
/// on the Settings row (`SPMore2.jsx:99`). Both call sites now take
/// `AppColors.snoozePriceInk`, and these tests read the colour off the REAL
/// rendered views rather than off the token, so a call site that drifts to a
/// different token goes red here even if the token itself is untouched.
///
/// History: #673 put the form on `warnFill500` (amber, 2.15:1 on white) while
/// Settings stayed on `warn400` (bronze, 5.24:1). That split is what #683
/// reported and what the cross-screen assertion below forbids.
@MainActor
final class PenaltyDisplayColorTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    /// The form's amount, the form's `₽`, the Settings value and the Settings
    /// glyph all resolve to the same colour, in light and in dark.
    func testFormAndSettingsPaintThePriceWithOneInk_inBothThemes() throws {
        let cell = hostedCell(amount: 50)
        let field = try XCTUnwrap(descendant(UITextField.self, in: cell))
        let suffix = try XCTUnwrap(descendants(UILabel.self, in: cell).first { $0.text == "₽" })

        let (settings, priceText) = makeSettings()
        let row = settings.makeFinanceCell(at: IndexPath(
            row: SettingsViewController.FinanceRow.defaultPrice.rawValue,
            section: try XCTUnwrap(settings.visibleSections.firstIndex(of: .finance))
        ))
        let value = try XCTUnwrap(
            descendants(UILabel.self, in: row).first { $0.text == priceText },
            "the Settings price value is gone"
        )
        let glyph = try XCTUnwrap(descendant(UIImageView.self, in: row))

        for style in [UIUserInterfaceStyle.light, .dark] {
            let expected = hex(AppColors.snoozePriceInk, style)
            XCTAssertEqual(hex(try XCTUnwrap(field.textColor), style), expected, "form amount, \(name(style))")
            XCTAssertEqual(hex(try XCTUnwrap(suffix.textColor), style), expected, "form ₽, \(name(style))")
            XCTAssertEqual(hex(try XCTUnwrap(value.textColor), style), expected, "Settings value, \(name(style))")
            XCTAssertEqual(hex(glyph.tintColor, style), expected, "Settings glyph, \(name(style))")
        }
    }

    /// The token is the canon `--sp-warn-400` in dark and its text-safe
    /// derivation in light — the same values as `warn400`, not a new colour.
    func testPriceInkIsWarn400_canonInDark_bronzeInLight() {
        XCTAssertEqual(hex(AppColors.snoozePriceInk, .dark), "#FFB84D", "canon --sp-warn-400")
        XCTAssertEqual(hex(AppColors.snoozePriceInk, .light), "#966107")
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(hex(AppColors.snoozePriceInk, style), hex(AppColors.warn400, style))
        }
    }

    /// Both rows sit on `bg1`. The price is body-size text in Settings (14pt)
    /// and the sole carrier of the value on the form at non-preset amounts, so
    /// it has to clear 4.5:1 in both themes — which the #673 amber did not.
    func testPriceInkClearsBodyTextOnTheCard_inBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrastRatio(
                AppColors.snoozePriceInk.resolved(style),
                AppColors.bg1.resolved(style)
            )
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "snooze price ink is \(String(format: "%.2f", ratio)):1 on bg1 in \(name(style))"
            )
        }
    }

    /// The amount and its `₽` are repainted together when the typed value
    /// stops validating, and back to the price ink when it starts again.
    func testInvalidInputRepaintsBothGlyphsAndValidInputRestoresThem() throws {
        let cell = hostedCell(amount: 50)
        let field = try XCTUnwrap(descendant(UITextField.self, in: cell))
        let suffix = try XCTUnwrap(
            descendants(UILabel.self, in: cell).first { $0.text == "₽" },
            "the rouble glyph is gone"
        )

        assertSameInk(field.textColor, suffix.textColor, "valid amount")
        XCTAssertEqual(hex(try XCTUnwrap(field.textColor), .light), hex(AppColors.snoozePriceInk, .light))

        field.text = ""
        field.sendActions(for: .editingChanged)
        assertSameInk(field.textColor, suffix.textColor, "invalid amount")
        XCTAssertEqual(
            hex(try XCTUnwrap(field.textColor), .light),
            hex(AppColors.pain400, .light),
            "an amount that does not validate must read as pain, not as a price"
        )

        field.text = "137"
        field.sendActions(for: .editingChanged)
        assertSameInk(field.textColor, suffix.textColor, "restored amount")
        XCTAssertEqual(
            hex(try XCTUnwrap(field.textColor), .light),
            hex(AppColors.snoozePriceInk, .light),
            "the restoring half of the branch kept an old ink"
        )
    }

    private func assertSameInk(_ lhs: UIColor?, _ rhs: UIColor?, _ context: String) {
        guard let lhs, let rhs else {
            XCTFail("\(context): one of the two glyphs has no colour at all")
            return
        }
        XCTAssertEqual(
            hex(lhs, .light),
            hex(rhs, .light),
            "\(context): the amount and its ₽ drifted apart"
        )
    }

    private func hostedCell(amount: Double) -> PenaltyCell {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        cell.configure(amount: amount, currency: .rub)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 343, height: 400))
        window.overrideUserInterfaceStyle = .light
        window.isHidden = false
        hostWindows.append(window)
        cell.frame = CGRect(x: 0, y: 0, width: 343, height: 240)
        window.addSubview(cell)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return cell
    }

    /// A Settings screen on an isolated defaults suite with a frozen ₽ wallet,
    /// plus the exact text its price row renders.
    private func makeSettings() -> (SettingsViewController, String) {
        let suite = "PenaltyDisplayColorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let currencyStore = WalletCurrencyStore(defaults: defaults)
        _ = currencyStore.freeze(.rub)
        let alarmDefaults = AlarmDefaults(defaults: defaults)
        alarmDefaults.penaltyAmount = 50
        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        let sut = SettingsViewController(
            themeService: ThemeService(defaults: defaults),
            alarmDefaults: alarmDefaults,
            referralService: ReferralService(defaults: defaults, balanceService: wallet),
            walletCurrencyStore: currencyStore
        )
        sut.loadViewIfNeeded()
        return (sut, MoneyFormatter.string(Double(50), currency: .rub))
    }

    private func descendant<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        descendants(type, in: root).first
    }

    private func descendants<T: UIView>(_ type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T { found.append(match) }
            found.append(contentsOf: descendants(type, in: subview))
        }
        return found
    }

    // MARK: - Helpers

    private func name(_ style: UIUserInterfaceStyle) -> String {
        style == .dark ? "dark" : "light"
    }

    private func hex(_ color: UIColor, _ style: UIUserInterfaceStyle) -> String {
        let channels = self.channels(color.resolved(style))
        return String(
            format: "#%02X%02X%02X",
            Int((channels.red * 255).rounded()),
            Int((channels.green * 255).rounded()),
            Int((channels.blue * 255).rounded())
        )
    }

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return Channels(red: red, green: green, blue: blue)
        }
        var white: CGFloat = 0
        color.getWhite(&white, alpha: &alpha)
        return Channels(red: white, green: white, blue: white)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        let channels = self.channels(color)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(channels.red)
            + 0.7152 * linear(channels.green)
            + 0.0722 * linear(channels.blue)
    }

    private func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
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
