import XCTest
@testable import SnoozePay

/// Tests for the alarms-list zero-balance state + alarm-title wrap rule (#232).
///
/// Part 1 — `AlarmsListViewModel.balanceHint` must swap the affordability
/// line for the zero-balance copy "Откладывать не получится" the moment the
/// wallet hits 0 ₽ (NOT "будильники не зазвонят" — the alarm still fires at
/// zero balance, the user just can't pay to snooze it).
///
/// Part 2 — `AlarmCell` must WRAP long alarm titles onto new lines, never
/// truncate them: 13/26-char names render on one line, 27-char wraps to 2,
/// 61-char wraps to 3 (per `AlarmCardWrapDemo` in SPScreensV2.jsx); the card
/// grows in height each time.
final class AlarmsListZeroBalanceTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var repo: AlarmRepository!

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmsListZeroBalance.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        repo = AlarmRepository(
            defaults: testDefaults,
            scheduler: AlarmsListViewModelTests.StubScheduler()
        )
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Builds a VM wired to an isolated BalanceService seeded with the
    /// given balance, so the shared singleton stays untouched.
    private func makeViewModel(balance: Double) -> AlarmsListViewModel {
        let center = NotificationCenter()
        testDefaults.set(balance, forKey: "user_balance")
        let service = BalanceService(defaults: testDefaults, notificationCenter: center)
        let viewModel = AlarmsListViewModel(
            alarmRepository: repo,
            balanceService: service,
            transactionRepository: TransactionRepository(defaults: testDefaults),
            notificationCenter: center
        )
        viewModel.loadData()
        return viewModel
    }

    func testZeroBalance_hintIsCannotSnoozeCopy() {
        let viewModel = makeViewModel(balance: 0)

        XCTAssertTrue(viewModel.isZeroBalance)
        XCTAssertEqual(viewModel.balanceHint, "Откладывать не получится")
    }

    func testZeroBalance_copyNeverClaimsAlarmsWontRing() {
        // PM explicitly corrected the copy: the alarm DOES ring at 0 ₽ —
        // only snoozing is unavailable. Guard against the wrong wording
        // sneaking back in.
        XCTAssertFalse(AlarmsListViewModel.zeroBalanceHint.lowercased().contains("не зазвон"))
        XCTAssertFalse(AlarmsListViewModel.zeroBalanceHint.lowercased().contains("не сработа"))
    }

    func testPositiveBalance_hintIsAffordabilityLine() {
        let viewModel = makeViewModel(balance: 150)

        XCTAssertFalse(viewModel.isZeroBalance)
        // 150 ₽ / default 50 ₽ penalty → 3 snoozes.
        XCTAssertEqual(viewModel.balanceHint, "Хватит на ~3 откладывания")
        XCTAssertEqual(viewModel.balanceHint, viewModel.affordabilityHint)
    }

    func testLowButNonZeroBalance_keepsAffordabilityHint() {
        // 50 ₽ is at/below the low-balance threshold (100 ₽) but NOT zero —
        // the pill goes warn-tone, the copy must stay the affordability
        // line, not the zero-balance escalation.
        let viewModel = makeViewModel(balance: 50)

        XCTAssertFalse(viewModel.isZeroBalance)
        XCTAssertTrue(viewModel.isLowBalance)
        XCTAssertEqual(viewModel.balanceHint, "Хватит на ~1 откладывание")
    }
}

// MARK: - AlarmCell title wrap (#232)

final class AlarmCellTitleWrapTests: XCTestCase {

    /// iPhone-class width — gives the caps label ≈258 pt of run room after
    /// the screen insets, card padding and the switch column.
    private let cellWidth: CGFloat = 393

    /// The four demo titles from `AlarmCardWrapDemo` (13/26/27/61 chars).
    private let shortName = "Будни · Пн–Пт".uppercased()
    private let edgeName = "Понедельник тренировка зал".uppercased()
    private let twoLineName = "Ранний подъём перед работой каждый день".uppercased()
    private let longName =
        "Утренняя тренировка перед работой каждый рабочий день недели".uppercased()

