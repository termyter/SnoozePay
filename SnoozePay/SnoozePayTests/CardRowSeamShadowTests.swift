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
/// These assertions are path-level — some on the ambient mask, some on the
/// key stop's `shadowPath` — so they are exact and cheap. The
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
    ///
    /// The hole is cut by two independent arguments — `corners` and
    /// `openEdges` — and this is the test that holds the first, in both
    /// directions: the corners a cap row squares must stay square, and the ones
    /// it rounds must stay rounded. Only the square half is #692; the rounded
    /// half was uncovered too, and without it `corners: []` at the call site
    /// passed the entire suite while the section lost the halo on its outer
    /// corners.
    ///
    /// `testAmbientStop_emitsNoHaloAcrossTheSeam` holds `openEdges`, so both
    /// probes here are deliberately placed where `openEdges` cannot decide the
    /// answer for them — otherwise this test would be a copy of that one rather
    /// than cover for the half nothing else holds. See the comment at the
    /// grown-corner probe for why that forces the coordinates to be measured
    /// rather than written down.
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

            let hole = try XCTUnwrap(ambient.path).boundingBoxOfPath
            assertSilhouetteStillDescribesTheRow(hole, of: row, spread: spread, context: "\(position)")
            assertGrownHoleCorners(hole, in: path, of: row, position: position)
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

    /// The key stop's path is the other half of the change, and — unlike the
    /// ambient mask — it changes no pixel today. A shadow is cast around
    /// whatever path it is given, so a `.first` row whose key stop is fully
    /// rounded does emit into the seam. Measured, reverting this line alone
    /// moves the rendered seam by 0/255 in both themes, and the reason is NOT
    /// the ambient mask: that mask lives on a sublayer and cannot clip the
    /// host layer's own shadow, and in dark the ambient layer is not installed
    /// at all (`AppShadow.swift:118-123`, held by
    /// `CardRowBandingTests.testDarkRows_carryNoAmbientStop`). The reason is
    /// the one written at `UIView+CardStyle.swift:255` — the corners this fixes
    /// sit where the two rows' own opaque fills already cover the difference.
    ///
    /// It is kept because the key stop should not describe a silhouette the
    /// layer does not have: the moment a row's fill stops covering that
    /// corner, an unfixed key stop starts printing there.
    ///
    /// A square corner contains the point just inside it; a corner rounded by
    /// `AppRadius.sm` does not. `assertCorner` proves the second half on a
    /// control path every time, so the probe cannot quietly go green if the
    /// radius ever shrinks below the inset.
    ///
    /// This is a PATH-level claim and nothing more. An earlier version of this
    /// comment said the theme loop below proved the change in dark too — it
    /// does not, and neither does it prove anything in light: nothing between
    /// `laidOutRow(style:)` and `shadowPath` reads the trait, so the two
    /// iterations execute identical code. The loop is kept only so a future
    /// theme-dependent silhouette cannot slip in unnoticed, and the rendered
    /// question is asked where it belongs — in
    /// `CardRowBandingTests.testTheSeamBetweenTwoRows_…`, which measured that
    /// reverting this very line moves the seam by nothing in either theme.
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

    /// Ask both directions of `corners` at the corners of the GROWN hole, for a
    /// `.first` or `.last` cap row.
    ///
    /// Inputs, so the numbers below stay re-derivable: the fixture row is
    /// 343×52, `ambientShadow1Spread` is 8, the radius is what the row was
    /// built with (`AppRadius.sm`, 12pt), and the probe inset is
    /// ``cornerInset``, 2pt. The radius is read off the row's layer rather than
    /// restated as a constant, because a control that assumes the radius cannot
    /// fail when the radius is the thing that moved: below ~6.8pt effective
    /// radius the real hole swallows the probe while a control on the stale
    /// 12pt still clears it, which is exactly the regression the control exists
    /// to catch. `AppShadow.cardPath` re-applies production's own clamp.
    ///
    /// Why the corners of the grown hole, and not a coordinate written down
    /// here. The probes in the ROW cannot see `corners` at all (#692):
    /// `openEdges` has already grown the hole 8pt past the seam, so on a
    /// `.first` row the bottom-left arc WOULD centre at (20, 56) — it is square
    /// as shipped — and even rounded it still swallows (10, 58), 10.2pt out
    /// against a 12pt radius. Both halves of #674 pass them.
    ///
    /// The grown corner separates the halves, and its extent is read off the
    /// production silhouette rather than recomputed, so a reverted `openEdges`
    /// moves the probe with it and these assertions stay green. That is the
    /// point, not an accident: a probe that also fired on an `openEdges` revert
    /// would be a second copy of `testAmbientStop_emitsNoHaloAcrossTheSeam`
    /// instead of cover for the half nothing else holds.
    ///
    /// No literal coordinate can do both. Staying inside the UNGROWN hole needs
    /// y ≤ 60, and there the region outside a 12pt arc is the sliver x < 8.69 —
    /// flush against the HOLE's own edge at x = 8, with the layer's edge 8pt
    /// further out at x = 0, so there is no room left for an inset.
    ///
    /// `cornerInset` in from both edges of the corner puts the probe
    /// √2·(radius − inset) = 14.1pt from the arc's centre, 2.1pt clear of a 12pt
    /// radius — which holds while inset < radius·(1 − 1/√2) = 3.5pt. The control
    /// asserts that every run instead of assuming it.
    private func assertGrownHoleCorners(
        _ hole: CGRect,
        in mask: CGPath,
        of row: UIView,
        position: CardRowPosition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let squareSide = position == .first ? "bottom" : "top"
        let roundedSide = position == .first ? "top" : "bottom"
        let inset = Self.cornerInset
        let radius = row.layer.cornerRadius
        let squareY = position == .first ? hole.maxY - inset : hole.minY + inset
        let roundedY = position == .first ? hole.minY + inset : hole.maxY - inset
        let ifRounded = AppShadow.cardPath(hole, cornerRadius: radius, corners: .allCorners)

        for (x, side) in [(hole.minX + inset, "left"), (hole.maxX - inset, "right")] {
            // The other direction, and the reason the square claim is not the
            // whole of `corners`: where the section DOES round, the triangle
            // outside the arc is the card's own outer corner and the halo
            // belongs there. Without this, `corners: []` at the call site passes
            // the entire suite while that halo disappears.
            let roundedProbe = CGPoint(x: x, y: roundedY)
            XCTAssertTrue(
                mask.contains(roundedProbe, using: .evenOdd),
                """
                \(position) rounds its \(roundedSide) — probe \(roundedProbe), hole \(hole), \
                radius \(radius)pt. Outside that arc is the section's own outer corner, so the \
                mask has to keep the halo there
                """,
                file: file, line: line
            )

            let probe = CGPoint(x: x, y: squareY)
            guard !ifRounded.contains(probe, using: .evenOdd) else {
                // Deliberately not `XCTAssertFalse` + fallthrough: a dead
                // control must not also print the claim below, whose stated
                // diagnosis would then be the wrong one.
                XCTFail(
                    """
                    control for \(position) \(squareSide)-\(side): probe \(probe) is inside hole \
                    \(hole) even when that hole is rounded by \(radius)pt, so the claim below \
                    would pass whatever `corners` did. Needs inset (\(inset)) < \
                    radius·(1 − 1/√2) = \(radius * (1 - 1 / CGFloat(2).squareRoot()))
                    """,
                    file: file, line: line
                )
                continue
            }
            XCTAssertFalse(
                mask.contains(probe, using: .evenOdd),
                """
                \(position) is square at the \(squareSide) — probe \(probe), hole \(hole), \
                radius \(radius)pt. The mask exposes that point, so the stop's interior \
                composites into the seam. Rounding \(squareSide)-\(side) is the likely cause, \
                but read the printed hole against the row's \(row.bounds.size) footprint first: \
                a silhouette that moved puts the probe somewhere else entirely
                """,
                file: file, line: line
            )
        }
    }

    /// Pin the oracle the grown-corner probes measure themselves against.
    ///
    /// Those probes take their coordinates from the ambient layer's own
    /// silhouette (`ambient.path`), which nothing else in this suite reads. An
    /// oracle free to move with the thing it measures proves nothing: shrink
    /// the silhouette alone — `AppShadow.swift:145`, the line the mask does NOT
    /// share, since `installHaloMask` recomputes the hole from `cardRect` — and
    /// probe and control slide inside the real hole together. The test stays
    /// green while the halo creeps in under the card.
    ///
    /// So the silhouette is held to two things it must be whatever `corners`
    /// and `openEdges` say: exactly as wide as the row plus the spread on each
    /// side, and never smaller than the row itself. `grown(by:on:)` only ever
    /// pushes a seam edge OUTWARD, so both survive `openEdges: []` and cost
    /// this test none of its orthogonality.
    private func assertSilhouetteStillDescribesTheRow(
        _ hole: CGRect,
        of row: UIView,
        spread: CGFloat,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let footprint = CGRect(origin: CGPoint(x: spread, y: spread), size: row.bounds.size)
        XCTAssertEqual(
            hole.minX, spread, accuracy: 0.01,
            "\(context): the silhouette starts \(spread)pt in, not at \(hole.minX)",
            file: file, line: line
        )
        XCTAssertEqual(
            hole.maxX, spread + row.bounds.maxX, accuracy: 0.01,
            "\(context): the silhouette is never grown sideways, yet \(hole) is",
            file: file, line: line
        )
        XCTAssertTrue(
            hole.contains(footprint),
            """
            \(context): the ambient silhouette \(hole) no longer covers the row's own \
            footprint \(footprint) — the corner probes would be measuring a hole that is \
            not the card
            """,
            file: file, line: line
        )
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
