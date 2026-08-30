import UIKit
import XCTest
@testable import SnoozePay

/// Issue #630 — the alarm card's toggle escaped the card's right edge as soon
/// as the title wrapped onto a second line.
///
/// ## What actually moved
///
/// Pixel columns off the reported screenshot (1206×2622, @3x, so ÷3 for pt):
///
/// | card | toggle drawing | card box | right gap |
/// |---|---|---|---|
/// | one line  | 915…1102 px | 49…1156 px | +54 px |
/// | two lines | 973…1159 px | 49…1156 px | **−3 px** |
///
/// The drawing is 186 px wide in BOTH rows — the control was not stretched or
/// squeezed visually, it was displaced by ~57 px (19 pt) to the right. And its
/// `trailing` constraint was satisfied the whole time. Those two facts only fit
/// together one way: `UISwitch` renders its intrinsic-size track centred in its
/// bounds and does not clip, so a frame squeezed by 38 pt keeps a 62 pt drawing
/// that now hangs 19 pt off each side. Half of 38 is the 19 that was measured.
///
/// The squeeze came from a degenerate tie. `capsLabel.trailing` is pinned to
/// `toggleSwitch.leading`, and a `numberOfLines = 0` label reports its
/// SINGLE-line width as intrinsic — for a wrapping title that is ~600 pt of a
/// 256 pt run. The label resisted compression at 750, the switch at 750, so the
/// deficit could be paid out of either view at identical cost and the engine
/// took it out of the switch.
///
/// ## What these tests measure
///
/// Not `frame.maxX` — that was green before the fix and is the reason earlier
/// probes found nothing. They measure the **drawn box** (intrinsic size centred
/// on the switch's centre, which is what a screenshot sees) against the card,
/// and the switch's laid-out width against its intrinsic width.
final class AlarmCellToggleOverflowTests: XCTestCase {

    /// iPhone 16 Pro portrait — the width the reported screenshot was taken at
    /// (1206 px @3x). Leaves the caps label ≈256 pt of run after the 16 pt
    /// screen inset, 20 pt card padding and the switch column.
    private let cellWidth: CGFloat = 402

    /// Card padding — the gap the toggle is supposed to keep from the edge.
    private let pad = AppSpacing.sp5

    private let shortName = "Будни · Пн–Пт".uppercased()
    /// The exact title from the failing row in the screenshot.
    private let twoLineName = "Спортзал и длинная пробежка по набережной · Выходные".uppercased()

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Lays a configured cell out through the same self-sizing sequence the
    /// list uses (`automaticDimension` + compressed fitting pass), hosted in a
    /// real window so the pass runs against real traits.
    private func layoutCell(daysCaps: String) -> AlarmCell {
        let cell = AlarmCell(style: .default, reuseIdentifier: AlarmCell.reuseID)
        cell.configure(
            time: "07:00",
            daysCaps: daysCaps,
            priceText: "50 ₽",
            multiplier: "×2",
            soundName: "Soft Dawn",
            enabled: true
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: cellWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = ceil(fitted.height)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: cellWidth, height: height + 40))
        window.isHidden = false
        hostWindows.append(window)

