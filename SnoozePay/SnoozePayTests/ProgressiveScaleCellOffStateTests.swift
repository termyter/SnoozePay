import XCTest
@testable import SnoozePay

/// The «Прогрессивный режим» card switched OFF keeps its texture (#688).
///
/// It used to hide the `50 → 100 → 200 → 400 ₽` chain and grey the flame, so
/// the disarmed card was a title and a switch. Now the chain stays, muted to
/// neutral ink and spoken with a «Выключено» prefix (one off signal, no
/// `.notEnabled` trait — #1113), and the flame stays
/// pain-tinted at the app's disabled alpha. These tests pin the on/off mapping
/// in both directions, through `configure` and through the switch itself.
@MainActor
final class ProgressiveScaleCellOffStateTests: XCTestCase {

    private let spokenChain = "1-е: 50 ₽ → 2-е: 100 ₽ → 3-е: 200 ₽ → 4-е: 400 ₽"

    func testOffKeepsTheChainVisibleButMutedAndMarkedOff() throws {
        let cell = makeCell(isOn: false)
        let chain = try chainLabel(in: cell)

        XCTAssertFalse(chain.isHidden, "the off card must keep its chain")
        XCTAssertEqual(chain.attributedText?.string.hasPrefix("50 → 100 → 200 → "), true)
        XCTAssertEqual(
            Set(inkHexes(of: chain)),
            [hex(AppColors.fg3), hex(AppColors.fg4)],
            "off: every step fg3, arrows fg4 — no warn or pain ink"
        )
        XCTAssertFalse(chain.isUserInteractionEnabled)
        XCTAssertEqual(chain.accessibilityTraits, .staticText, "off is said once, by the label (#1113)")
        XCTAssertEqual(
            chain.accessibilityLabel,
            Localized.format("create_alarm.progressive.chain_off_accessibility", spokenChain)
        )
        XCTAssertNotEqual(chain.accessibilityLabel, spokenChain, "VoiceOver must hear that the rule is off")
    }

    func testOnPaintsTheChainInWarnAndPainAndSpeaksItPlain() throws {
        let cell = makeCell(isOn: true)
        let chain = try chainLabel(in: cell)

        XCTAssertFalse(chain.isHidden)
        let inks = Set(inkHexes(of: chain))
        XCTAssertTrue(inks.contains(hex(AppColors.warn400)))
        XCTAssertTrue(inks.contains(hex(AppColors.pain400)))
        XCTAssertFalse(inks.contains(hex(AppColors.fg3)), "on: no step may stay muted")
        XCTAssertEqual(chain.accessibilityTraits, .staticText)
        XCTAssertEqual(chain.accessibilityLabel, spokenChain)
    }

    func testFlameStaysPresentWhenOffAndFullWhenOn() throws {
        let off = try flame(in: makeCell(isOn: false))
        XCTAssertFalse(off.isHidden)
        XCTAssertEqual(hex(off.tintColor), hex(AppColors.pain400), "off but present: still the flame's colour")
        XCTAssertEqual(off.alpha, ProgressiveScaleCell.disabledFlameAlpha, accuracy: 0.001)
        XCTAssertLessThan(off.alpha, 1)
        XCTAssertGreaterThan(off.alpha, 0)

        let armed = try flame(in: makeCell(isOn: true))
        XCTAssertEqual(hex(armed.tintColor), hex(AppColors.pain400))
        XCTAssertEqual(armed.alpha, 1, accuracy: 0.001)
    }

    /// The switch repaints in place, both ways, without a re-`configure`.
    func testTogglingFlipsTheMappingBothWays() throws {
        let cell = makeCell(isOn: true)
        let toggle = try XCTUnwrap(descendants(SPSwitch.self, in: cell).first)
        var reported: [Bool] = []
        cell.onToggled = { reported.append($0) }

        toggle.isOn = false
        toggle.sendActions(for: .valueChanged)
        var chain = try chainLabel(in: cell)
        XCTAssertFalse(chain.isHidden)
        XCTAssertEqual(chain.accessibilityTraits, .staticText)
        XCTAssertEqual(
            chain.accessibilityLabel,
            Localized.format("create_alarm.progressive.chain_off_accessibility", spokenChain)
        )
        XCTAssertFalse(Set(inkHexes(of: chain)).contains(hex(AppColors.pain400)))
        XCTAssertEqual(try flame(in: cell).alpha, ProgressiveScaleCell.disabledFlameAlpha, accuracy: 0.001)

        toggle.isOn = true
        toggle.sendActions(for: .valueChanged)
        chain = try chainLabel(in: cell)
        XCTAssertEqual(chain.accessibilityTraits, .staticText)
        XCTAssertTrue(Set(inkHexes(of: chain)).contains(hex(AppColors.pain400)))
        XCTAssertEqual(chain.accessibilityLabel, spokenChain)
        XCTAssertEqual(try flame(in: cell).alpha, 1, accuracy: 0.001)
        XCTAssertEqual(reported, [false, true])
    }

    // MARK: - Helpers

    private func makeCell(isOn: Bool) -> ProgressiveScaleCell {
        let cell = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        cell.configure(isOn: isOn, chain: [50, 100, 200, 400], currency: .rub, accessibilityChain: spokenChain)
        return cell
    }

    private func chainLabel(in cell: UIView) throws -> UILabel {
        try XCTUnwrap(descendants(UILabel.self, in: cell).first { $0.attributedText?.string.contains(" → ") == true })
    }

    /// The flame is the only image view outside the switch.
    private func flame(in cell: UIView) throws -> UIImageView {
        let switches = descendants(SPSwitch.self, in: cell)
        return try XCTUnwrap(descendants(UIImageView.self, in: cell).first { image in
            !switches.contains { image.isDescendant(of: $0) }
        })
    }

    private func inkHexes(of label: UILabel) -> [String] {
        guard let text = label.attributedText else { return [] }
        var inks: [String] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let color = value as? UIColor { inks.append(hex(color)) }
        }
        return inks
    }

    private func descendants<T: UIView>(_ type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T { found.append(match) }
            found.append(contentsOf: descendants(type, in: subview))
        }
        return found
    }

    /// Light and dark hexes together, so a mismatch in either theme shows.
    private func hex(_ color: UIColor) -> String {
        [UIUserInterfaceStyle.light, .dark].map { style -> String in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(
                format: "%02X%02X%02X@%.2f",
                Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()), alpha
            )
        }.joined(separator: "/")
    }
}
