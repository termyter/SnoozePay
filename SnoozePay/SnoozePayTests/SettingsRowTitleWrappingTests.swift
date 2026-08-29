import XCTest
@testable import SnoozePay

/// Issue #519 — «Цена откладывания по умолчанию» is wider than a Settings row
/// and used to render as «Цена откладывания по ум…». The copy is canon
/// (`SPMore4.jsx:155`) and the design row wraps in the same situation
/// (`.sp-row__main { flex: 1; min-width: 0 }`, no `text-overflow`), so the row
/// now takes a second line and the Финансы section self-sizes.
///
/// The assertions are on measured height rather than on `numberOfLines`: a
/// two-line label whose section still returns a fixed 52pt would look exactly
/// like the bug, and only the height catches that pairing.
final class SettingsRowTitleWrappingTests: XCTestCase {

    /// Deliberately narrow — the wrap has to hold on the smallest shipping
    /// width, and it keeps the test independent of whether the brand Manrope
    /// faces are registered in the test host (`AppFonts.brandFontsAvailable`).
    private let rowWidth: CGFloat = 320

    private func fittedHeight(title: String, trailingText: String?) -> CGFloat {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(
            systemName: "rublesign.circle",
            iconColor: AppColors.warn400,
            title: title,
            trailingText: trailingText,
            accessory: .disclosureIndicator
        )
        cell.frame = CGRect(
            x: 0, y: 0,
            width: rowWidth, height: SettingsIconRowCell.minimumRowHeight
        )
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        return cell.contentView.systemLayoutSizeFitting(
            CGSize(width: rowWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    func testLongFinanceTitleAsksForMoreThanOneRowOfHeight() {
        let height = fittedHeight(title: "Цена откладывания по умолчанию", trailingText: "50 ₽")
        XCTAssertGreaterThan(
            height, SettingsIconRowCell.minimumRowHeight,
            "The title has to wrap, and a wrapped row needs more than the 52pt "
                + "rhythm — otherwise `heightForRowAt` clips the second line"
        )
    }

    func testShortTitleStillMeasuresAtTheRowRhythm() {
        let height = fittedHeight(title: "Вибрация", trailingText: nil)
        XCTAssertEqual(
            height, SettingsIconRowCell.minimumRowHeight, accuracy: 0.5,
            "A one-line row must not shrink below 52pt now that its section "
                + "self-sizes, or Финансы reads tighter than its neighbours"
        )
    }
}
