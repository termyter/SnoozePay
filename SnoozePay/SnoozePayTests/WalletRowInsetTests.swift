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
/// The inset is paid for out of the text column, so 32pt of lost width has to
/// go somewhere. Before #677 it went into an ellipsis: `SPRow.titleLabel` had
/// no `adjustsFontSizeToFitWidth` and one line. #677 gives the wallet's rows
/// `titleLines: 2` instead, and that is a visible trade, not a free fix —
/// «Пополнение баланса» needs 175pt and had 175/193/202pt of run before the
/// change, so it fit on one line at every width and now wraps at every width.
/// One card can therefore hold rows of two different heights (~66 vs ~87pt).
/// That raggedness is bought deliberately: the amount beside the title stays
/// put either way, and an ellipsis eats the noun that says WHAT the money did.
///
/// «Возврат за откладывание» is the longest reachable title
/// (`wallet.tx.refund`, restored as a real path by #358), and the narrowest
/// phone still supported is the SE-class 375pt. Both are laid out here for
/// real and asked whether the label got the height its text needs.
///
/// Asserting on the laid-out label rather than on the constraint constant is
/// the point: a test that re-read `AppSpacing.sp5` would agree with any inset,
/// including one that truncates.
@MainActor
final class WalletRowInsetTests: XCTestCase {

    /// Widths of the phones this has to survive: SE-class, the two 6.1"
    /// classes the screenshots are taken on, then Max/Pro-Max. The last two
    /// are here because "the widest phone" is a load-bearing phrase in
    /// `SPRow.titleLines`' doc, and without them it would have meant 402.
    private static let deviceWidths: [CGFloat] = [375, 393, 402, 430, 440]

    private var hostWindows: [UIWindow] = []

    /// The history screen reads the real ledger out of `UserDefaults.standard`
    /// — there is no seam to inject through — so this suite writes it and puts
    /// back whatever was there. Restoring the raw `Data` (including "absent")
    /// rather than clearing it keeps the 1000-odd other tests seeing the
    /// ledger they expect.
    private static let ledgerKey = "stored_transactions"
    private var savedLedger: Data??

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        if let saved = savedLedger {
            if let blob = saved {
                UserDefaults.standard.set(blob, forKey: Self.ledgerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.ledgerKey)
            }
            savedLedger = nil
        }
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
    ///
    /// A zero-width label returns `.greatestFiniteMagnitude`, not 0. Zero is
    /// the answer that would make every assertion below pass while the row is
    /// in exactly the broken state this suite exists to catch — the collapsed
    /// frame documented in #467/#576, where the width survives and the height
    /// does not. Failing loudly is the only safe direction here.
    private static func heightNeeded(by label: UILabel) -> CGFloat {
        guard label.bounds.width > 0 else { return .greatestFiniteMagnitude }
        guard let text = label.text, let font = label.font else { return 0 }
        return (text as NSString).boundingRect(
            with: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }

    /// The same question on the OTHER screen that renders these rows.
    ///
    /// `WalletTransactionHistoryViewController.makeCard` repeats the preview
    /// card's `sp5` inset and `titleLines: 2` by hand, so the two can drift
    /// apart while the preview-card tests above stay green — and «Все
    /// операции» would then visibly shift the list sideways.
    func testTheHistoryScreenRendersTheSameRowsWithoutTruncation() throws {
        for width in Self.deviceWidths {
            let screen = try laidOutHistoryScreen(width: width)
            let titles = Self.titleLabels(in: screen)
            XCTAssertFalse(titles.isEmpty, "the history screen built no rows at \(width)pt")
            for label in titles {
                XCTAssertGreaterThanOrEqual(
                    label.bounds.height.rounded() + 0.5, Self.heightNeeded(by: label).rounded(),
                    """
                    at \(width)pt «\(label.text ?? "")» was laid out \
                    \(label.bounds.width)×\(label.bounds.height)pt on the history \
                    screen and its text needs \(Self.heightNeeded(by: label))pt
                    """
                )
            }
        }
    }

    /// The history card has to start its rows at the same inset as the
    /// preview card, or the two lists disagree by 16pt at the same width.
    func testTheHistoryCardUsesTheSameRowInsetAsThePreviewCard() throws {
        let history = try laidOutHistoryScreen(width: 402)
        let row = try XCTUnwrap(Self.rows(in: history).first, "the history screen built no rows")
        let card = try XCTUnwrap(
            sequence(first: row.superview, next: { $0?.superview }).first { $0 is SPCard } ?? nil,
            "the history row is not inside an SPCard"
        )
        let rowInCard = row.convert(row.bounds, to: card)
        XCTAssertEqual(
            rowInCard.minX, AppSpacing.sp5, accuracy: 0.5,
            "the history card's row inset drifted away from the preview card's"
        )
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

    /// The real history screen, hosted at a real device width with a ledger
    /// holding the two titles this file cares about.
    private func laidOutHistoryScreen(width: CGFloat) throws -> UIView {
        if savedLedger == nil {
            savedLedger = .some(UserDefaults.standard.data(forKey: Self.ledgerKey))
        }
        let ledger = [
            Transaction(type: .refund, amount: 1_200, createdAt: Date()),
            Transaction(type: .topup, amount: 1_200, createdAt: Date())
        ]
        UserDefaults.standard.set(try JSONEncoder().encode(ledger), forKey: Self.ledgerKey)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
        window.overrideUserInterfaceStyle = .light
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        let screen = WalletTransactionHistoryViewController()
        window.rootViewController = screen
        window.makeKeyAndVisible()
        hostWindows.append(window)

        screen.loadViewIfNeeded()
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return screen.view
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
