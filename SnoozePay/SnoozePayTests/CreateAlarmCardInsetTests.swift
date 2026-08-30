import XCTest
@testable import SnoozePay

/// Horizontal content inset of every card on the create/edit-alarm form.
///
/// The canon does NOT build this form out of one component — an earlier
/// version of this header said it did, and that was checkably wrong. Inside
/// artboard `AlarmEdit` (`SPMore2.jsx:131-291`) three different rules land the
/// content, and only two of them land it on 20: the screen gutter (`:145`,
/// `:161`, `:196`), `SPCard padding={20}` (`:198`, `:237`, `:257`), and
/// `SPCard padding={4}` (`:227`) for the Звук / Тема / Вибрация rows, where
/// canon is 4 and the app deliberately holds 20. The full mapping lives on
/// `AppSpacing.cardHorizontalPadding`.
///
/// What this file guards is therefore the APP's rule, not the canon's: every
/// cell on the form agrees on one inset. The app drifted off that one cell at
/// a time — `TimePickerCell` and the list rows kept 20pt, while the name
/// field, the day chips, the repeat pill, the snooze slider and the penalty
/// column settled on `AppSpacing.lg` (16). On screen the two groups sit
/// directly above each other, so the 4pt step reads as a misaligned column of
/// text (#672).
///
/// Two oracles, on purpose. "Every cell agrees with every other" catches one
/// cell drifting; "the shared value is 20" catches all of them drifting
/// together. The second compares against the LITERAL canon number rather than
/// `AppSpacing.cardHorizontalPadding`, because the token is ours and the canon
/// is not — redefining the token would otherwise move both sides at once and
/// keep the test green while the form left the canon.
///
/// What this measures is the CARD's padding: the leading edge of the views the
/// cell itself positions. How far a child then insets its own content — a text
/// field's editing inset, a mono glyph's side bearing — is that child's
/// business and is not part of the card metric. So «Название» still starts its
/// glyphs ~1pt further in than the day chips do, and that is a separate
/// question from this one.
final class CreateAlarmCardInsetTests: XCTestCase {

    /// `SPCard padding={20}` — the literal from the canon, not our token.
    private static let canonCardPadding: CGFloat = 20

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
        let reference = try reference(in: measured)

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
        let reference = try reference(in: measured)

        XCTAssertEqual(
            reference.inset,
            Self.canonCardPadding,
            accuracy: 0.5,
            """
            The form's cards agree on \(reference.inset)pt, but the canon card \
            is `SPCard padding={20}` (SPMore2.jsx, artboard AlarmEdit)
            """
        )
    }

    /// The token the cells actually read must be the canon number too — a
    /// named `cardHorizontalPadding` holding 16 is what #672 was filed against,
    /// and a reader reaching for the token would silently reproduce it.
    func testTheCardPaddingTokenCarriesTheCanonNumber() {
        XCTAssertEqual(
            AppSpacing.cardHorizontalPadding,
            Self.canonCardPadding,
            accuracy: 0.001,
            "AppSpacing.cardHorizontalPadding drifted off the canon SPCard padding={20}"
        )
    }

    // MARK: - Measurement

    private typealias Measured = (name: String, inset: CGFloat)

    /// The cell the others are compared against, chosen by NAME rather than by
    /// position, so reordering the fixture list cannot silently change which
    /// cell defines the form's inset.
    private func reference(in measured: [Measured]) throws -> Measured {
        try XCTUnwrap(
            measured.first { $0.name == "PenaltyCell" },
            "the reference cell is missing from the fixture list"
        )
    }

    /// Leading gap between each cell's `contentView` and the leftmost thing it
    /// draws, measured after a real layout pass rather than read off the
    /// constraint constants the production code sets.
    private func measuredInsets() throws -> [Measured] {
        // Every cell type `CreateAlarmViewController+Sections.registerSectionCells(in:)`
        // registers. Naming fewer than all of them is how the drift this test
        // exists to catch got in: the six that had drifted were fixed, and the
        // four that had not were left unwatched.
        let cells: [(String, UITableViewCell)] = [
            ("TimePickerCell", TimePickerCell(style: .default, reuseIdentifier: nil)),
            ("DayPickerCell", DayPickerCell(style: .default, reuseIdentifier: nil)),
            ("RepeatModeCell", RepeatModeCell(style: .default, reuseIdentifier: nil)),
            ("NameCell", NameCell(style: .default, reuseIdentifier: nil)),
            ("SoundCell", SoundCell(style: .default, reuseIdentifier: nil)),
            ("VibrationCell", VibrationCell(style: .default, reuseIdentifier: nil)),
            ("PenaltyCell", PenaltyCell(style: .default, reuseIdentifier: nil)),
            ("ProgressiveScaleCell", ProgressiveScaleCell(style: .default, reuseIdentifier: nil)),
            ("SnoozeSliderCell", SnoozeSliderCell(style: .default, reuseIdentifier: nil)),
            ("ThemeRowCell", ThemeRowCell(style: .default, reuseIdentifier: nil))
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