        cell.frame = CGRect(x: 0, y: 0, width: cellWidth, height: height)
        window.addSubview(cell)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return cell
    }

    private func toggleView(in cell: AlarmCell) throws -> SPSwitch {
        try XCTUnwrap(descendants(of: SPSwitch.self, in: cell).first, "toggle not found in AlarmCell")
    }

    /// The card surface: the switch's own superview, so the test never has to
    /// guess which subview is the card.
    private func cardView(of toggle: SPSwitch) throws -> UIView {
        try XCTUnwrap(toggle.superview, "toggle has no card superview")
    }

    /// What a screenshot sees: `UISwitch` paints its intrinsic-size track
    /// centred in its bounds and clips to nothing, so the drawn box is NOT
    /// `frame` once the frame has been compressed.
    private func drawnBox(of toggle: SPSwitch, in card: UIView) -> CGRect {
        let centre = toggle.convert(CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: card)
        let size = toggle.intrinsicContentSize
        return CGRect(
            x: centre.x - size.width / 2,
            y: centre.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T { found.append(match) }
            found.append(contentsOf: descendants(of: type, in: subview))
        }
        return found
    }

    /// Distance from the right edge of the toggle's DRAWING to the card edge —
    /// the number the screenshot measurement in #630 reports.
    private func rightGap(daysCaps: String) throws -> CGFloat {
        let toggle = try toggleView(in: layoutCell(daysCaps: daysCaps))
        let card = try cardView(of: toggle)
        return card.bounds.maxX - drawnBox(of: toggle, in: card).maxX
    }

    private func capsLabel(text: String, in cell: AlarmCell) throws -> UILabel {
        let label = descendants(of: UILabel.self, in: cell).first { $0.attributedText?.string == text }
        return try XCTUnwrap(label, "caps label rendering \"\(text)\" not found")
    }

    // MARK: - The fixture really wraps

    /// Without this the three tests below would be vacuously green on a title
    /// that happens to fit on one line.
    func testTheLongFixtureTitleReallyWrapsAtThisWidth() throws {
        let cell = layoutCell(daysCaps: twoLineName)
        let caps = try capsLabel(text: twoLineName, in: cell)
        let lineHeight = AppTypography.caps.lineHeight

        XCTAssertGreaterThanOrEqual(
            caps.bounds.height, lineHeight * 2 - 1,
            "Fixture title fits on one line at \(cellWidth)pt — it cannot exercise the wrap defect"
        )
    }

    // MARK: - The defect

    /// The regression itself: the drawn control must stay inside the card.
    /// Before the fix this box ran ~1 pt PAST the card's right edge, 19 pt past
    /// where the padding puts it.
    func testToggleDrawingStaysInsideTheCardWhenTitleWraps() throws {
        let cell = layoutCell(daysCaps: twoLineName)
        let toggle = try toggleView(in: cell)
        let card = try cardView(of: toggle)

        let drawn = drawnBox(of: toggle, in: card)
        XCTAssertLessThanOrEqual(
            drawn.maxX, card.bounds.maxX - pad + 0.5,
            "Toggle is drawn past the card's inner padding — it overflows the card edge"
        )
    }

    /// Why it overflowed: the frame lost width while the drawing kept it.
    /// A control the user has to hit cannot be a source of slack.
    func testToggleKeepsItsIntrinsicWidthWhenTitleWraps() throws {
        let cell = layoutCell(daysCaps: twoLineName)
        let toggle = try toggleView(in: cell)

        XCTAssertEqual(
            toggle.bounds.width, toggle.intrinsicContentSize.width, accuracy: 0.5,
            "Switch frame was compressed; its drawing does not shrink with it, so it spills out of bounds"
        )
    }

    /// The issue's acceptance criterion, stated directly: a wrapped title must
    /// not change the toggle's right gap at all.
    func testRightGapIsIdenticalForOneLineAndWrappedTitles() throws {
        let oneLineGap = try rightGap(daysCaps: shortName)
        let wrappedGap = try rightGap(daysCaps: twoLineName)

        XCTAssertEqual(
            wrappedGap, oneLineGap, accuracy: 1,
            "Wrapping the title moved the toggle by \(oneLineGap - wrappedGap)pt"
        )
    }

    /// The trailing constraint was never broken — documenting that here keeps a
    /// future reader from "fixing" the wrong thing, and keeps the assertions
    /// above from being satisfied by nudging the anchor with a magic constant.
    func testTrailingAnchorWasNeverTheProblem() throws {
        for name in [shortName, twoLineName] {
            let cell = layoutCell(daysCaps: name)
            let toggle = try toggleView(in: cell)
            let card = try cardView(of: toggle)

            XCTAssertEqual(
                toggle.frame.maxX, card.bounds.maxX - pad, accuracy: 0.5,
                "Toggle frame trailing must sit exactly one card padding from the edge"
            )
        }
    }

    // MARK: - Contract

    /// The tie that made the split degenerate lived in the priorities, so guard
    /// them: a switch that can be compressed will drift again the next time a
    /// call site pins a wrapping label to it.
    func testSPSwitchRefusesToBeCompressed() {
        let toggle = SPSwitch()

        XCTAssertEqual(toggle.contentCompressionResistancePriority(for: .horizontal), .required)
        XCTAssertEqual(toggle.contentCompressionResistancePriority(for: .vertical), .required)
        // The other half of "fixed size" is the platform default and is left
        // optional on purpose (a stack may stretch the container it sits in) —
        // 750 still outranks every label's 251, so nothing stretches the switch.
        XCTAssertGreaterThanOrEqual(
            toggle.contentHuggingPriority(for: .horizontal).rawValue,
            UILayoutPriority.defaultHigh.rawValue,
            "A switch that hugs weaker than the text beside it will be stretched instead of the text"
        )
    }
}
