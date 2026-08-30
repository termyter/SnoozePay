import UIKit
import XCTest
@testable import SnoozePay

/// The ambient shadow stop at the seam between two card rows (#674).
///
/// #515 masked that stop out of the card's MIDDLE and stopped the section
/// reading as striped. It left the two corners a cap row does not round: the
/// halo's hole was still cut as a fully rounded rect, so on a `.first` row the
/// little triangles at the two SQUARE bottom corners fell outside the hole,
/// inside the visible part of the mask. The stop's interior — `#F0F1F2` over
/// `bg1` — printed into exactly those triangles, which sit in the seam between
/// two rows.
///
/// Measured on a light 3× screenshot before the fix, scanning the left rail of
/// the Звук/Тема/Вибрация card for the first pure-white pixel per row:
///
///     y=1248…1306   x=61        straight rail
///     y=1307…1324   x 61 → 71   Звук/Тема seam, 10 px of wash
///     y=1325…1497   x=61
///     y=1498…1509   x 66 → 61   Тема/Вибрация seam, 5 px
///
/// A soft gradient rather than a hard edge, i.e. decoration painted over a
/// continuous fill — not a gap in the fill. What the eye makes of it is "every
/// row is rounded", which is how the PM reported it.
///
/// These assertions are on the mask path, so they are exact and cheap. The
/// rendered counterpart lives in `CardRowBandingTests`, next to the render
/// probe it needs.
@MainActor
final class CardRowSeamShadowTests: XCTestCase {

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    /// #515 masked the ambient stop out of the card's MIDDLE. It left the two
    /// corners a cap row does not round.
    ///
    /// A `.first` row is square at the bottom, but the halo's hole was cut as a
    /// fully rounded rect, so the two little triangles at the bottom corners
    /// fell outside the hole — inside the visible part of the mask. The stop's
    /// interior printed there, in the seam between two rows, and the section
    /// read as if every row were separately rounded.
    func testAmbientStop_isMaskedOutOfTheCornersACapRowDoesNotRound() throws {
        let cases: [(CardRowPosition, String)] = [
            (.first, "bottom"),
            (.last, "top")
        ]
        for (position, squareSide) in cases {
            let row = laidOutRow(position: position, style: .light)
            let ambient = try XCTUnwrap(ambientLayer(of: row), "\(position) should carry the stop")
            let mask = try XCTUnwrap(ambient.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            let spread = AppShadow.ambientShadow1Spread
            let inset: CGFloat = 2

            let y = squareSide == "bottom"
                ? spread + row.bounds.maxY - inset
                : spread + row.bounds.minY + inset
            for (x, side) in [(spread + inset, "left"), (spread + row.bounds.maxX - inset, "right")] {
                XCTAssertFalse(
                    path.contains(CGPoint(x: x, y: y), using: .evenOdd),
                    """
                    \(position) is square at the \(squareSide), so its \(squareSide)-\(side) \
                    corner is the row's own opaque fill — the ambient stop must not \
                    composite there
                    """
                )
            }
        }
    }

    /// The seam itself: a cap row must not emit its halo across the edge it
    /// shares with the next row, because the surface on that side is the
    /// neighbour's `bg1`, not the page.
    func testAmbientStop_emitsNoHaloAcrossTheSeam() throws {
        let row = laidOutRow(position: .first, style: .light)
        let ambient = try XCTUnwrap(ambientLayer(of: row))
        let mask = try XCTUnwrap(ambient.mask as? CAShapeLayer)
        let path = try XCTUnwrap(mask.path)
        let spread = AppShadow.ambientShadow1Spread

        XCTAssertFalse(
            path.contains(
                CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.maxY + 2),
                using: .evenOdd
            ),
            "a .first row's bottom edge is a seam, not a card edge — nothing to halo"
        )
        XCTAssertTrue(
            path.contains(
                CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.minY - 2),
                using: .evenOdd
            ),
            "…but the top IS the section's edge, and the halo there is the point of the stop"
        )
    }

    // MARK: - Fixtures

    private func laidOutRow(
        position: CardRowPosition,
        style: UIUserInterfaceStyle
    ) -> CardRowBackgroundView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 343, height: 52))
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = AppColors.bg0
        window.isHidden = false
        hostWindows.append(window)

        let row = CardRowBackgroundView(position: position, cornerRadius: AppRadius.sm)
        row.frame = window.bounds
        window.addSubview(row)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return row
    }

    private func ambientLayer(of row: UIView) -> CAShapeLayer? {
        row.layer.sublayers?
            .first { $0.name == AppShadow.ambientShadow1LayerName } as? CAShapeLayer
    }
}
