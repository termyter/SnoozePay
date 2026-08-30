import XCTest
@testable import SnoozePay

/// Layout of the «Прогрессивный режим» card's text column.
///
/// The canon puts the title, subtitle and doubling chain in a `flex: 1` column
/// beside the switch (`SPMore2.jsx` L260). The app matched that structurally
/// but the column never CLAIMED its width: `alignment = .leading` left every
/// row at its intrinsic size, and for a `numberOfLines = 0` label that is the
/// single-line width, so the column had no definite width at all. Where the
/// subtitle broke was then decided by compression tie-breaks — it split at
/// "в 2 / раза" while half the card sat empty (#638).
final class ProgressiveScaleCellLayoutTests: XCTestCase {

    /// Card width on a 390pt screen: 390 minus the form's 16pt page gutters,
    /// matching the width `CreateAlarmLightThemeTests` hosts this card at.
    private let cardWidth: CGFloat = 343

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func hostedCell() -> ProgressiveScaleCell {
        let cell = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        // Armed: the chain row is only in the hierarchy while the mode is on,
        // and it is the widest row — laying out without it would measure a
        // column the user never sees.
        cell.configure(isOn: true, chain: [50, 100, 200, 400], accessibilityChain: "")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: cardWidth, height: 400))
        window.isHidden = false
        hostWindows.append(window)

        cell.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 200)
        window.addSubview(cell)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return cell
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T { found.append(match) }
            found.append(contentsOf: descendants(of: type, in: subview))
        }
        return found
    }

    private func subtitleLabel(in cell: UIView) -> UILabel? {
        let expected = Localized.text("create_alarm.progressive.subtitle")
        return descendants(of: UILabel.self, in: cell).first { $0.text == expected }
    }

    // MARK: - Column width

    /// The column must run all the way to the switch. This is the regression
    /// the issue actually describes: empty space to the right of a wrapped line.
    ///
    /// Frames are converted into `cell` before comparing — the label lives in
    /// the stack, the switch in `contentView`, and their raw `frame`s are in
    /// different coordinate spaces.
    func testSubtitleColumnReachesTheSwitch() throws {
        let cell = hostedCell()
        let subtitle = try XCTUnwrap(subtitleLabel(in: cell), "subtitle label not found")
        let toggle = try XCTUnwrap(descendants(of: SPSwitch.self, in: cell).first,
                                   "switch not found")

        let subtitleFrame = subtitle.convert(subtitle.bounds, to: cell)
        let toggleFrame = toggle.convert(toggle.bounds, to: cell)

        XCTAssertEqual(toggleFrame.minX - subtitleFrame.maxX, AppSpacing.sp3, accuracy: 1,
                       "Subtitle should stop exactly one gap short of the switch, not earlier")
    }

    /// A blunter statement of the same thing, phrased the way the issue is:
    /// the caption must not be confined to a narrow column with half the card
    /// unused beside it.
    func testSubtitleUsesMoreThanHalfTheCard() throws {
        let cell = hostedCell()
        let subtitle = try XCTUnwrap(subtitleLabel(in: cell))

        XCTAssertGreaterThan(subtitle.frame.width, cardWidth / 2,
                             "Caption column collapsed to less than half the card")
    }

    // MARK: - Wrapping

    /// The caption is a touch too long for one line in this column, so it takes
    /// two — but no more. Three lines would mean the column had collapsed again.
    func testSubtitleWrapsAtMostOnce() throws {
        let cell = hostedCell()
        let subtitle = try XCTUnwrap(subtitleLabel(in: cell))

        XCTAssertLessThanOrEqual(subtitle.frame.height, subtitle.font.lineHeight * 2 + 1,
                                 "Caption took more than two lines — the column is too narrow")
    }

    /// Since the caption DOES wrap, the non-breaking space is what decides where.
    /// «в 2 раза» has to be narrow enough to survive as one unit in this column;
    /// if it were wider than the column, the layout would break it regardless of
    /// which space character joins it.
    func testTheUnbreakableRunFitsTheColumn() throws {
        let cell = hostedCell()
        let subtitle = try XCTUnwrap(subtitleLabel(in: cell))
        let font = try XCTUnwrap(subtitle.font)

        let run = "в 2\u{00A0}раза" as NSString
        let width = run.size(withAttributes: [.font: font]).width

        XCTAssertLessThan(width, subtitle.frame.width,
                          "«в 2 раза» is wider than its column, so it will be split anyway")
    }

    /// Typography rule, independent of width: a number and its unit may not be
    /// split across lines. A non-breaking space enforces it at ANY width, which
    /// is what makes the card safe at accessibility text sizes where wrapping
    /// is unavoidable.
    func testSubtitleKeepsTheNumberAndItsUnitTogether() {
        let subtitle = Localized.text("create_alarm.progressive.subtitle")

        XCTAssertTrue(subtitle.contains("2\u{00A0}раза"),
                      "«2 раза» must be joined by a non-breaking space")
        XCTAssertFalse(subtitle.contains("2 раза"),
                       "A plain space here lets the layout break between the number and its unit")
    }
}
