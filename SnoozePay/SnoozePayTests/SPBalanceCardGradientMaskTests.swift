import UIKit
import XCTest
@testable import SnoozePay

/// Tests for the balance-card gradient mask alignment under auto-shrink (#397).
///
/// `SPBalanceCard.valueLabel` shrinks wide balances via `adjustsFontSizeToFitWidth`,
/// but the gradient clip-mask is rendered from the attributed string whose font
/// is baked at 56pt `moneyXl`. Drawing 56pt glyphs into the shrunk bounds let the
/// right-hand digits / `₽` fall outside the mask. `effectiveFontScale` mirrors
/// UIKit's shrink heuristic so the mask re-fonts to the on-screen size — the pure
/// geometry is pinned here.
final class SPBalanceCardGradientMaskTests: XCTestCase {

    private func attributed(_ string: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: size)])
    }

    func testScale_isOneWhenTextFits() {
        let text = attributed("12 345 ₽", size: 56)
        let natural = text.size().width
        let scale = SPBalanceCard.effectiveFontScale(
            for: text, fitting: natural + 50, minimumScaleFactor: 0.75
        )
        XCTAssertEqual(scale, 1, "Text that already fits is not shrunk")
    }

    func testScale_isOneWhenExactlyFits() {
        let text = attributed("12 345 ₽", size: 56)
        let natural = text.size().width
        let scale = SPBalanceCard.effectiveFontScale(
            for: text, fitting: natural, minimumScaleFactor: 0.75
        )
        XCTAssertEqual(scale, 1, "Text at the exact width edge is not shrunk")
    }

    func testScale_shrinksProportionallyWhenTooWide() {
        let text = attributed("1 234 567 ₽", size: 56)
        let natural = text.size().width
        let available = natural * 0.85   // needs ~0.85x to fit, above the floor
        let scale = SPBalanceCard.effectiveFontScale(
            for: text, fitting: available, minimumScaleFactor: 0.75
        )
        XCTAssertEqual(scale, 0.85, accuracy: 0.001,
                       "Above the floor the scale tracks availableWidth / naturalWidth")
    }

    func testScale_clampsToMinimumScaleFactor() {
        let text = attributed("1 234 567 ₽", size: 56)
        let natural = text.size().width
        let available = natural * 0.5    // would need 0.5x, below the 0.75 floor
        let scale = SPBalanceCard.effectiveFontScale(
            for: text, fitting: available, minimumScaleFactor: 0.75
        )
        XCTAssertEqual(scale, 0.75, accuracy: 0.001,
                       "UIKit clamps at minimumScaleFactor and clips beyond it")
    }

    func testScale_isOneForZeroWidth() {
        let text = attributed("12 345 ₽", size: 56)
        XCTAssertEqual(
            SPBalanceCard.effectiveFontScale(
                for: text,
                fitting: 0,
                minimumScaleFactor: 0.75
            ),
            1, "Zero available width is a no-op (layout not resolved yet)"
        )
    }

    func testScaleFonts_multipliesEveryRunPointSize() {
        let combined = NSMutableAttributedString(
            string: "12 ", attributes: [.font: UIFont.systemFont(ofSize: 56)]
        )
        combined.append(NSAttributedString(string: "₽", attributes: [.font: UIFont.systemFont(ofSize: 40)]))

        SPBalanceCard.scaleFonts(in: combined, by: 0.5)

        var sizes: [CGFloat] = []
        combined.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: combined.length),
            options: []
        ) { value, _, _ in
            if let font = value as? UIFont { sizes.append(font.pointSize) }
        }
        XCTAssertEqual(sizes, [28, 20], "Each run keeps its own font, scaled uniformly")
    }

    func testScaleFonts_isNoopAtUnitScale() {
        let text = NSMutableAttributedString(string: "12 345 ₽", attributes: [.font: UIFont.systemFont(ofSize: 56)])
        SPBalanceCard.scaleFonts(in: text, by: 1)
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize, 56, "Unit scale leaves fonts untouched")
    }

    func testGradientMaskLandsAfterBalanceCardLayout() {
        let card = SPBalanceCard(balance: 1_234_567)
        card.frame = CGRect(x: 0, y: 0, width: 335, height: 180)
        card.setNeedsLayout()
        card.layoutIfNeeded()

        let valueLabel = findGradientLabel(in: card)
        XCTAssertNotNil(valueLabel)
        XCTAssertGreaterThan(valueLabel?.bounds.width ?? 0, 0)
        XCTAssertEqual(valueLabel?.textColor, .clear, "gradient mask must replace the fallback colour")

        let gradients = (valueLabel?.layer.sublayers ?? []).compactMap { $0 as? CAGradientLayer }
        XCTAssertEqual(gradients.count, 1)
        XCTAssertNotNil(gradients.first?.mask, "gradient must be clipped to the rendered glyphs")
        XCTAssertEqual(gradients.first?.frame.size, valueLabel?.bounds.size)
    }

    private func findGradientLabel(in view: UIView) -> SPGradientTextLabel? {
        if let label = view as? SPGradientTextLabel { return label }
        return view.subviews.lazy.compactMap(findGradientLabel(in:)).first
    }
}
