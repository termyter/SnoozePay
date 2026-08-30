import UIKit
import XCTest
@testable import SnoozePay

/// The wallet's transaction rows after #677 widened the card's horizontal
/// inset from `sp1` (4) to `sp5` (20).
///
/// ## Why the inset is 20 and not 4
///
/// Measured off a native 3× screenshot of the alarm form (1206×2622, so ÷3 for
/// pt), which is the list this screen is supposed to agree with:
///
/// | | from the screen edge |
/// |---|---|
/// | the `.insetGrouped` card itself | **20.0 pt** |
/// | the «Тема» swatch inside it | **40.0 pt** |
///
/// The 20 in `ThemeRowCell` is measured from the CELL, and the cell already
/// carries `.insetGrouped`'s own 20pt section inset — so the row content lands
/// 40pt from the screen edge, not 20. The wallet's cards sit in a stack with
/// `AppSpacing.screenInset` (16) margins, so `sp1` put the row content at
/// 16 + 4 = 20pt and `sp5` puts it at 16 + 20 = 36pt. The change moves this
/// list TOWARDS the reference; it does not overshoot it. (The remaining 4pt is
/// `screenInset` = 16 disagreeing with the canon gutter of 20, which is its
/// own inconsistency and not this screen's to fix.)
///
/// ## What this file actually guards
///
/// The inset is paid for out of the text column: `SPRow.titleLabel` is
/// `numberOfLines = 1` with no `adjustsFontSizeToFitWidth`, so 32pt of lost
/// width becomes an ellipsis rather than a second line. «Возврат за
/// откладывание» is the longest reachable title (`wallet.tx.refund`, restored
/// as a real path by #358), and the narrowest phone still supported is the
/// SE-class 375pt. Both are laid out here for real and asked whether the label
/// got the width its text needs.
///
/// Asserting on the laid-out label rather than on the constraint constant is
/// the point: a test that re-read `AppSpacing.sp5` would agree with any inset,
/// including one that truncates.
@MainActor
final class WalletRowInsetTests: XCTestCase {

    /// Widths of the phones this has to survive: SE-class, then the modern
    /// 6.1" the screenshots are taken on.
    private static let deviceWidths: [CGFloat] = [375, 393, 402]

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    /// The longest title the screen can actually show must still fit on the
    /// narrowest phone it supports.
    func testTheLongestRealTitleIsNotTruncatedOnAnySupportedWidth() throws {
        for width in Self.deviceWidths {
            let card = try laidOutPreviewCard(width: width)
            for label in Self.titleLabels(in: card) {
                XCTAssertGreaterThanOrEqual(
                    label.bounds.height.rounded() + 0.5, Self.heightNeeded(by: label).rounded(),
                    """
                    at \(width)pt «\(label.text ?? "")» was laid out \
                    \(label.bounds.width)×\(label.bounds.height)pt and its text needs \
                    \(Self.heightNeeded(by: label))pt at that width — the row renders \
                    an ellipsis
                    """
                )
            }
        }
    }

    /// The inset itself, measured from the card edge rather than read off the
    /// constraint — so a change that satisfies the constant while the stack
    /// resolves somewhere else still fails.
    func testTheRowContentStartsOneCardPaddingInsideTheCard() throws {
        let card = try laidOutPreviewCard(width: 402)
        let row = try XCTUnwrap(Self.rows(in: card).first, "the preview card built no rows")
        let rowInCard = row.convert(row.bounds, to: card)
        XCTAssertEqual(
            rowInCard.minX, AppSpacing.sp5, accuracy: 0.5,
            "the row no longer starts one card padding inside the card"
        )
        XCTAssertEqual(
            card.bounds.maxX - rowInCard.maxX, AppSpacing.sp5, accuracy: 0.5,
            "the inset stopped being symmetric"
        )
    }

    /// How tall the label's text really is at the width it was given.
    ///
    /// Deliberately NOT `label.sizeThatFits`: that respects `numberOfLines`
    /// and so caps at the very height we are trying to prove sufficient,
    /// which is a tautology. `boundingRect` ignores the cap and answers the
    /// question that matters — does the string fit, or is something cut off.
    private static func heightNeeded(by label: UILabel) -> CGFloat {
        guard let text = label.text, let font = label.font, label.bounds.width > 0 else { return 0 }
        return (text as NSString).boundingRect(
            with: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }

    // MARK: - Fixtures

    /// The real preview card, hosted at a real device width inside the same
    /// `screenInset` margins the wallet screen uses.
    private func laidOutPreviewCard(width: CGFloat) throws -> UIView {
        let items = [
            WalletTransactionPreviewItem(
                title: Localized.text("wallet.tx.refund"),
                timestampText: "Сегодня · 07:09",
                amountText: "+1 200 ₽",
                isDebit: false,
                iconSystemName: "arrow.uturn.backward"
            ),
            WalletTransactionPreviewItem(
                title: Localized.text("wallet.tx.topup"),
                timestampText: "Вчера · 21:32",
                amountText: "−1 200 ₽",
                isDebit: true,
                iconSystemName: "plus"
            )
        ]
        let card = WalletViewController().makeTxPreviewCard(items: items)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        window.overrideUserInterfaceStyle = .light
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        window.makeKeyAndVisible()
        hostWindows.append(window)

        card.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: window.topAnchor),
            card.leadingAnchor.constraint(
                equalTo: window.leadingAnchor, constant: AppSpacing.screenInset
            ),
            card.trailingAnchor.constraint(
                equalTo: window.trailingAnchor, constant: -AppSpacing.screenInset
            )
        ])
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return card
    }

    private static func rows(in view: UIView) -> [SPRow] {
        view.subviews.flatMap { ($0 as? SPRow).map { [$0] } ?? rows(in: $0) }
    }

    /// The title is the FIRST label of a row's text column; the timestamp
    /// underneath it is allowed to truncate and is not asked about.
    private static func titleLabels(in view: UIView) -> [UILabel] {
        rows(in: view).compactMap { row in
            labels(in: row).first { !($0.text ?? "").isEmpty && !($0.text ?? "").contains("·") }
        }
    }

    private static func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { ($0 as? UILabel).map { [$0] } ?? labels(in: $0) }
    }
}
