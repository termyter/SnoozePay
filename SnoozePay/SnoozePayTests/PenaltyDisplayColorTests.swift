import XCTest
@testable import SnoozePay

/// The snooze price numeral's ink, and the price paid for it.
///
/// `AppColors.priceDisplay` is a `warnFill*` value used as text, which the
/// token doctrine in `AppColors.swift` otherwise forbids. It is there because
/// the canon and the doctrine disagree and the canon won by PM decision
/// (#673): the amount, the preset chip under it and the slider track above it
/// are one amber family in `SPMore2.jsx`, and rendering the largest of the
/// three in bronze `#966107` is what the PM reported as a wrong colour.
///
/// These tests exist so that the trade-off cannot rot quietly. They pin the
/// tie to the chip (so the two can never drift apart again) and they pin the
/// contrast ratio the exception actually costs (so nobody re-derives it as
/// "probably fine").
final class PenaltyDisplayColorTests: XCTestCase {

    /// The amount and the selected preset chip are the same amber, in both
    /// themes. This is the whole point of the token: one family, one value.
    func testPriceInkMatchesTheSelectedPresetChip() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(
                hex(AppColors.priceDisplay, style),
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
            hex(AppColors.priceDisplay, .light),
            hex(AppColors.priceDisplay, .dark),
            "the canon warn ramp is theme-independent; priceDisplay must be too"
        )
    }

    /// The cost of the exception, stated rather than assumed.
    ///
    /// On the light card the amount measures ~2.15:1, below both 4.5:1 and the
    /// 3:1 large-text threshold. What keeps that from being a lost value is
    /// that the same number is also carried by the selected chip, whose ink is
    /// `fgOnWarn` — the assertion below holds that second carrier to the full
    /// 4.5:1 so the redundancy can't be removed without this test going red.
    func testTheLightModeShortfallIsPinnedAndTheChipCarriesTheValue() {
        let onCard = contrastRatio(
            AppColors.priceDisplay.resolved(.light),
            AppColors.bg1.resolved(.light)
        )
        XCTAssertEqual(
            onCard,
            2.15,
            accuracy: 0.05,
            """
            priceDisplay on bg1 measures \(String(format: "%.2f", onCard)):1. If \
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
