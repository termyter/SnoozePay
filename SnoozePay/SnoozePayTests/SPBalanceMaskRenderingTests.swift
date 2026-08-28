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
/// So these tests render the mask for real and compare its **ink** (the
/// non-transparent pixels) against what a plain `UILabel` with the same
/// configuration paints. Divergence between the two is precisely the class of
/// defect the geometry tests cannot see.
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

    /// A plain `UILabel` with the same text / shrink configuration — the
    /// reference for what UIKit actually puts on screen.
    private func makeControlLabel(width: CGFloat) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.moneyXl
        label.textColor = .black
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.attributedText = wideBalance
        label.frame = CGRect(x: 0, y: 0, width: width, height: 60)
        label.setNeedsLayout()
        label.layoutIfNeeded()
        return label
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

    func testMaskInk_matchesWhatUIKitPaintsWhenShrunk() {
        let width = (wideBalance.size().width * 0.85).rounded()
        let label = makeGradientLabel(width: width)
        let control = makeControlLabel(width: width)

        guard let masked = maskInkBounds(of: label),
              let painted = paintedInkBounds(of: control) else {
            return XCTFail("expected ink from both the mask and the reference label")
        }

        // Tolerance is wide enough to absorb rasterisation / hinting noise but
        // far below the ~40pt horizontal overhang (and ~8pt glyph-height delta)
        // an unshrunk mask produces.
        assertInkMatches(masked, painted, tolerance: 4)
    }

    func testMaskInk_matchesUIKitClippingBelowTheMinimumScaleFactor() {
        // Half the natural width: UIKit clamps the shrink at 0.75 and then
        // clips whatever still doesn't fit. The mask has to clip identically —
        // a mask that kept scaling past the floor would show glyphs UIKit
        // never draws.
        let width = (wideBalance.size().width * 0.5).rounded()
        let label = makeGradientLabel(width: width)
        let control = makeControlLabel(width: width)

        guard let masked = maskInkBounds(of: label),
              let painted = paintedInkBounds(of: control) else {
            return XCTFail("expected ink from both the mask and the reference label")
        }

        XCTAssertLessThanOrEqual(masked.maxX, label.bounds.width + 0.5, "clipped mask stays in bounds")
        assertInkMatches(masked, painted, tolerance: 4)
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

    /// TEMPORARY diagnostic (#407): dumps the geometry both sides measure so
    /// the CI log says *why* the mask and the control label disagree.
    func testDiagnostic_dumpGeometry() {
        let natural = wideBalance.size().width
        let width = (natural * 0.85).rounded()
        let label = makeGradientLabel(width: width)
        let control = makeControlLabel(width: width)

        // Same configuration, but digits only — no narrow space, no ₽.
        let digitsOnly = UILabel()
        digitsOnly.font = AppTypography.moneyXl
        digitsOnly.textColor = .black
        digitsOnly.numberOfLines = 1
        digitsOnly.adjustsFontSizeToFitWidth = true
        digitsOnly.minimumScaleFactor = 0.75
        digitsOnly.attributedText = NSAttributedString(
            string: MoneyFormatter.digits(1_234_567),
            attributes: [.font: AppTypography.moneyXl]
        )
        digitsOnly.frame = CGRect(x: 0, y: 0, width: width, height: 60)
        digitsOnly.layoutIfNeeded()

        let scale = SPBalanceCard.effectiveFontScale(
            for: NSMutableAttributedString(attributedString: wideBalance),
            fitting: width,
            minimumScaleFactor: 0.75
        )

        XCTFail("""
        DIAG natural=\(natural) width=\(width) maskScale=\(scale)
        DIAG masked=\(String(describing: maskInkBounds(of: label)))
        DIAG painted=\(String(describing: paintedInkBounds(of: control)))
        DIAG digitsOnly=\(String(describing: paintedInkBounds(of: digitsOnly)))
        DIAG controlLineBreak=\(control.lineBreakMode.rawValue)
        """)
    }

    // MARK: - Helpers

    private func assertInkMatches(
        _ masked: CGRect,
        _ painted: CGRect,
        tolerance: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(masked.minX, painted.minX, accuracy: tolerance,
                       "mask starts where UIKit starts painting", file: file, line: line)
        XCTAssertEqual(masked.maxX, painted.maxX, accuracy: tolerance,
                       "mask ends where UIKit stops painting", file: file, line: line)
        XCTAssertEqual(masked.height, painted.height, accuracy: tolerance,
                       "mask glyphs are rendered at the size UIKit shrunk to", file: file, line: line)
    }

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

    /// Bounding box (in points) of what the reference label actually paints.
    private func paintedInkBounds(of view: UIView) -> CGRect? {
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage else { return nil }
        return inkBounds(of: cgImage, in: view.bounds.size)
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
