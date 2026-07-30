import UIKit

/// "ВРЕМЯ ПОДЪЁМА" card of the statistics screen (#348, `SPMore4.jsx`
/// `Stats()`, artboard `27-stats`): three columns — "В среднем" (current
/// two-week mean), "Раньше было" (the two weeks before it, struck through)
/// and "Раньше на" (the delta in minutes, tinted by direction).
///
/// The host hides the whole card when `StatisticsViewModel.wakeTimeStats`
/// is `nil`; when only the baseline is missing this card drops the last two
/// columns and explains why, instead of inventing a comparison.
final class SPWakeTimeCard: UIView {

    // MARK: - Subviews

    private let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)

    private let averageValueLabel = SPWakeTimeCard.makeValueLabel(color: AppColors.fg1)
    private let baselineValueLabel = SPWakeTimeCard.makeValueLabel(color: AppColors.fg3)
    private let deltaValueLabel = SPWakeTimeCard.makeValueLabel(color: AppColors.money400)

    private let deltaCaptionLabel = SPWakeTimeCard.makeCaptionLabel(alignment: .right)

    private var baselineColumn = UIView()
    private var deltaColumn = UIView()

    /// Shown instead of the comparison columns until a previous window's
    /// worth of wake history exists.
    private let pendingLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.textAlignment = .right
        label.text = "Сравнение появится, когда наберётся история"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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

    func apply(_ stats: StatisticsViewModel.WakeTimeStats) {
        averageValueLabel.text = StatisticsViewModel.clockText(minutes: stats.averageMinutes)

        guard let baseline = stats.baselineMinutes, let delta = stats.deltaMinutes else {
            baselineColumn.isHidden = true
            deltaColumn.isHidden = true
            pendingLabel.isHidden = false
            return
        }
        baselineColumn.isHidden = false
        deltaColumn.isHidden = false
        pendingLabel.isHidden = true

        baselineValueLabel.attributedText = NSAttributedString(
            string: StatisticsViewModel.clockText(minutes: baseline),
            attributes: [
                .font: AppTypography.moneyMd,
                .foregroundColor: AppColors.fg3,
                // The design strikes the old average through — it's the value
                // the user has left behind.
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: AppColors.fg3
            ]
        )
        deltaCaptionLabel.text = StatisticsViewModel.wakeDeltaCaption(minutes: delta)
        let deltaColor = delta > 0
            ? AppColors.money400
            : (delta < 0 ? AppColors.pain400 : AppColors.fg2)
        deltaValueLabel.textColor = deltaColor
        deltaValueLabel.attributedText = SPWakeTimeCard.deltaAttributed(
            StatisticsViewModel.wakeDeltaValueText(minutes: delta),
            color: deltaColor
        )
    }

    /// Re-fonts the space before "мин" with the proportional sans — the same
    /// trick `MoneyFormatter.attributed` uses for `₽`. JetBrains Mono renders
    /// U+0020 at a full ~0.6em advance, which made "14 мин" read as "14  мин".
    private static func deltaAttributed(_ text: String, color: UIColor) -> NSAttributedString {
        let mono = AppTypography.moneyMd
        let attributes: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: color]
        guard let spaceIndex = text.firstIndex(of: " ") else {
            return NSAttributedString(string: text, attributes: attributes)
        }
        let result = NSMutableAttributedString(
            string: String(text[text.startIndex..<spaceIndex]), attributes: attributes
        )
        result.append(NSAttributedString(
            string: " ",
            attributes: [
                .font: AppFonts.sans(.regular, mono.pointSize),
                .foregroundColor: color
            ]
        ))
        result.append(NSAttributedString(
            string: String(text[text.index(after: spaceIndex)...]), attributes: attributes
        ))
        return result
    }

    // MARK: - Layout

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let caps = SPWakeTimeCard.makeCapsLabel("ВРЕМЯ ПОДЪЁМА", color: AppColors.fg3)
        let averageColumn = SPWakeTimeCard.makeColumn(
            caption: SPWakeTimeCard.makeCaptionLabel(alignment: .left, text: "В среднем"),
            valueLabel: averageValueLabel,
            alignment: .left
        )
        baselineColumn = SPWakeTimeCard.makeColumn(
            caption: SPWakeTimeCard.makeCaptionLabel(alignment: .center, text: "Раньше было"),
            valueLabel: baselineValueLabel,
            alignment: .center
        )
        deltaColumn = SPWakeTimeCard.makeColumn(
            caption: deltaCaptionLabel,
            valueLabel: deltaValueLabel,
            alignment: .right
        )

        let columnsRow = UIStackView(arrangedSubviews: [averageColumn, baselineColumn, deltaColumn])
        columnsRow.axis = .horizontal
        columnsRow.alignment = .top
        columnsRow.distribution = .fillEqually
        columnsRow.spacing = AppSpacing.sp2
        columnsRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [caps, columnsRow, pendingLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AppSpacing.sp2
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
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
    }

    // MARK: - Builders

    private static func makeColumn(
        caption: UILabel,
        valueLabel: UILabel,
        alignment: NSTextAlignment
    ) -> UIView {
        valueLabel.textAlignment = alignment
        let column = UIStackView(arrangedSubviews: [caption, valueLabel])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = AppSpacing.sp1
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
    }

    private static func makeCaptionLabel(
        alignment: NSTextAlignment,
        text: String? = nil
    ) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.text = text
        label.textAlignment = alignment
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
