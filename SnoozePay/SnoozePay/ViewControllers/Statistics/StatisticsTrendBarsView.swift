import UIKit

/// 8-week "Динамика откладываний" bar trend (#235, artboard 27). Eight thin
/// bars oldest → newest; the current week's bar is tinted by the trend
/// direction (money gradient = improving, muted = flat, pain gradient =
/// worse), the historical bars are a quiet white overlay.
final class StatisticsTrendBarsView: UIView {

    // MARK: - Public API

    func apply(
        points: [StatisticsViewModel.WeekTrendPoint],
        direction: StatisticsViewModel.TrendDirection
    ) {
        self.points = points
        self.direction = direction
        rebuild()
        setNeedsLayout()
    }

    // MARK: - State

    private var points: [StatisticsViewModel.WeekTrendPoint] = []
    private var direction: StatisticsViewModel.TrendDirection = .same
    private var barViews: [TrendBarView] = []

    // MARK: - Constants

    private static let chartHeight: CGFloat = 100
    private static let barGap: CGFloat = 6
    private static let minBarRatio: CGFloat = 0.06

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
        barViews.forEach { $0.removeFromSuperview() }
        barViews = points.map { point in
            let bar = TrendBarView()
            bar.apply(point: point, direction: direction)
            addSubview(bar)
            return bar
        }
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.chartHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !barViews.isEmpty else { return }
        let count = CGFloat(barViews.count)
        let barWidth = (bounds.width - Self.barGap * (count - 1)) / count
        let maxValue = max(points.map(\.count).max() ?? 0, 1)

        for (index, bar) in barViews.enumerated() {
            let ratio = max(Self.minBarRatio, CGFloat(points[index].count) / CGFloat(maxValue))
            let height = bounds.height * ratio
            bar.frame = CGRect(
                x: CGFloat(index) * (barWidth + Self.barGap),
                y: bounds.height - height,
                width: barWidth,
                height: height
            )
        }
    }
}

// MARK: - Bar

private final class TrendBarView: UIView {

    private let gradient = CAGradientLayer()
    private var isCurrent = false
    private var direction: StatisticsViewModel.TrendDirection = .same

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = AppSpacing.sp1
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        layer.insertSublayer(gradient, at: 0)
        // CAGradientLayer holds resolved CGColors; without this the current
        // week's bar keeps the palette of the theme it was built under.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (bar: TrendBarView, _) in
            bar.refreshPalette()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        point: StatisticsViewModel.WeekTrendPoint,
        direction: StatisticsViewModel.TrendDirection
    ) {
        isCurrent = point.isCurrent
        self.direction = direction
        refreshPalette()
    }

    private func refreshPalette() {
        guard isCurrent else {
            gradient.isHidden = true
            backgroundColor = AppColors.whiteOverlay12
            return
        }
        traitCollection.performAsCurrent {
            switch direction {
            case .better:
                gradient.isHidden = false
                gradient.colors = SPSupport.moneyGradientColors
                gradient.locations = SPSupport.moneyGradientLocations
                backgroundColor = .clear
            case .worse:
                gradient.isHidden = false
                gradient.colors = SPSupport.painGradientColors
                gradient.locations = SPSupport.painGradientLocations
                backgroundColor = .clear
            case .same:
                gradient.isHidden = true
                backgroundColor = AppColors.whiteOverlay24
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}