    /// Lays the cell out at `cellWidth` using the same compressed-fitting
    /// pass UITableView's self-sizing uses, then returns the cell plus the
    /// caps label rendering `daysCaps`.
    private func layoutCell(daysCaps: String) -> (cell: AlarmCell, caps: UILabel) {
        let cell = AlarmCell(style: .default, reuseIdentifier: AlarmCell.reuseID)
        cell.configure(
            time: "07:00",
            daysCaps: daysCaps,
            priceText: "50 ₽",
            multiplier: nil,
            soundName: "Soft Dawn",
            enabled: true
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: cellWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: cellWidth, height: ceil(fitted.height))
        cell.layoutIfNeeded()
        guard let caps = findLabel(withText: daysCaps, in: cell) else {
            XCTFail("Caps label rendering \"\(daysCaps)\" not found in AlarmCell")
            return (cell, UILabel())
        }
        return (cell, caps)
    }

    private func findLabel(withText text: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel,
           label.attributedText?.string == text || label.text == text {
            return label
        }
        for subview in view.subviews {
            if let found = findLabel(withText: text, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Rendered line count — wrapped height divided by the line height of
    /// the ACTUAL caps font. (`label.font` stays the 17pt default when the
    /// text is attributed, so read the font off the attributed string.)
    private func lineCount(of label: UILabel) -> Int {
        let font = (label.attributedText?.attribute(
            .font, at: 0, effectiveRange: nil
        ) as? UIFont) ?? label.font ?? UIFont.systemFont(ofSize: 12)
        guard font.lineHeight > 0 else { return 0 }
        return Int((label.bounds.height / font.lineHeight).rounded())
    }

    /// "Never truncated" — the laid-out label must be tall enough for the
    /// FULL text at its final width (no vertical clipping → no ellipsis).
    private func assertNotTruncated(
        _ label: UILabel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let attributed = label.attributedText else {
            XCTFail("Caps label lost its attributed text", file: file, line: line)
            return
        }
        let required = attributed.boundingRect(
            with: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        XCTAssertGreaterThanOrEqual(
            label.bounds.height + 0.5, required,
            "Caps label is shorter than its full text — title is being clipped/truncated",
            file: file, line: line
        )
    }

    func testCapsLabelNeverTruncates() {
        for name in [shortName, edgeName, twoLineName, longName] {
            let (_, caps) = layoutCell(daysCaps: name)
            XCTAssertEqual(caps.numberOfLines, 0, "Caps label must allow unlimited lines")
            XCTAssertFalse(
                caps.adjustsFontSizeToFitWidth,
                "Long titles must wrap, not shrink to fit"
            )
            assertNotTruncated(caps)
        }
    }

    func testShortNameRendersOnOneLine() {
        XCTAssertEqual(lineCount(of: layoutCell(daysCaps: shortName).caps), 1)
    }

    func testEdgeNameStaysCompactAndUnclipped() {
        // The 26-char demo title sits exactly at the single-line capacity
        // in the design's CSS metrics. UIFont metrics differ slightly, so
        // don't pin the boundary to exactly 1 line — assert it stays
        // compact (≤2 lines) and, critically, is never truncated.
        let caps = layoutCell(daysCaps: edgeName).caps
        XCTAssertLessThanOrEqual(lineCount(of: caps), 2)
        assertNotTruncated(caps)
    }

    func testLongNamesWrapOntoMultipleLines() {
        let twoLine = lineCount(of: layoutCell(daysCaps: twoLineName).caps)
        let threeLine = lineCount(of: layoutCell(daysCaps: longName).caps)
        XCTAssertGreaterThanOrEqual(twoLine, 2, "≈40-char title must wrap to ≥2 lines")
        XCTAssertGreaterThanOrEqual(threeLine, 3, "61-char title must wrap to ≥3 lines")
        XCTAssertGreaterThanOrEqual(threeLine, twoLine, "Longer titles must not collapse lines")
    }

    func testCardGrowsWithWrappedTitle() {
        let oneLineHeight = layoutCell(daysCaps: shortName).cell.frame.height
        let twoLineHeight = layoutCell(daysCaps: twoLineName).cell.frame.height
        let threeLineHeight = layoutCell(daysCaps: longName).cell.frame.height

        XCTAssertGreaterThan(
            twoLineHeight, oneLineHeight,
            "Card must grow when the title wraps to a second line"
        )
        XCTAssertGreaterThan(
            threeLineHeight, twoLineHeight,
            "Card must keep growing as more lines wrap"
        )
    }
}
