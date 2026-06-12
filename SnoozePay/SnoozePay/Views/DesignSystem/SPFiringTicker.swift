import UIKit

/// History ticker for the firing screen — the row of coloured mini-pills that
/// summarise today's snooze charges in the centred hero block.
///
/// Spec — `SPDawnV3.jsx:114-136` (`TickerRow`): a caps «СЕГОДНЯ» eyebrow, then
/// one chip per charged snooze separated by a thin «·». Each chip shows the
/// rounded rouble amount and tints amber when the charge was under 200 ₽, red
/// when it was 200 ₽ or more. This replaces the old single-line mono text
/// summary that lived above the CTA.
///
/// The amount → tint mapping is pure logic, so it lives in `SPFiringTickerEntry`
/// (unit-tested) and the view just renders the entries.
enum SPFiringTicker {

    /// One charge in today's snooze history.
    struct Entry: Equatable {
        /// Rounded rouble amount charged for this snooze.
        let amount: Int

        /// Tint threshold per `SPDawnV3.jsx:120-121`: amber below 200 ₽, red at
        /// or above 200 ₽.
        var isHeavy: Bool { amount >= 200 }

        /// Chip text colour. `pain300` (coral) for heavy charges, `warn300`
        /// (amber) otherwise.
        var textColor: UIColor { isHeavy ? AppColors.pain300 : AppColors.warn300 }

        /// Chip background fill — the same hue at ~18% so the pill reads as a
        /// soft wash, matching `rgba(244,82,63,.18)` / `rgba(245,158,11,.18)`.
        var fillColor: UIColor {
            (isHeavy ? AppColors.pain500 : AppColors.warn500).withAlphaComponent(0.18)
        }
    }

    /// Map a chronological list of penalty amounts (doubles, as the VM emits
    /// them) to rounded ticker entries.
    static func entries(from penalties: [Double]) -> [Entry] {
        penalties.map { Entry(amount: Int($0.rounded())) }
    }

    /// Build the chip row view for the supplied entries. Returns a horizontal
    /// stack: «СЕГОДНЯ» caps eyebrow, then the chips interleaved with thin «·»
    /// dots. Returns an empty (hidden) stack when there's no history yet.
    static func makeRow(for entries: [Entry]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AppSpacing.sp2 - 2   // 6pt — matches the JSX `gap: 6`
        row.isHidden = entries.isEmpty
        guard !entries.isEmpty else { return row }

        let eyebrow = UILabel()
        eyebrow.attributedText = NSAttributedString(
            string: "СЕГОДНЯ",
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.18,
                .foregroundColor: UIColor.white.withAlphaComponent(0.45)
            ]
        )
        row.addArrangedSubview(eyebrow)

        let chips = UIStackView()
        chips.axis = .horizontal
        chips.alignment = .center
        chips.spacing = AppSpacing.sp1   // 4pt — matches the JSX inner `gap: 4`
        for (index, entry) in entries.enumerated() {
            chips.addArrangedSubview(makeChip(entry))
            if index < entries.count - 1 {
                chips.addArrangedSubview(makeSeparator())
            }
        }
        row.addArrangedSubview(chips)
        return row
    }

    private static func makeChip(_ entry: SPFiringTicker.Entry) -> UIView {
        let label = SPPaddedLabel(insets: UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8))
        label.attributedText = NSAttributedString(
            string: "−\(entry.amount)",
            attributes: [
                .font: AppTypography.moneySm,
                .foregroundColor: entry.textColor
            ]
        )
        label.backgroundColor = entry.fillColor
        label.layer.cornerRadius = AppRadius.pill
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private static func makeSeparator() -> UILabel {
        let dot = UILabel()
        dot.text = "·"
        dot.font = AppFonts.sans(.medium, 10)
        dot.textColor = UIColor.white.withAlphaComponent(0.25)
        return dot
    }
}

/// Minimal padded-label used for the ticker chips so the pill background hugs
/// the text with the spec's 3×8 inset. Kept private-ish to the ticker module.
final class SPPaddedLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
