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
/// together. The second compares against a literal 20 rather than against
/// `AppSpacing.cardHorizontalPadding`, because reading the token on both sides
/// would let a redefinition move them together and keep the test green while
/// the form drifted.
///
/// What this measures is the CARD's padding: the leading edge of the views the
/// cell itself positions. How far a child then insets its own content — a text
/// field's editing inset, a mono glyph's side bearing — is that child's
/// business and is not part of the card metric. So «Название» still starts its
/// glyphs ~1pt further in than the day chips do, and that is a separate
/// question from this one.
final class CreateAlarmCardInsetTests: XCTestCase {

    /// The inset this form standardised on (#231, #672, #677), held here as a
    /// literal rather than read from `AppSpacing.cardHorizontalPadding` so a
    /// redefinition of the token cannot move both sides of the comparison.
    ///
    /// It is NOT "what the canon says these cards use", and the name it used to
    /// carry said it was. 20 is `SPCard`'s own default parameter
    /// (`SPComponents.jsx:38`), and it is the literal on the three
    /// `padding={20}` cards of artboard `AlarmEdit` (`SPMore2.jsx:198`, `:237`,
    /// `:257`). But `SoundCell`, `VibrationCell` and `ThemeRowCell` — three of
    /// the ten cells measured below — map to the Звук / Тема / Вибрация card,
    /// which is `padding={4}` there (`:227`). For those the app holds 20
    /// against the canon, by our decision, not with it.
    private static let standardisedCardPadding: CGFloat = 20

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
                cards must share one inset — that is this app's rule (#672), \
                not something SPMore2.jsx settles
                """
            )
        }
    }

    func testTheSharedInsetIsTheValueWeStandardisedOn() throws {
        let measured = try measuredInsets()
        let reference = try reference(in: measured)

        XCTAssertEqual(
            reference.inset,
            Self.standardisedCardPadding,
            accuracy: 0.5,
            """
            The form's cards agree on \(reference.inset)pt, but this form \
            standardised on \(Self.standardisedCardPadding)pt (#231, #672, \
            #677). Before changing the number here, check that is what was \
            decided — the canon does not settle it, it puts 20 on three cards \
            of AlarmEdit and 4 on the Звук / Тема / Вибрация one.
            """
        )
    }

    /// The token the cells actually read must carry that same number — a
    /// `cardHorizontalPadding` named like this one but holding 16 is what #672
    /// was filed against, and a reader reaching for the token would silently
    /// reproduce it.
    func testTheCardPaddingTokenCarriesTheStandardisedNumber() {
        XCTAssertEqual(
            AppSpacing.cardHorizontalPadding,
            Self.standardisedCardPadding,
            accuracy: 0.001,
            """
            AppSpacing.cardHorizontalPadding drifted off the \
            \(Self.standardisedCardPadding)pt this form standardised on \
            (#231, #672, #677)
            """
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
