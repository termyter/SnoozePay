import UIKit

/// "ЭТА НЕДЕЛЯ" card of the statistics screen (#348, `SPMore4.jsx` `Stats()`,
/// artboard `27-stats`): a seven-column saved/lost money chart with the
/// "Сэкономили / Потратили / Чистый" totals below a hairline divider.
///
/// Composition rather than inheritance — `SPCard` is `final`, so the card
/// surface is an inner view pinned to this wrapper's edges. That also keeps
/// `StatisticsViewController` free of another dozen stored labels.
///
/// Deliberate departures from the JSX reference, all reviewed and kept:
/// the caps title and the legend stack on two lines instead of sharing one
/// baseline row (the legend doesn't fit beside the title at iPhone widths);
/// and "Чистый" takes a semantic colour instead of the mock's flat white,
/// because the sign is the whole point of the figure.
final class SPWeekMoneyCard: UIView {

    // MARK: - Subviews

    private let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)
    private let barsView = SPWeekMoneyBarsView()
    private let savedValueLabel = SPSupport.makeMoneyValueLabel(color: AppColors.money400)
    private let spentValueLabel = SPSupport.makeMoneyValueLabel(color: AppColors.pain400)
    private let netValueLabel = SPSupport.makeMoneyValueLabel(color: AppColors.fg1)

    /// The totals row — swapped for `emptyLabel` when the week recorded
    /// nothing at all, so an untouched week doesn't publish a `+0 ₽` triplet
    /// that reads like a rendering bug. A *legitimate* zero (free alarms) does
    /// print, with `savingsNoteLabel` explaining it.
    private let totalsRow = UIStackView()
    private let emptyLabel: UILabel = {
        let label = SPSupport.makeMetaLabel("За эту неделю данных пока нет")
        label.numberOfLines = 0
        return label
    }()

    /// Explains a "—" or a legitimate zero in the savings column instead of
    /// leaving the user to guess. Copy is supplied by the view model, which
    /// is the only layer that knows *why* the figure came out that way.
    private let savingsNoteLabel: UILabel = {
        let label = SPSupport.makeMetaLabel()
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    /// Shown instead of the chart + totals when the ledger couldn't be read.
    /// The card deliberately stays on screen: a card that silently vanishes
    /// between launches is as dishonest as one that prints made-up money
    /// (#348 verification, finding 3).
    private let unavailableLabel: UILabel = {
        let label = SPSupport.makeMetaLabel(color: AppColors.warn300)
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let legendLabel = SPSupport.makeMetaLabel(
        "зелёное — сэкономлено · красное — потеряно"
    )

    private let divider: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.stroke1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - API

    /// Feeds the chart and the totals from **one** snapshot — the view model
    /// computes both in `loadData`, so the bars and the numbers are always
    /// derived from the same read of the clock and the same ledger.
    func apply(
        days: [StatisticsViewModel.WeekMoneyDay],
        summary: StatisticsViewModel.MoneySummary,
        savingsNote: String? = nil
    ) {
        barsView.days = days
        applyValue(savedValueLabel, amount: summary.saved, color: AppColors.money400)
        applyValue(spentValueLabel, amount: -summary.spent, color: AppColors.pain400)
        // The net figure carries the verdict, so it takes the semantic colour
        // rather than staying neutral like the design's static mock.
        let netColor: UIColor
        switch summary.net {
        case .some(let net) where net > 0: netColor = AppColors.money400
        case .some(let net) where net < 0: netColor = AppColors.pain400
        default: netColor = AppColors.fg1
        }
        applyValue(netValueLabel, amount: summary.net, color: netColor)

        legendLabel.isHidden = false
        barsView.isHidden = false
        divider.isHidden = false
        unavailableLabel.isHidden = true
        totalsRow.isHidden = summary.isEmpty
        emptyLabel.isHidden = !summary.isEmpty
        savingsNoteLabel.text = savingsNote
        savingsNoteLabel.isHidden = savingsNote == nil
    }

    /// Ledger-unavailable state: the title stays, everything numeric goes, and
    /// `reason` explains which failure hit. Callers pass
    /// `StatisticsViewModel.MoneyUnavailableReason.message`.
    func applyUnavailable(_ message: String) {
        legendLabel.isHidden = true
        barsView.isHidden = true
        divider.isHidden = true
        totalsRow.isHidden = true
        emptyLabel.isHidden = true
        savingsNoteLabel.isHidden = true
        unavailableLabel.isHidden = false
        unavailableLabel.text = message
    }

    private func applyValue(_ label: UILabel, amount: Double?, color: UIColor) {
        label.textColor = color
        label.attributedText = StatisticsViewModel.signedMoneyAttributed(
            amount, digitsFont: AppTypography.moneyMd, color: color
        )
        label.accessibilityLabel = StatisticsViewModel.signedMoneyText(amount)
    }

    // MARK: - Layout

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        barsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let caps = SPSupport.makeCapsLabel("ЭТА НЕДЕЛЯ")
        legendLabel.numberOfLines = 0

        buildTotalsRow()

        let stack = UIStackView(arrangedSubviews: [
            caps, legendLabel, barsView, divider, totalsRow, savingsNoteLabel,
            emptyLabel, unavailableLabel
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.sp2
        stack.setCustomSpacing(AppSpacing.sp4, after: legendLabel)
        stack.setCustomSpacing(AppSpacing.sp4, after: barsView)
        stack.setCustomSpacing(AppSpacing.sp4, after: divider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),

            divider.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func buildTotalsRow() {
        totalsRow.axis = .horizontal
        totalsRow.alignment = .top
        totalsRow.distribution = .fillEqually
        totalsRow.spacing = AppSpacing.sp2
        totalsRow.translatesAutoresizingMaskIntoConstraints = false
        [
            ("Сэкономили", savedValueLabel, NSTextAlignment.left),
            ("Потратили", spentValueLabel, .center),
            ("Чистый", netValueLabel, .right)
        ].forEach { caption, valueLabel, alignment in
            totalsRow.addArrangedSubview(
                SPWeekMoneyCard.makeTotalColumn(
                    caption: caption, valueLabel: valueLabel, alignment: alignment
                )
            )
        }
    }

    // MARK: - Builders

    private static func makeTotalColumn(
        caption: String,
        valueLabel: UILabel,
        alignment: NSTextAlignment
    ) -> UIView {
        let captionLabel = SPSupport.makeMetaLabel(caption, alignment: alignment)
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.8
        valueLabel.textAlignment = alignment

        let column = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = AppSpacing.sp1
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
    }
}
