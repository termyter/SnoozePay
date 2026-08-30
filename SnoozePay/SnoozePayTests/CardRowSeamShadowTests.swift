import UIKit
import XCTest
@testable import SnoozePay

/// One corner of a card row, and a point just inside it in the path's own
/// coordinates. Whether that point is filled is the whole question: a square
/// corner fills it, a corner rounded by `AppRadius.sm` does not.
private struct CornerProbe {
    enum Side { case topLeft, topRight, bottomLeft, bottomRight }
    let side: Side
    let point: CGPoint
}

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

    /// The key stop is the other half of the fix, and it is not a mask: a
    /// shadow is cast around whatever path it is given, so the only way to
    /// stop a `.first` row shadowing along the seam is to give the key stop
    /// the row's real, part-square outline.
    ///
    /// A square corner contains the point just inside it; a corner rounded by
    /// `AppRadius.sm` does not. `assertCornerIsSquare` proves the second half
    /// on a control path every time, so the probe cannot quietly go green if
    /// the radius ever shrinks below the inset.
    func testKeyShadowPath_isSquareOnEveryEdgeTheRowShares() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (position, squareSides) in Self.squareSidesByPosition {
                let row = laidOutRow(position: position, style: style)
                let path = try XCTUnwrap(
                    row.layer.shadowPath,
                    "\(position) in \(style.rawValue) should carry a key stop path"
                )
                for corner in Self.corners(of: row.bounds) {
                    let isSquare = squareSides.contains(corner.side)
                    assertCorner(
                        corner, of: path, isSquare: isSquare,
                        context: "\(position) key stop, style \(style.rawValue)"
                    )
                }
            }
        }
    }

    /// `.single` is the position with no seam at all — every corner rounds,
    /// and nothing about the fix may change that. Without this the
    /// `.allCorners` case rests on two independent literals happening to agree.
    func testASingleRow_roundsAllFourCornersInBothStops() throws {
        let row = laidOutRow(position: .single, style: .light)
        let key = try XCTUnwrap(row.layer.shadowPath)
        for corner in Self.corners(of: row.bounds) {
            assertCorner(corner, of: key, isSquare: false, context: ".single key stop")
        }

        let ambient = try XCTUnwrap(ambientLayer(of: row))
        let mask = try XCTUnwrap((ambient.mask as? CAShapeLayer)?.path)
        let spread = AppShadow.ambientShadow1Spread
        XCTAssertTrue(
            mask.contains(
                CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.maxY + 2),
                using: .evenOdd
            ),
            ".single shares no edge, so the halo belongs on all four sides"
        )
    }

    /// The seam fix opens the top and bottom edges. The sides are the section's
    /// own edges on every position, and the halo has to survive there — a
    /// `grown(by:on:)` that leaked into `.left`/`.right` would erase it.
    func testTheHaloSurvivesOnTheSidesOfEveryPosition() throws {
        for position in [CardRowPosition.first, .last, .single] {
            let row = laidOutRow(position: position, style: .light)
            let ambient = try XCTUnwrap(ambientLayer(of: row))
            let mask = try XCTUnwrap((ambient.mask as? CAShapeLayer)?.path)
            let spread = AppShadow.ambientShadow1Spread
            let probes = [(spread - 2, "left"), (spread + row.bounds.maxX + 2, "right")]
            for (outside, side) in probes {
                XCTAssertTrue(
                    mask.contains(
                        CGPoint(x: outside, y: spread + row.bounds.midY), using: .evenOdd
                    ),
                    "\(position)'s \(side) edge is the card's own edge — the halo belongs there"
                )
            }
        }
    }

    /// `CACornerMask` and `UIRectCorner` name the same four corners, but the
    /// two enumerations are unrelated bit sets and a left↔right swap in the
    /// translation is invisible on a symmetric row. Asked corner by corner.
    func testTheCornerTranslationKeepsEachCornerWhereItWas() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let pairs: [(CACornerMask, CornerProbe.Side)] = [
            (.layerMinXMinYCorner, .topLeft),
            (.layerMaxXMinYCorner, .topRight),
            (.layerMinXMaxYCorner, .bottomLeft),
            (.layerMaxXMaxYCorner, .bottomRight)
        ]
        for (mask, rounded) in pairs {
            let path = AppShadow.cardPath(rect, cornerRadius: AppRadius.sm, corners: mask)
            for corner in Self.corners(of: rect) {
                assertCorner(
                    corner, of: path, isSquare: corner.side != rounded,
                    context: "cardPath asked to round \(rounded) only"
                )
            }
        }
    }

    /// `grown(by:on:)` is a plain geometry helper and the seam fix only ever
    /// asks it for vertical edges. Held on all four so the horizontal pair is
    /// correct rather than merely unused.
    func testGrowingARectMovesOnlyTheNamedEdges() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(rect.grown(by: 8, on: []), rect)
        XCTAssertEqual(rect.grown(by: 8, on: .top), CGRect(x: 10, y: 12, width: 100, height: 58))
        XCTAssertEqual(rect.grown(by: 8, on: .bottom), CGRect(x: 10, y: 20, width: 100, height: 58))
        XCTAssertEqual(rect.grown(by: 8, on: .left), CGRect(x: 2, y: 20, width: 108, height: 50))
        XCTAssertEqual(rect.grown(by: 8, on: .right), CGRect(x: 10, y: 20, width: 108, height: 50))
        XCTAssertEqual(
            rect.grown(by: 8, on: [.top, .bottom]),
            CGRect(x: 10, y: 12, width: 100, height: 66)
        )
    }

    /// A row shorter than two radii cannot ask for a corner bigger than itself.
    func testCardPathClampsARadiusBiggerThanTheRow() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 10)
        let path = AppShadow.cardPath(rect, cornerRadius: 999)
        XCTAssertEqual(path.boundingBoxOfPath.height, rect.height, accuracy: 0.01)
        XCTAssertEqual(path.boundingBoxOfPath.width, rect.width, accuracy: 0.01)
    }

    /// `.middle` is the one position that casts nothing: both its edges are
    /// seams, so a shadow there could only fall on a neighbour's surface.
    ///
    /// Stated as its own test because it is what makes `.middle` absent from
    /// the matrices above — and because `CardRowPosition.middle.openEdges`
    /// answers `[.top, .bottom]` for a caller that never arrives. That mapping
    /// is kept correct rather than removed; this test is why it is unused.
    func testAMiddleRow_castsNeitherStop() {
        let row = laidOutRow(position: .middle, style: .light)
        XCTAssertNil(row.layer.shadowPath, ".middle has no silhouette to cast")
        XCTAssertEqual(row.layer.shadowOpacity, 0, ".middle must not cast the key stop")
        XCTAssertNil(ambientLayer(of: row), ".middle must not carry the ambient stop either")
    }

    // MARK: - Corner probes

    /// How far inside a corner the probe sits. Small enough that a corner
    /// rounded by `AppRadius.sm` clears it, large enough to survive rasterising
    /// error — and `assertCorner` proves the first half rather than assuming it.
    private static let cornerInset: CGFloat = 2

    private static let squareSidesByPosition: [(CardRowPosition, Set<CornerProbe.Side>)] = [
        (.first, [.bottomLeft, .bottomRight]),
        (.last, [.topLeft, .topRight]),
        (.single, [])
    ]

    private static func corners(of rect: CGRect) -> [CornerProbe] {
        let inset = cornerInset
        return [
            CornerProbe(side: .topLeft, point: CGPoint(x: rect.minX + inset, y: rect.minY + inset)),
            CornerProbe(side: .topRight, point: CGPoint(x: rect.maxX - inset, y: rect.minY + inset)),
            CornerProbe(
                side: .bottomLeft, point: CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
            ),
            CornerProbe(
                side: .bottomRight, point: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
            )
        ]
    }

    /// Ask whether `path` fills the point just inside one corner.
    ///
    /// When the corner is expected to be ROUNDED the probe only means something
    /// if `AppRadius.sm` is actually big enough to clear `cornerInset`; a
    /// shrinking radius would otherwise turn this assertion green without
    /// anyone touching it. So the rounded case is stated as a difference from
    /// the square control, not as a bare `XCTAssertFalse`.
    private func assertCorner(
        _ corner: CornerProbe,
        of path: CGPath,
        isSquare: Bool,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let filled = path.contains(corner.point, using: .evenOdd)
        if isSquare {
            XCTAssertTrue(
                filled,
                "\(context): \(corner.side) is square, so the path must fill its corner",
                file: file, line: line
            )
            return
        }
        let square = CGPath(rect: path.boundingBoxOfPath, transform: nil)
        XCTAssertTrue(
            square.contains(corner.point, using: .evenOdd),
            """
            \(context): the probe for \(corner.side) fell outside the row itself — \
            the inset is wrong, and the assertion below would pass for the wrong reason
            """,
            file: file, line: line
        )
        XCTAssertFalse(
            filled,
            """
            \(context): \(corner.side) is rounded by \(AppRadius.sm)pt, so the path \
            must not fill a point \(Self.cornerInset)pt inside it
            """,
            file: file, line: line
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
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        window.makeKeyAndVisible()
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
