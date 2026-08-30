import XCTest
@testable import SnoozePay

/// Issue #631 — the «ДИНАМИКА ОТКЛАДЫВАНИЙ» card showed «Чаще, чем», an
/// unfinished sentence. The catalogue holds «Чаще, чем неделю назад»; the tail
/// was not truncated with an ellipsis, it was simply never drawn.
///
/// The label lives in a horizontal stack next to the trend arrow. A multi-line
/// `UILabel` with no `preferredMaxLayoutWidth` reports its SINGLE-LINE size, so
/// the stack sized itself for one line, the label was then squeezed narrower,
/// wrapped, and the second line had nowhere to go. No constraint was violated
/// and no truncation glyph appeared — which is why it survived review.
///
/// Assertions compare the rendered box against the height the text actually
/// needs at the width it actually got. `numberOfLines` would not catch this:
/// the label was already multi-line, it was the geometry that lied.
@MainActor
final class TrendHeadlineWrappingTests: XCTestCase {

    /// The narrowest supported width — the acceptance criterion asks for the
    /// smallest screen, not just an iPhone 17.
    private let narrowWidth: CGFloat = 320

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    private func hostedStatistics(width: CGFloat) -> StatisticsViewController {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
        window.isHidden = false
        hostWindows.append(window)
        let sut = StatisticsViewController()
        window.rootViewController = sut
        sut.loadViewIfNeeded()
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return sut
    }

    /// Height the string needs at the width the label ended up with.
    private func requiredHeight(for label: UILabel) throws -> CGFloat {
        let text = try XCTUnwrap(label.text)
        let font = try XCTUnwrap(label.font)
        XCTAssertGreaterThan(label.bounds.width, 0, "label was never given a width")
        return (text as NSString).boundingRect(
            with: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }

    private func assertNotClipped(
        _ label: UILabel,
        _ what: String,
        line: UInt = #line
    ) throws {
        let needed = try requiredHeight(for: label)
        XCTAssertGreaterThanOrEqual(
            label.bounds.height, needed - 0.5,
            "\(what): box is \(label.bounds.height)pt but the text needs \(needed)pt at "
                + "\(label.bounds.width)pt wide — the tail is not drawn",
            line: line
        )
    }

    // MARK: - The reported string

    func testWorseHeadlineIsDrawnInFull() throws {
        let sut = hostedStatistics(width: narrowWidth)
        sut.trendHeadlineLabel.text = Localized.text("statistics.trend.worse")
        sut.view.setNeedsLayout()
        sut.view.layoutIfNeeded()

        try assertNotClipped(sut.trendHeadlineLabel, "«Чаще, чем неделю назад»")
    }

    /// Acceptance: «проверены и остальные ветки statistics.trend.*».
    func testEveryTrendHeadlineIsDrawnInFull() throws {
        let sut = hostedStatistics(width: narrowWidth)

        for direction in [
            StatisticsViewModel.TrendDirection.better,
            .same,
            .worse
        ] {
            let headline = StatisticsViewModel.headline(for: direction)
            sut.trendHeadlineLabel.text = headline
            sut.view.setNeedsLayout()
            sut.view.layoutIfNeeded()

            try assertNotClipped(sut.trendHeadlineLabel, "headline for \(direction): «\(headline)»")
        }
    }

    /// The longest string on the card is not the headline at all — it is the
    /// flat-week caption underneath, and it sits in the same kind of stack.
    func testTheLongestSubtitleIsDrawnInFull() throws {
        let sut = hostedStatistics(width: narrowWidth)
        sut.trendSubtitleLabel.text = Localized.text("statistics.trend.no_change")
        sut.view.setNeedsLayout()
        sut.view.layoutIfNeeded()

        try assertNotClipped(sut.trendSubtitleLabel, "«Столько же, сколько на прошлой неделе»")
    }

    // MARK: - The guard that actually fails on the old code

    /// Both geometry assertions above pass on the BROKEN build too: hosted in
    /// a bare window the label gets a second layout pass, UIKit fills in
    /// `preferredMaxLayoutWidth` on its own, and the height comes out right.
    /// The defect needs the live screen to appear, and it was verified there.
    ///
    /// So the regression guard is structural: these two labels must be
    /// `SPWrappingLabel`. Swapping either back to a plain `UILabel` fails here
    /// — which is exactly the change that would bring the bug back.
    func testTrendLabelsUseTheWrappingLabel() {
        let sut = StatisticsViewController()
        sut.loadViewIfNeeded()

        XCTAssertTrue(
            sut.trendHeadlineLabel is SPWrappingLabel,
            "trendHeadlineLabel must report a height for the width it is given"
        )
        XCTAssertTrue(
            sut.trendSubtitleLabel is SPWrappingLabel,
            "trendSubtitleLabel carries the longest string on the card"
        )
    }

    // MARK: - The mechanism, in isolation

    /// `SPWrappingLabel` exists to report a height that matches the width it
    /// was given. Pinned directly so a future refactor cannot quietly swap it
    /// back to `UILabel` and reintroduce the whole class.
    func testWrappingLabelReportsHeightForItsActualWidth() {
        let label = SPWrappingLabel()
        label.font = AppTypography.h3
        label.numberOfLines = 0
        label.text = Localized.text("statistics.trend.worse")

        let singleLine = label.intrinsicContentSize.height
        label.frame = CGRect(x: 0, y: 0, width: 140, height: 0)
        label.layoutIfNeeded()

        XCTAssertGreaterThan(
            label.intrinsicContentSize.height, singleLine,
            "Narrowing the label must raise its intrinsic height, or the stack "
                + "around it keeps reserving one line"
        )
    }
}
