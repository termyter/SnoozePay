import UIKit
import XCTest
@testable import SnoozePay

/// Rendering-level tests for the balance gradient mask (#407).
///
/// `SPBalanceCardGradientMaskTests` pins the pure geometry of
/// `effectiveFontScale`, but that helper is only a *mirror* of UIKit's own
/// `adjustsFontSizeToFitWidth` shrink — a mirror can drift without any unit
/// test noticing, because nothing there rasterises a live label. The #397 bug
/// looked exactly like that: the scale maths was fine in isolation, yet the
/// mask was drawn at the unshrunk 56pt size and the right-hand digits / `₽`
/// fell outside the label box.
///
/// So these tests rasterise the mask for real and measure its **ink** (the
/// non-transparent pixels). That is the class of defect the geometry tests
/// cannot see.
///
/// ## Why the oracle is not "match a plain UILabel"
///
/// The obvious reference — render a plain `UILabel` with the same text and
/// shrink settings and demand the mask match it pixel-for-pixel — was tried
/// first and is **wrong**. Measured on the CI simulator with the 1 234 567 ₽
/// fixture in a 292pt box (natural width 343.8pt):
///
/// | | ink maxX | ink height | effective scale |
/// |---|---|---|---|
/// | mask (`effectiveFontScale`) | 290.3 | 36.0 | 0.849 |
/// | plain `UILabel` | 267.0 | 33.3 | ~0.786 |
///
/// Both paint the *whole* string — a digits-only control measures 237.7pt, so
/// the `₽` is present on both sides and nothing is being dropped. UIKit simply
/// quantises its own shrink and lands well below the scale that would fit,
/// leaving ~28pt of the box unused. That quantisation is undocumented and has
/// no stability guarantee across OS versions, so pinning the mask to it would
/// make this file fail on an OS update while the product is fine.
///
/// It also does not matter visually: `applyGradientMask` sets `textColor` to
/// `.clear`, so the mask *is* what the user sees — there is no second
/// rendering for it to disagree with.
///
/// What actually matters is the #397 contract, and that is what is asserted
/// below: the mask never spills past `textBounds`, it carries the *entire*
/// string when the fitting scale is above `minimumScaleFactor`, and it clamps
/// at the floor (clipping, exactly like UIKit) rather than shrinking forever.
final class SPBalanceMaskRenderingTests: XCTestCase {

    // MARK: - Fixtures

    /// The widest realistic balance — the string that overflows `moneyXl` on a
    /// narrow device and therefore exercises the shrink path.
    private var wideBalance: NSAttributedString {
        MoneyFormatter.attributed(1_234_567, digitsFont: AppTypography.moneyXl)
    }

    /// Build the balance-card value label in isolation, configured exactly like
    /// `SPBalanceCard.valueLabel`, laid out at `width`.
    private func makeGradientLabel(width: CGFloat) -> SPGradientTextLabel {
        let label = SPGradientTextLabel(
            colors: SPSupport.moneyGradientColors,
            locations: SPSupport.moneyGradientLocations,
            startPoint: SPSupport.gradientStart,
            endPoint: SPSupport.gradientEnd
        )
        label.font = AppTypography.moneyXl
        label.textColor = AppColors.fg1
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.attributedText = wideBalance
        label.frame = CGRect(x: 0, y: 0, width: width, height: 60)
        label.setNeedsLayout()
        label.layoutIfNeeded()
        return label
    }

    /// The same label given all the room it needs, so no shrink happens. Its
    /// ink is the unit-scale reference every shrunk measurement is compared
    /// against.
    private func makeUnshrunkLabel() -> SPGradientTextLabel {
        makeGradientLabel(width: (wideBalance.size().width * 2).rounded())
    }

    // MARK: - Tests

    func testMaskInk_staysInsideTextBoundsWhenShrunk() {
        // A width that needs ~0.85x to fit — above the 0.75 floor, so UIKit
        // shrinks rather than clips and the mask must follow it down.
        let width = (wideBalance.size().width * 0.85).rounded()
        let label = makeGradientLabel(width: width)

        guard let ink = maskInkBounds(of: label) else {
            return XCTFail("gradient mask rendered no glyphs")
        }

        XCTAssertGreaterThanOrEqual(ink.minX, -0.5, "mask ink starts inside the label box")
        XCTAssertLessThanOrEqual(
            ink.maxX, label.bounds.width + 0.5,
            "mask ink must not extend past textBounds — the right-hand digits / ₽ would be cut (#397)"
        )
        XCTAssertGreaterThanOrEqual(ink.minY, -0.5, "mask ink starts inside the label box")
        XCTAssertLessThanOrEqual(ink.maxY, label.bounds.height + 0.5, "mask ink fits vertically")
    }

