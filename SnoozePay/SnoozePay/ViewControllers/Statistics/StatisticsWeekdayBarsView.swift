import UIKit

/// "По дням недели" bar chart (#235, artboard 27). Seven columns, each a
/// value label on top, a bar in the middle and a weekday caption below.
/// The worst day renders in the pain gradient with a tinted shadow; zero
/// days collapse to a 4pt dashed outline; everything else is a muted
/// white-overlay bar.
///
/// Hand-rolled UIKit (manual `layoutSubviews`) instead of Swift Charts —
/// the dashed zero-bars and per-bar gradient/shadow treatment are bespoke
/// enough that fighting Charts' bar styling would cost more than 7 views.
final class StatisticsWeekdayBarsView: UIView {

    // MARK: - Public API

    var stats: [StatisticsViewModel.WeekdayStat] = [] {
        didSet {
            rebuild()
            setNeedsLayout()
        }
    }

    // MARK: - Constants

    private static let chartHeight: CGFloat = 132
    private static let columnGap: CGFloat = 8
    private static let valueHeight: CGFloat = 14
    private static let captionHeight: CGFloat = 14
    private static let rowGap: CGFloat = 6
    /// `fileprivate` so the bar itself rounds its gradient to the same radius —
    /// a private member would be invisible to `WeekdayBarView` below.
    fileprivate static let barCornerRadius: CGFloat = 6
    private static let zeroBarHeight: CGFloat = 4
    private static let minBarRatio: CGFloat = 0.08

    // MARK: - Subviews

    private var columns: [Column] = []

    private struct Column {
        let valueLabel: UILabel
        let bar: WeekdayBarView
        let captionLabel: UILabel
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Build

    private func rebuild() {
        columns.forEach {
            $0.valueLabel.removeFromSuperview()
            $0.bar.removeFromSuperview()
            $0.captionLabel.removeFromSuperview()
        }
        columns = stats.map { stat in
            let valueLabel = UILabel()
            valueLabel.font = AppFonts.sans(.bold, 12)
            valueLabel.textAlignment = .center
            valueLabel.text = StatisticsViewModel.barValueText(stat.average)
            // 12pt bold — small text, so the worst day takes the light
            // theme's body step rather than the decorative 300 (3.01:1).
            valueLabel.textColor = stat.isWorst
                ? StatisticsAccentTones.pain
                : (stat.average == 0 ? AppColors.fg4 : AppColors.fg2)
            addSubview(valueLabel)

            let bar = WeekdayBarView()
            bar.apply(isWorst: stat.isWorst, isZero: stat.average == 0)
            addSubview(bar)

            let captionLabel = UILabel()
            captionLabel.font = AppFonts.sans(stat.isWorst ? .bold : .medium, 11)
            captionLabel.textAlignment = .center
            captionLabel.text = stat.label
            captionLabel.textColor = stat.isWorst ? AppColors.fg1 : AppColors.fg3
            addSubview(captionLabel)

            return Column(valueLabel: valueLabel, bar: bar, captionLabel: captionLabel)
        }
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.chartHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !columns.isEmpty else { return }
        let count = CGFloat(columns.count)
        let columnWidth = (bounds.width - Self.columnGap * (count - 1)) / count
        let maxValue = max(stats.map(\.average).max() ?? 0, 0.001)
        let barAreaTop = Self.valueHeight + Self.rowGap
        let barAreaBottom = bounds.height - Self.captionHeight - Self.rowGap
        let barAreaHeight = max(0, barAreaBottom - barAreaTop)

        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * (columnWidth + Self.columnGap)
            let stat = stats[index]
            let barHeight: CGFloat
            if stat.average == 0 {
                barHeight = Self.zeroBarHeight
            } else {
                let ratio = max(Self.minBarRatio, CGFloat(stat.average / maxValue))
                barHeight = barAreaHeight * ratio
            }
            column.bar.frame = CGRect(
                x: x,
                y: barAreaBottom - barHeight,
                width: columnWidth,
                height: barHeight
            )
            column.valueLabel.frame = CGRect(
                x: x,
                y: column.bar.frame.minY - Self.rowGap - Self.valueHeight,
                width: columnWidth,
                height: Self.valueHeight
            )
            column.captionLabel.frame = CGRect(
                x: x,
                y: bounds.height - Self.captionHeight,
                width: columnWidth,
                height: Self.captionHeight
            )
        }
    }
}

// MARK: - Bar

/// Single weekday bar: pain gradient + shadow for the worst day, dashed
/// outline for zero days, muted overlay otherwise.
private final class WeekdayBarView: UIView {

    private let gradient = CAGradientLayer()
    private let dashLayer = CAShapeLayer()
    private var isWorst = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = StatisticsWeekdayBarsView.barCornerRadius
        layer.cornerCurve = .continuous
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.locations = SPSupport.painGradientLocations
        gradient.cornerRadius = StatisticsWeekdayBarsView.barCornerRadius
        layer.addSublayer(gradient)

        dashLayer.fillColor = UIColor.clear.cgColor
        dashLayer.lineWidth = 1.5
        dashLayer.lineDashPattern = [4, 3]
        layer.addSublayer(dashLayer)

        refreshPalette()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (bar: WeekdayBarView, _) in
            bar.refreshPalette()
        }
    }

    /// Gradient stops and the tinted shadow are CGColors — they don't follow
    /// a theme flip on their own.
    private func refreshPalette() {
        traitCollection.performAsCurrent {
            gradient.colors = SPSupport.painGradientColors
        }
        guard isWorst else { return }
        layer.shadowColor = AppColors.pain500.resolvedColor(with: traitCollection).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(isWorst: Bool, isZero: Bool) {
        self.isWorst = isWorst
        gradient.isHidden = !isWorst
        dashLayer.isHidden = !isZero
        backgroundColor = (isWorst || isZero) ? .clear : AppColors.whiteOverlay12
        if isWorst {
            layer.shadowOpacity = 0.30
            layer.shadowOffset = CGSize(width: 0, height: AppSpacing.sp1)
            layer.shadowRadius = 7
            refreshPalette()
        } else {
            layer.shadowOpacity = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        dashLayer.strokeColor = AppColors.whiteOverlay12.resolvedColor(with: traitCollection).cgColor
        dashLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            cornerRadius: 3
        ).cgPath
    }
}
