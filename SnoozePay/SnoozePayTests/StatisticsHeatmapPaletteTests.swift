import UIKit
import XCTest
@testable import SnoozePay

/// Pins the heatmap's readability in BOTH themes (#493).
///
/// The grid encodes a day with colour alone, over five levels: три статуса
/// (`woke` money / `light` warn / `heavy` pain), пустой день, и сама карточка
/// под ними. After #489 the light accent scale is derived per-role, and every
/// filled status happens to land on the same 6:1 rung — which means in light
/// the three statuses are near-ISOLUMINANT and only hue separates them. WCAG
/// contrast is therefore the wrong instrument here; these tests use CIE ΔE*ab
/// (1976) for level-to-level separation and keep contrast only where the
/// question really is "can this be read as text/affordance".
///
/// What this file would have caught: the empty-day fill. `whiteOverlay04` is a
/// 4.5 ΔE whisper on the dark card and a 3.0 ΔE one on the light card — under
/// the ~2 ΔE just-noticeable difference for a small patch, i.e. the month's
/// skeleton silently disappeared in light mode.
final class StatisticsHeatmapPaletteTests: XCTestCase {

    private let styles: [UIUserInterfaceStyle] = [.light, .dark]
    private let statuses: [StatisticsViewModel.DayStatus] = [.woke, .light, .heavy]

    // MARK: - Five levels

    /// Every pair of the three filled statuses must be obviously different —
    /// they are the whole meaning of the grid. Measured ΔE*ab: light 33–79,
    /// dark 50–117.
    func testFilledStatuses_areSeparatedFromEachOther() {
        for style in styles {
            for (first, second) in pairs(statuses) {
                let delta = deltaE(midStop(first, style), midStop(second, style))
                XCTAssertGreaterThanOrEqual(
                    delta, 20,
                    "\(first) vs \(second) is only ΔE \(fmt(delta)) apart in \(name(style))"
                )
            }
        }
    }

    /// …and from the card they sit on, and from an empty day.
    func testFilledStatuses_areSeparatedFromTheCardAndFromEmptyDays() {
        for style in styles {
            let card = AppColors.bg2.resolved(style)
            let empty = flatten(StatisticsHeatmapView.emptyFillColor.resolved(style), over: card)
            for status in statuses {
                let tone = midStop(status, style)
                XCTAssertGreaterThanOrEqual(
                    deltaE(tone, card), 20,
                    "\(status) is ΔE \(fmt(deltaE(tone, card))) from bg2 in \(name(style))"
                )
                XCTAssertGreaterThanOrEqual(
                    deltaE(tone, empty), 20,
                    "\(status) is ΔE \(fmt(deltaE(tone, empty))) from an empty day in \(name(style))"
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(tone, card), 3.0 - 0.05,
                    "\(status) is \(fmt(contrast(tone, card))):1 on bg2 in \(name(style))"
                )
            }
        }
    }

    /// The empty day is the fifth level and the delicate one: visible enough
    /// to draw the calendar, quiet enough not to read as data. The light fill
    /// steps to 6% ink precisely so it carries the dark theme's weight —
    /// 4% ink on the light card is 3.0 ΔE, i.e. invisible.
    func testEmptyDay_isAWhisperOfTheSamePerceptualWeightInBothThemes() {
        var deltas: [CGFloat] = []
        for style in styles {
            let card = AppColors.bg2.resolved(style)
            let empty = flatten(StatisticsHeatmapView.emptyFillColor.resolved(style), over: card)
            let delta = deltaE(empty, card)
            deltas.append(delta)
            XCTAssertGreaterThanOrEqual(
                delta, 4.0,
                "the empty day is ΔE \(fmt(delta)) from the card in \(name(style)) — invisible"
            )
            XCTAssertLessThanOrEqual(
                delta, 8.0,
                "the empty day is ΔE \(fmt(delta)) from the card in \(name(style)) — reads as data"
            )
        }
        XCTAssertEqual(
            deltas[0], deltas[1], accuracy: 1.0,
            "the empty day should weigh the same in both themes, got "
            + "\(fmt(deltas[0])) light vs \(fmt(deltas[1])) dark"
        )
    }

    /// Within a cell the gradient must still read as a gradient after the
    /// light scale inverted its direction (light → dark on light surfaces).
    func testCellGradient_keepsItsStopsApartInBothThemes() {
        for style in styles {
            for status in statuses {
                let stops = gradientStops(status, style)
                XCTAssertEqual(stops.count, 3, "\(status) lost a gradient stop")
                for index in 0..<(stops.count - 1) {
                    let delta = deltaE(stops[index], stops[index + 1])
                    XCTAssertGreaterThanOrEqual(
                        delta, 5.0,
                        "\(status) stops \(index)/\(index + 1) are ΔE \(fmt(delta)) apart in \(name(style))"
                    )
                }
            }
        }
    }

    // MARK: - Text and affordances

    /// The tooltip's status word is 12pt semibold on `bg3` — small text, so it
    /// needs the AA bar rather than the decorative step the dark canon uses.
    func testTooltipStatusText_clearsSmallTextContrastOnTheBubble() {
        for style in styles {
            let bubble = AppColors.bg3.resolved(style)
            for status in statuses {
                let ink = StatisticsHeatmapView.toneColor(for: status).resolved(style)
                XCTAssertGreaterThanOrEqual(
                    contrast(ink, bubble), 4.5 - 0.05,
                    "\(status) tooltip text is \(fmt(contrast(ink, bubble))):1 in \(name(style))"
                )
            }
        }
    }