    func testMaskInk_carriesTheWholeStringScaledDownWhenItFits() {
        // 0.85x is above the 0.75 floor, so the mask must *scale* the whole
        // amount down. The #397 bug drew it at the unshrunk 56pt instead, which
        // pushed the trailing digits and the ₽ outside the label box.
        let width = (wideBalance.size().width * 0.85).rounded()
        let expected = SPBalanceCard.effectiveFontScale(
            for: NSMutableAttributedString(attributedString: wideBalance),
            fitting: width,
            minimumScaleFactor: 0.75
        )

        guard let shrunk = maskInkBounds(of: makeGradientLabel(width: width)),
              let unshrunk = maskInkBounds(of: makeUnshrunkLabel()) else {
            return XCTFail("gradient mask rendered no glyphs")
        }

        XCTAssertLessThanOrEqual(
            shrunk.maxX, width + 0.5,
            "mask ink must not extend past textBounds — the right-hand digits / ₽ would be cut (#397)"
        )
        // A uniformly scaled copy of the full-size ink means every glyph
        // survived: had the tail been clipped, the width ratio would collapse
        // while the height ratio stayed at 1.
        XCTAssertEqual(shrunk.width / unshrunk.width, expected, accuracy: 0.03,
                       "whole string present, scaled to fit — not clipped")
        XCTAssertEqual(shrunk.height / unshrunk.height, expected, accuracy: 0.03,
                       "glyphs rasterised at the shrunk size, not the 56pt original")
    }

    func testMaskInk_clampsAtTheMinimumScaleFactorAndClips() {
        // Half the natural width needs ~0.5x, below the 0.75 floor. UIKit stops
        // shrinking at the floor and clips the overflow; the mask has to do the
        // same. A mask that kept scaling would render the amount at a size
        // UIKit never uses — and a money figure at the wrong size next to
        // correctly-sized copy reads as a rendering glitch.
        let width = (wideBalance.size().width * 0.5).rounded()

        guard let clipped = maskInkBounds(of: makeGradientLabel(width: width)),
              let unshrunk = maskInkBounds(of: makeUnshrunkLabel()) else {
            return XCTFail("gradient mask rendered no glyphs")
        }

        XCTAssertLessThanOrEqual(clipped.maxX, width + 0.5, "clipped mask stays in bounds")
        XCTAssertEqual(clipped.height / unshrunk.height, 0.75, accuracy: 0.03,
                       "shrink stops at minimumScaleFactor instead of continuing down")
        // 0.75 of the natural width still overflows a half-width box, so the
        // ink has to run to the edge — that is the clip.
        XCTAssertGreaterThan(clipped.width, width * 0.9,
                             "overflow is clipped at the box edge, not scaled away")
    }

    func testBalanceCard_maskInkStaysInsideValueLabelOnNarrowCard() {
        // Same check through the real card, so the label's configuration (and
        // not just this file's copy of it) is what gets verified.
        let cardWidth = (wideBalance.size().width * 0.85).rounded() + 40   // 20pt side padding
        let card = SPBalanceCard(balance: 1_234_567)
        card.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 180)
        card.setNeedsLayout()
        card.layoutIfNeeded()

        guard let label = findGradientLabel(in: card) else {
            return XCTFail("balance card has no gradient label")
        }
        guard let ink = maskInkBounds(of: label) else {
            return XCTFail("gradient mask rendered no glyphs")
        }

        XCTAssertGreaterThan(ink.width, 0, "mask must contain the rendered amount")
        XCTAssertLessThanOrEqual(
            ink.maxX, label.bounds.width + 0.5,
            "balance mask must not spill past the value label on a narrow card"
        )
    }

    // MARK: - Helpers

    /// Bounding box (in points, label-local) of the non-transparent pixels of
    /// the layer mask the gradient is clipped to.
    private func maskInkBounds(of label: UILabel) -> CGRect? {
        let gradients = (label.layer.sublayers ?? []).compactMap { $0 as? CAGradientLayer }
        // `CALayer.contents` is `Any?`; `as? CGImage` can't actually verify a
        // CoreFoundation type (the compiler warns it always succeeds), so check
        // the CF type id explicitly before downcasting.
        guard let contents = gradients.first?.mask?.contents else { return nil }
        let object = contents as AnyObject
        guard CFGetTypeID(object) == CGImage.typeID else { return nil }
        return inkBounds(of: unsafeDowncast(object, to: CGImage.self), in: label.bounds.size)
    }

    /// Scan the image's alpha channel and return the bounding box of everything
    /// that got painted, converted back into `size`'s point space.
    private func inkBounds(of image: CGImage, in size: CGSize) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return nil }

        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Ignore the antialiasing fringe so the box tracks solid glyph coverage.
        let threshold: UInt8 = 24
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in 0..<height {
            let offset = row * width
            for column in 0..<width where alpha[offset + column] > threshold {
                if column < minX { minX = column }
                if column > maxX { maxX = column }
                if row < minY { minY = row }
                if row > maxY { maxY = row }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let scaleX = CGFloat(width) / size.width
        let scaleY = CGFloat(height) / size.height
        return CGRect(
            x: CGFloat(minX) / scaleX,
            y: CGFloat(minY) / scaleY,
            width: CGFloat(maxX - minX + 1) / scaleX,
            height: CGFloat(maxY - minY + 1) / scaleY
        )
    }

    private func findGradientLabel(in view: UIView) -> SPGradientTextLabel? {
        if let label = view as? SPGradientTextLabel { return label }
        return view.subviews.lazy.compactMap(findGradientLabel(in:)).first
    }
}
