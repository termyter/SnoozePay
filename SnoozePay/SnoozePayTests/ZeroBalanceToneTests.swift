import XCTest
@testable import SnoozePay

/// The one zero, told the same way on both screens.
///
/// Before #634 the Wallet painted an empty balance with the money ramp — this
/// app's "you have money, it works" signal — while the alarms list, one tab
/// away, painted the same zero as a blocking state in red. Two screens gave
/// opposite readings of one number, and one of them had to be wrong.
final class ZeroBalanceToneTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    // MARK: - Which state the card thinks it is in

    func testZeroBalanceIsRecognisedAsEmpty() {
        XCTAssertTrue(SPBalanceCard(balance: 0).isZeroBalance)
    }

    func testPositiveBalanceIsNotEmpty() {
        XCTAssertFalse(SPBalanceCard(balance: 1).isZeroBalance)
        XCTAssertFalse(SPBalanceCard(balance: 840).isZeroBalance)
    }

    /// A negative balance is not "money you have" either. Nothing should be
    /// able to put a below-zero wallet back on the green ramp.
    func testNegativeBalanceIsTreatedAsEmpty() {
        XCTAssertTrue(SPBalanceCard(balance: -50).isZeroBalance)
    }

    // MARK: - The ink

    /// The point of the issue: at zero the two screens must name the state with
    /// the SAME token. `fgOnPainWash` is what `SPAlarmsListHeader.applyTone`
    /// gives its zero pill.
    func testZeroTakesTheSameInkAsTheAlarmsListPill() {
        for trait in [light, dark] {
            let expected = AppColors.fgOnPainWash.resolvedColor(with: trait).cgColor
            let stops = SPBalanceCard.valueColors(isZero: true, trait: trait)

            XCTAssertFalse(stops.isEmpty)
            for stop in stops {
                XCTAssertEqual(stop, expected,
                               "Zero must use the alarms-list zero ink, not a colour of its own")
            }
        }
    }

    /// Flat, not a ramp — every stop identical. A gradient here would reopen
    /// the contrast problem the flat token exists to avoid.
    func testZeroRendersFlatRatherThanAsARamp() {
        let stops = SPBalanceCard.valueColors(isZero: true, trait: light)
        let first = stops.first
        XCTAssertNotNil(first)
        XCTAssertTrue(stops.allSatisfy { $0 == first },
                      "Zero should paint flat: all gradient stops identical")
    }

    /// The acceptance criterion «отрицательный/положительный баланс не задет»:
    /// a wallet with money in it keeps the money ramp exactly as before.
    func testPositiveBalanceKeepsTheMoneyRamp() {
        for trait in [light, dark] {
            XCTAssertEqual(SPBalanceCard.valueColors(isZero: false, trait: trait),
                           SPSupport.moneyGradientColors(for: trait),
                           "A funded wallet must keep the untouched money gradient")
        }
    }

    // MARK: - Contrast

    /// `pain300` — the stop a naive pain RAMP would open on — measures 2.77:1
    /// against this near-white card, under the 3:1 large-text floor even at
    /// 56pt. The flat token has to clear that bar in both themes.
    func testZeroInkIsLegibleOnTheCardInBothThemes() {
        let cases: [(UITraitCollection, String)] = [(light, "light"), (dark, "dark")]
        for (trait, name) in cases {
            let ink = AppColors.fgOnPainWash.resolvedColor(with: trait)
            let card = AppColors.bg2.resolvedColor(with: trait)

            XCTAssertGreaterThanOrEqual(contrast(ink, card), 3.0,
                                        "Zero balance ink fails the large-text floor in \(name)")
        }
    }

    // MARK: - WCAG helpers

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let left = luminance(lhs)
        let right = luminance(rhs)
        return (max(left, right) + 0.05) / (min(left, right) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return 0
        }
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
