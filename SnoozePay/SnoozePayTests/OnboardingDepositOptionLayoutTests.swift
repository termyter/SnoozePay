import XCTest
@testable import SnoozePay

/// Layout regression tests for the onboarding deposit page (#534).
///
/// The option card lays a text column (title row + description) beside an
/// incompressible amount label. Under the original `.leading` stack alignment
/// the description kept its single-line intrinsic width while the amount label
/// refused to shrink, and the engine settled the conflict by squeezing the
/// description to 8pt — one character per line, 550pt tall. That blew the card
/// up to 608pt and pushed the whole page ~200pt past its scroll page, hiding
/// the screen title and the third option on a real device.
///
/// **These tests mount the real `OnboardingViewController`, deliberately.** A
/// synthetic host that builds one card at a fixed width does NOT reproduce the
/// collapse — it was measured passing against the broken build. Only the card
/// carrying the visible "ПОПУЛЯРНО" tag collapses, and only inside the real
/// page's constraint set, so anything less than the real hierarchy is a test
/// that goes green on the bug it was written to catch.
final class OnboardingDepositOptionLayoutTests: XCTestCase {

    /// iPhone 17 points — the device the defect was recorded on.
    private let screen = CGSize(width: 402, height: 874)

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Mounts the onboarding pager and returns its three deposit cards.
    private func laidOutDepositCards() -> [OnboardingDepositOptionView] {
        let controller = OnboardingViewController()
        let host = UIWindow(frame: CGRect(origin: .zero, size: screen))
        host.rootViewController = controller
        host.isHidden = false
        window = host

        controller.loadViewIfNeeded()
        host.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return controller.depositOptionViews
    }

    private func descriptionLabel(in card: UIView) throws -> UILabel {
        try XCTUnwrap(
            allLabels(in: card).first { ($0.text ?? "").hasPrefix("≈") },
            "no description label in the card's subtree"
        )
    }

    private func allLabels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { subview -> [UILabel] in
            let nested = allLabels(in: subview)
            return (subview as? UILabel).map { [$0] + nested } ?? nested
        }
    }

    // MARK: - The collapse

    /// Broken build measured 8pt on the popular card. The floor sits far above
    /// that and far below the ~240pt a healthy text column gets.
    func testEveryDescription_getsRealHorizontalSpace() throws {
        for (index, card) in laidOutDepositCards().enumerated() {
            let label = try descriptionLabel(in: card)
            XCTAssertGreaterThan(
                label.bounds.width, 100,
                "card \(index): description collapsed to \(label.bounds.width)pt — "
                + "starved of width, it wraps one character per line"
            )
        }
    }

    /// The same defect from the other side. Two lines of meta type is ~36pt.
    func testEveryDescription_staysShort() throws {
        for (index, card) in laidOutDepositCards().enumerated() {
            let label = try descriptionLabel(in: card)
            XCTAssertLessThan(
                label.bounds.height, 60,
                "card \(index): description grew to \(label.bounds.height)pt — "
                + "that is a vertical-wrap blow-up, not a two-line label"
            )
        }
    }

    /// What the user sees. The broken build measured 608pt on the popular card
    /// against 75pt and 93pt for its neighbours.
    func testEveryCard_staysCardHeight() throws {
        for (index, card) in laidOutDepositCards().enumerated() {
            XCTAssertLessThan(
                card.bounds.height, 120,
                "card \(index) measured \(card.bounds.height)pt — it overflows the page"
            )
        }
    }

    /// The page as a whole has to fit what it is given. This is the assertion
    /// closest to the reported symptom: 928.7pt of content in a 712pt page.
    func testOptionColumn_fitsTheScreen() throws {
        let cards = laidOutDepositCards()
        let column = cards.reduce(0) { $0 + $1.bounds.height }

        XCTAssertLessThan(
            column, 320,
            "the three option cards measure \(column)pt tall together — the page "
            + "title and the CTA cannot both fit around that"
        )
    }

    // MARK: - The title row keeps its shape

    /// `.fill` stretches the title row to the text column's width. Without a
    /// spacer the slack lands on one of the two labels through a hugging tie
    /// broken by index — the trap that stretched the «Все» chip in #519.
    ///
    /// Unlike the four above, this one is green on the pre-fix build: it guards
    /// the mechanism the fix introduces, not the defect the fix removes.
    func testPopularTag_staysBesideItsTitle() throws {
        let cards = laidOutDepositCards()
        let popularCard = try XCTUnwrap(
            cards.first { card in
                allLabels(in: card).contains { $0.attributedText?.string == "ПОПУЛЯРНО" }
            },
            "no option card carries the ПОПУЛЯРНО tag"
        )
        let labels = allLabels(in: popularCard)
        let title = try XCTUnwrap(labels.first { $0.text == "Серьёзно" })
        let tag = try XCTUnwrap(labels.first { $0.attributedText?.string == "ПОПУЛЯРНО" })

        XCTAssertEqual(
            tag.frame.minX - title.frame.maxX, AppSpacing.sp2, accuracy: 1,
            "the caps tag drifted \(tag.frame.minX - title.frame.maxX)pt from the "
            + "title — the row's slack landed on a label instead of the spacer"
        )
    }
}
