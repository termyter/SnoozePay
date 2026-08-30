import XCTest
@testable import SnoozePay

/// Horizontal content inset of every card on the create/edit-alarm form.
///
/// The canon builds this whole form out of one component: `SPCard padding={20}`
/// (`SPMore2.jsx`, artboard `AlarmEdit`). The app drifted off it one cell at a
/// time — `TimePickerCell` and the list rows kept 20pt, while the name field,
/// the day chips, the repeat pill, the snooze slider and the penalty column
/// settled on `AppSpacing.lg` (16). On screen the two groups sit directly above
/// each other, so the 4pt step reads as a misaligned column of text (#672).
///
/// The oracle is deliberately *not* "each cell equals 20". It is "every cell
/// agrees with every other cell", with a single separate check tying that
/// shared value to the canon. A future change that moves the whole form to a
/// different padding stays green; a change that moves one cell does not.
final class CreateAlarmCardInsetTests: XCTestCase {

    /// Card width on a 390pt screen minus the `.insetGrouped` gutters — the
    /// same width `CreateAlarmLightThemeTests` hosts these cells at.
    private let cardWidth: CGFloat = 343

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Tests

    func testEveryFormCardStartsItsContentAtTheSameInset() throws {
        let measured = try measuredInsets()
        let reference = try XCTUnwrap(measured.first)

        for (name, inset) in measured {
            XCTAssertEqual(
                inset,
                reference.inset,
                accuracy: 0.5,
                """
                \(name) starts its content \(inset)pt from the card edge while \
                \(reference.name) starts at \(reference.inset)pt — the form's \
                cards must share one inset, see SPMore2.jsx AlarmEdit
                """
            )
        }
    }

    func testTheSharedInsetIsTheCanonCardPadding() throws {
        let measured = try measuredInsets()
        let reference = try XCTUnwrap(measured.first)

        XCTAssertEqual(
            reference.inset,
            AppSpacing.sp5,
            accuracy: 0.5,
            """
            The form's cards agree on \(reference.inset)pt, but the canon card \
            is `SPCard padding={20}` — AppSpacing.sp5
            """
        )
    }

    // MARK: - Measurement

    private typealias Measured = (name: String, inset: CGFloat)

    /// Leading gap between each cell's `contentView` and the leftmost thing it
    /// draws, measured after a real layout pass rather than read off the
    /// constraint constants the production code sets.
    private func measuredInsets() throws -> [Measured] {
        let cells: [(String, UITableViewCell)] = [
            ("TimePickerCell", TimePickerCell(style: .default, reuseIdentifier: nil)),
            ("NameCell", NameCell(style: .default, reuseIdentifier: nil)),
            ("DayPickerCell", DayPickerCell(style: .default, reuseIdentifier: nil)),
            ("RepeatModeCell", RepeatModeCell(style: .default, reuseIdentifier: nil)),
            ("SnoozeSliderCell", SnoozeSliderCell(style: .default, reuseIdentifier: nil)),
            ("PenaltyCell", PenaltyCell(style: .default, reuseIdentifier: nil))
        ]

        var measured: [Measured] = []
        for (name, cell) in cells {
            host(cell)
            let inset = try XCTUnwrap(
                leadingContentInset(of: cell),
                "\(name) laid out with no measurable content"
            )
            measured.append((name, inset))
        }
        return measured
    }

    private func host(_ cell: UITableViewCell) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: cardWidth, height: 600))
        window.isHidden = false
        hostWindows.append(window)
        cell.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 240)
        window.addSubview(cell)
        window.setNeedsLayout()
        window.layoutIfNeeded()
    }

    /// Smallest `minX` among the views the CELL ITSELF positions — the direct
    /// children of `contentView`. That is precisely the card's padding: how a
    /// child distributes its own subviews further in (a button's title inset,
    /// a stack that centres its arranged views) is that child's business and
    /// must not be mistaken for the card's.
    private func leadingContentInset(of cell: UITableViewCell) -> CGFloat? {
        cell.contentView.subviews
            .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 0 && $0.bounds.height > 0 }
            .map { $0.frame.minX }
            .min()
    }
}