    /// The selection ring is a UI affordance — WCAG 1.4.11 asks 3:1 against
    /// what surrounds it. It is drawn with alpha, so it is measured composited
    /// over the card.
    func testSelectionRing_clearsTheNonTextContrastBar() {
        for style in styles {
            let card = AppColors.bg2.resolved(style)
            for status in statuses {
                let ring = flatten(
                    StatisticsHeatmapView.ringColor(for: status).resolved(style), over: card
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(ring, card), 3.0 - 0.05,
                    "\(status) ring is \(fmt(contrast(ring, card))):1 on bg2 in \(name(style))"
                )
            }
        }
    }

    // MARK: - The dark canon must not move

    /// Dark is the canon; the light work above may not touch it.
    func testDarkTones_stillMatchTheBrandPalette() {
        let canon: [(StatisticsViewModel.DayStatus, UInt32)] = [
            (.woke, 0x5EEAB8), (.light, 0xFFD479), (.heavy, 0xFFB4A8)
        ]
        for (status, expected) in canon {
            XCTAssertEqual(
                hex(StatisticsHeatmapView.toneColor(for: status).resolved(.dark)), expected,
                "\(status) drifted from the dark canon"
            )
        }
    }

    // MARK: - Helpers

    private func gradientStops(
        _ status: StatisticsViewModel.DayStatus,
        _ style: UIUserInterfaceStyle
    ) -> [UIColor] {
        var result: [UIColor] = []
        // The stops are CGColors baked by `SPSupport` from dynamic tokens —
        // they resolve against whatever traits are current, so make ours current.
        UITraitCollection(userInterfaceStyle: style).performAsCurrent {
            result = (StatisticsHeatmapView.gradientStops(for: status)?.colors ?? [])
                .map { UIColor(cgColor: $0) }
        }
        return result
    }

    /// Middle stop — what the eye reads as "the colour of the cell".
    private func midStop(
        _ status: StatisticsViewModel.DayStatus,
        _ style: UIUserInterfaceStyle
    ) -> UIColor {
        let stops = gradientStops(status, style)
        return stops.count == 3 ? stops[1] : .clear
    }

    private func pairs<T>(_ items: [T]) -> [(T, T)] {
        var result: [(T, T)] = []
        for first in 0..<items.count {
            for second in (first + 1)..<items.count {
                result.append((items[first], items[second]))
            }
        }
        return result
    }

    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private struct Lab {
        let lightness: CGFloat
        let greenRed: CGFloat
        let blueYellow: CGFloat
    }

    /// Composite a translucent colour onto an opaque one.
    private func flatten(_ color: UIColor, over background: UIColor) -> UIColor {
        let top = components(color), bottom = components(background)
        return UIColor(
            red: top.red * top.alpha + bottom.red * (1 - top.alpha),
            green: top.green * top.alpha + bottom.green * (1 - top.alpha),
            blue: top.blue * top.alpha + bottom.blue * (1 - top.alpha),
            alpha: 1
        )
    }

    private func components(_ color: UIColor) -> RGBA {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// CIE ΔE*ab (1976). Coarser than ΔE00 but monotonic and short enough to
    /// live in a test; every threshold above is set well clear of the ~2.3
    /// just-noticeable difference.
    private func deltaE(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = lab(lhs), second = lab(rhs)
        return sqrt(
            pow(first.lightness - second.lightness, 2)
                + pow(first.greenRed - second.greenRed, 2)
                + pow(first.blueYellow - second.blueYellow, 2)
        )
    }

    private func lab(_ color: UIColor) -> Lab {
        let rgba = components(color)
        let linear = [rgba.red, rgba.green, rgba.blue].map { value -> CGFloat in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        // sRGB D65 → XYZ, then XYZ → L*a*b* against the D65 white point.
        let capX = (linear[0] * 0.4124564 + linear[1] * 0.3575761 + linear[2] * 0.1804375) / 0.95047
        let capY = linear[0] * 0.2126729 + linear[1] * 0.7151522 + linear[2] * 0.0721750
        let capZ = (linear[0] * 0.0193339 + linear[1] * 0.1191920 + linear[2] * 0.9503041) / 1.08883
        func pivot(_ value: CGFloat) -> CGFloat {
            value > 216.0 / 24389.0 ? pow(value, 1.0 / 3.0) : (841.0 / 108.0) * value + 4.0 / 29.0
        }
        let pivoted = [pivot(capX), pivot(capY), pivot(capZ)]
        return Lab(
            lightness: 116 * pivoted[1] - 16,
            greenRed: 500 * (pivoted[0] - pivoted[1]),
            blueYellow: 200 * (pivoted[1] - pivoted[2])
        )
    }

    /// WCAG 2.1 relative luminance + contrast, same recipe as
    /// `AppColorsContrastTests`.
    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let first = luminance(lhs), second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        let rgba = components(color)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgba.red) + 0.7152 * channel(rgba.green) + 0.0722 * channel(rgba.blue)
    }

    private func hex(_ color: UIColor) -> UInt32 {
        let rgba = components(color)
        let toByte: (CGFloat) -> UInt32 = { UInt32(min(max(($0 * 255).rounded(), 0), 255)) }
        return (toByte(rgba.red) << 16) | (toByte(rgba.green) << 8) | toByte(rgba.blue)
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private func name(_ style: UIUserInterfaceStyle) -> String {
        style == .light ? "light" : "dark"
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}
