import UIKit

/// "ЭТА НЕДЕЛЯ" card of the statistics screen (#348, `SPMore4.jsx` `Stats()`,
/// artboard `27-stats`): a seven-column saved/lost money chart with the
/// "Сэкономили / Потратили / Чистый" totals below a hairline divider.
///
/// Composition rather than inheritance — `SPCard` is `final`, so the card
/// surface is an inner view pinned to this wrapper's edges. That also keeps
/// `StatisticsViewController` free of another dozen stored labels.
final class SPWeekMoneyCard: UIView {

    // MARK: - Subviews

    private let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)
    private let barsView = SPWeekMoneyBarsView()
    private let savedValueLabel = SPWeekMoneyCard.makeValueLabel(color: AppColors.money400)
    private let spentValueLabel = SPWeekMoneyCard.makeValueLabel(color: AppColors.pain400)
    private let netValueLabel = SPWeekMoneyCard.makeValueLabel(color: AppColors.fg1)

    /// The totals row — swapped for `emptyLabel` when the week carries
    /// neither savings nor charges, so the card never shows a `+0 ₽` triplet
    /// that reads like a rendering bug.
    private let totalsRow = UIStackView()
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.text = "За эту неделю данных пока нет"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

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

    /// Feeds the chart and the totals. `days` drives the columns; `summary`
    /// is expected to be `StatisticsViewModel.moneySummary(days:)` of the
    /// same array so the bars and the numbers can never disagree.
    func apply(
        days: [StatisticsViewModel.WeekMoneyDay],
        summary: StatisticsViewModel.MoneySummary
    ) {
        barsView.days = days
        savedValueLabel.text = StatisticsViewModel.signedMoneyText(summary.saved)
        spentValueLabel.text = StatisticsViewModel.signedMoneyText(-summary.spent)
        netValueLabel.text = StatisticsViewModel.signedMoneyText(summary.net)
        // The net figure carries the verdict, so it takes the semantic colour
        // rather than staying neutral like the design's static mock.
        netValueLabel.textColor = summary.net > 0
            ? AppColors.money400
            : (summary.net < 0 ? AppColors.pain400 : AppColors.fg1)
        totalsRow.isHidden = summary.isEmpty
        emptyLabel.isHidden = !summary.isEmpty
    }

    // MARK: - Layout

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        barsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let caps = SPWeekMoneyCard.makeCapsLabel("ЭТА НЕДЕЛЯ", color: AppColors.fg3)
        let legend = UILabel()
        legend.font = AppTypography.meta
        legend.textColor = AppColors.fg3
        legend.numberOfLines = 0
        legend.text = "зелёное — сэкономлено · красное — потеряно"
        legend.translatesAutoresizingMaskIntoConstraints = false

        buildTotalsRow()

        let stack = UIStackView(arrangedSubviews: [
            caps, legend, barsView, divider, totalsRow, emptyLabel
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.sp2
        stack.setCustomSpacing(AppSpacing.sp4, after: legend)
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
        let captionLabel = UILabel()
        captionLabel.font = AppTypography.meta
        captionLabel.textColor = AppColors.fg3
        captionLabel.text = caption
        captionLabel.textAlignment = alignment
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.8
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.textAlignment = alignment

        let column = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = AppSpacing.sp1
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
    }

    private static func makeValueLabel(color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.moneyMd
        label.textColor = color
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func makeCapsLabel(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: color
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
