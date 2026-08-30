import XCTest
@testable import SnoozePay

/// The snooze price numeral's ink, and the price paid for it.
///
/// `AppColors.penaltyAmountDisplay32` is a `warnFill*` value used as text,
/// which the token doctrine in `AppColors.swift` otherwise forbids.
///
/// It is NOT "the canon won" — an earlier version of this header said so, and
/// that is not what happened. Canon paints the numeral `var(--sp-warn-400)`
/// (`SPMore2.jsx:241`) on a dark surface; the app renders it on white. Three
/// candidate inks, all measured against white:
///
/// | ink | ratio on white |
/// |---|---|
/// | `#FFB84D` (the literal canon value) | 1.719:1 |
/// | `#F59E0B` (what this token resolves to) | 2.148:1 |
/// | `#966107` (the bronze it replaced) | 5.237:1 |
///
/// So this is a THIRD value, chosen by PM decision (#673) because the amount,
/// the preset chip under it and the slider track above it read as one amber
/// family and the largest of the three was the odd one out. It buys that
/// family at a real cost in contrast, and the cost is pinned below rather
/// than left to be re-derived as "probably fine".
///
/// These tests exist so that the trade-off cannot rot quietly. They pin the
/// tie to the chip (so the two can never drift apart again) and they pin the
/// contrast ratio the exception actually costs (so nobody re-derives it as
/// "probably fine").
@MainActor
final class PenaltyDisplayColorTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    /// The amount and the selected preset chip are the same amber, in both
    /// themes. This is the whole point of the token: one family, one value.
    func testPriceInkMatchesTheSelectedPresetChip() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                hex(AppColors.penaltyAmountDisplay32, style),
                hex(AppColors.warnFill500, style),
                "price ink and the selected chip's fill diverged in \(name(style))"
            )
        }
    }

    /// `warnFill*` is flat by design, so the amount reads identically in both
    /// themes — matching `tokens.css`, which never overrides the warn ramp in
    /// its `[data-theme="light"]` block.
    func testPriceInkIsTheSameAmberInBothThemes() {
        XCTAssertEqual(
            hex(AppColors.penaltyAmountDisplay32, .light),
            hex(AppColors.penaltyAmountDisplay32, .dark),
            "the canon warn ramp is theme-independent; penaltyAmountDisplay32 must be too"
        )
    }

    /// The cost of the exception, stated rather than assumed.
    ///
    /// On the light card the amount measures ~2.15:1, below both 4.5:1 and the
    /// 3:1 large-text threshold. The mitigation is that the same number is
    /// usually also carried by the selected preset chip, whose ink is
    /// `fgOnWarn` — the assertion below holds that second carrier to the full
    /// 4.5:1 so the redundancy can't be removed without this test going red.
    ///
    /// ⚠️ "Usually" is doing real work in that sentence, and
    /// `testTheChipOnlyCarriesTheValueOnPresetAmounts` pins exactly where it
    /// stops being true.
    func testTheLightModeShortfallIsPinnedAndTheChipCarriesTheValue() {
        let onCard = contrastRatio(
            AppColors.penaltyAmountDisplay32.resolved(.light),
            AppColors.bg1.resolved(.light)
        )
        XCTAssertEqual(
            onCard,
            2.15,
            accuracy: 0.05,
            """
            penaltyAmountDisplay32 on bg1 measures \(String(format: "%.2f", onCard)):1. If \
            this moved UP past 3.0 the exception is no longer needed and the \
            comment in AppColors should be retired; if it moved DOWN the \
            regression is worse than the one #673 accepted
            """
        )

        let chipInk = contrastRatio(
            AppColors.fgOnWarn.resolved(.light),
            AppColors.warnFill500.resolved(.light)
        )
        XCTAssertGreaterThanOrEqual(
            chipInk,
            4.5,
            """
            The chip is the accessible carrier of the amount — it measures \
            \(String(format: "%.2f", chipInk)):1 and must stay at 4.5:1 or \
            better, or the price has no readable representation at all
            """
        )
    }

    // MARK: - Where the mitigation runs out

    /// The honest boundary of the accessibility argument above.
    ///
    /// The field is a free `numberPad` with a 1 ₽ floor, and a chip lights only
    /// on an exact preset match (`abs(preset - currentAmount) < .ulpOfOne`).
    /// So for 137 ₽ there is no second carrier at all: the number exists on
    /// screen exactly once, at 2.15:1.
    ///
    /// This test does not assert that that is acceptable — it asserts that it
    /// is TRUE, so the trade-off in `AppColors.penaltyAmountDisplay32` cannot be read as
    /// broader than it is. If the redundancy is ever made unconditional (a
    /// chip that reflects any amount, a second readout), this test goes red and
    /// the caveat can come out of the comment.
    func testTheChipOnlyCarriesTheValueOnPresetAmounts() {
        XCTAssertEqual(
            selectedChipCount(forAmount: 50),
            1,
            "a preset amount must light its chip — that is the accessible carrier"
        )
        XCTAssertEqual(
            selectedChipCount(forAmount: 137),
            0,
            """
            a chip lit for a non-preset amount would mean the mitigation is \
            unconditional — good news, but the caveat in AppColors.penaltyAmountDisplay32 \
            then needs rewriting rather than leaving as-is
            """
        )
    }

    /// The branch this PR actually edits: the amount and its `₽` are repainted
    /// together when the typed value stops validating, and back again when it
    /// starts. A regression that left the restoring half on the old bronze
    /// would be invisible without this.
    func testInvalidInputRepaintsBothGlyphsAndValidInputRestoresThem() throws {
        let cell = hostedCell(amount: 50)
        let field = try XCTUnwrap(descendant(UITextField.self, in: cell))
        let suffix = try XCTUnwrap(
            descendants(UILabel.self, in: cell).first { $0.text == "₽" },
            "the rouble glyph is gone"
        )

        assertSameInk(field.textColor, suffix.textColor, "valid amount")
        XCTAssertEqual(hex(try XCTUnwrap(field.textColor), .light), hex(AppColors.penaltyAmountDisplay32, .light))

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
            hex(AppColors.penaltyAmountDisplay32, .light),
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

    private func selectedChipCount(forAmount amount: Double) -> Int {
        let cell = hostedCell(amount: amount)
        let selected = hex(AppColors.warnFill500, .light)
        return descendants(UIButton.self, in: cell)
            .filter { $0.backgroundColor.map { hex($0, .light) } == selected }
            .count
    }

    private func hostedCell(amount: Double) -> PenaltyCell {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        cell.configure(amount: amount)
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
