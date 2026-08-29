import UIKit

/// «ВРЕМЯ ПОДЪЁМА» card of the statistics screen (#348, `SPMore4.jsx`
/// `Stats()`, artboard `27-stats`): three columns — «В среднем» (the typical
/// wake time of the last two weeks), «Раньше было» (the two weeks before it,
/// struck through) and «Раньше на» (the delta in minutes, tinted by
/// direction).
///
/// Three states, in order of how much history exists:
///   1. No wake instants at all → the host hides the card entirely.
///   2. Fewer than `minimumSamples` mornings → «Копим историю: нужно ещё N
///      утр». A median over one or two mornings is noise, not a habit.
///   3. Median available, baseline still short → the comparison columns drop
///      out rather than inventing a «раньше было».
final class SPWakeTimeCard: UIView {

    // MARK: - Subviews

    private let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)

    private let averageValueLabel = SPSupport.makeMoneyValueLabel(color: AppColors.fg1)
    private let baselineValueLabel = SPSupport.makeMoneyValueLabel(
        color: AppColors.fg3, alignment: .center
    )
    private let deltaValueLabel = SPSupport.makeMoneyValueLabel(
        color: AppColors.money400, alignment: .right
    )

    private let deltaCaptionLabel = SPSupport.makeMetaLabel(alignment: .right)

    private var columnsRow = UIStackView()
    private var baselineColumn = UIView()
    private var deltaColumn = UIView()

    /// Shown instead of the comparison columns until a previous window's
    /// worth of wake history exists.
    private let pendingLabel: UILabel = {
        let label = SPSupport.makeMetaLabel(
            Localized.text("statistics.wake_time.pending"), alignment: .right
        )
        label.numberOfLines = 0
        return label
    }()

    /// Replaces the whole columns row while the recent window is below the
    /// sample threshold.
    private let accumulatingLabel: UILabel = {
        let label = SPSupport.makeMetaLabel()
        label.numberOfLines = 0
        label.isHidden = true
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
        guard let median = stats.medianMinutes else {
            // State 2 — some mornings recorded, not enough to call anything
            // typical yet.
            columnsRow.isHidden = true
            pendingLabel.isHidden = true
            accumulatingLabel.isHidden = false
            accumulatingLabel.text = StatisticsViewModel.wakeSamplesPendingText(
                stats.samplesUntilReady
            )
            return
        }
        columnsRow.isHidden = false
        accumulatingLabel.isHidden = true
        averageValueLabel.text = StatisticsViewModel.clockText(minutes: median)

        guard let baseline = stats.baselineMedianMinutes, let delta = stats.deltaMinutes else {
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
                // The design strikes the old figure through — it's the value
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

    /// Re-fonts the space before «мин» with the proportional sans — the same
    /// trick `MoneyFormatter.attributed` uses for `₽`. JetBrains Mono renders
    /// U+0020 at a full ~0.6em advance, which made «14 мин» read as «14  мин».
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

        let caps = SPSupport.makeCapsLabel(Localized.text("statistics.wake_time.caps"))
        let averageColumn = SPWakeTimeCard.makeColumn(
            caption: SPSupport.makeMetaLabel(Localized.text("statistics.wake_time.average")),
            valueLabel: averageValueLabel,
            alignment: .left
        )
        baselineColumn = SPWakeTimeCard.makeColumn(
            caption: SPSupport.makeMetaLabel(Localized.text("statistics.wake_time.baseline"), alignment: .center),
            valueLabel: baselineValueLabel,
            alignment: .center
        )
        deltaColumn = SPWakeTimeCard.makeColumn(
            caption: deltaCaptionLabel,
            valueLabel: deltaValueLabel,
            alignment: .right
        )

        columnsRow = UIStackView(arrangedSubviews: [averageColumn, baselineColumn, deltaColumn])
        columnsRow.axis = .horizontal
        columnsRow.alignment = .top
        columnsRow.distribution = .fillEqually
        columnsRow.spacing = AppSpacing.sp2
        columnsRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [
            caps, columnsRow, accumulatingLabel, pendingLabel
        ])
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
        caption.textAlignment = alignment
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.8
        valueLabel.textAlignment = alignment
        let column = UIStackView(arrangedSubviews: [caption, valueLabel])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = AppSpacing.sp1
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
    }
}
