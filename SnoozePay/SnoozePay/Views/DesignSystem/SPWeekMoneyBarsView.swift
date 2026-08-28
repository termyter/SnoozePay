import UIKit

/// "ЭТА НЕДЕЛЯ" money chart (#348, `SPMore4.jsx` `Stats()`, artboard
/// `27-stats`). Seven Monday-first columns; each stacks the day's lost
/// roubles on top (pain gradient) and the saved roubles below (money
/// gradient), with the weekday caption underneath.
///
/// Hand-rolled UIKit with manual `layoutSubviews` — same reasoning as
/// `StatisticsWeekdayBarsView`: the stacked two-segment bars with
/// segment-dependent corner masks are cheaper to lay out directly than to
/// coax out of Swift Charts.
final class SPWeekMoneyBarsView: UIView {

    // MARK: - Public API

    var days: [StatisticsViewModel.WeekMoneyDay] = [] {
        didSet {
            rebuild()
            setNeedsLayout()
        }
    }

    // MARK: - Constants

    /// Chart height per the JSX (`height: 120` for the bar row + caption).
    private static let chartHeight: CGFloat = 140
    private static let columnGap = AppSpacing.sp2
    private static let captionHeight: CGFloat = 14
    private static let rowGap = AppSpacing.sp2
    /// Gap between the lost and saved segments of the same column.
    private static let segmentGap: CGFloat = 2
    private static let cornerRadius: CGFloat = 6
    private static let tightRadius: CGFloat = 2
    /// Floor so a token amount still reads as a visible sliver.
    private static let minSegmentHeight: CGFloat = 4

    // MARK: - Subviews

    private var columns: [Column] = []

    private struct Column {
        let lostBar: MoneySegmentView
        let savedBar: MoneySegmentView
        let captionLabel: UILabel
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Build

    private func rebuild() {
        columns.forEach {
            $0.lostBar.removeFromSuperview()
            $0.savedBar.removeFromSuperview()
            $0.captionLabel.removeFromSuperview()
        }
        columns = days.map { day in
            let lostBar = MoneySegmentView(kind: .lost)
            lostBar.isHidden = day.spent <= 0
            addSubview(lostBar)

            let savedBar = MoneySegmentView(kind: .saved)
            savedBar.isHidden = day.savedHeightValue <= 0
            addSubview(savedBar)

            let captionLabel = UILabel()
            captionLabel.font = AppFonts.sans(.medium, 11)
            captionLabel.textAlignment = .center
            captionLabel.text = day.label
            // Future days of the current week stay dimmed — they carry no
            // data yet and shouldn't read as "nothing happened".
            captionLabel.textColor = day.isPastOrToday ? AppColors.fg3 : AppColors.fg4
            addSubview(captionLabel)

            return Column(lostBar: lostBar, savedBar: savedBar, captionLabel: captionLabel)
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
        // Scale against the tallest *stack* so the busiest day fills the
        // chart and every other column stays proportional to it. (The JSX
        // mock scales against the tallest single value; stacking is the
        // honest axis once a day can carry both a saving and a loss.)
        let peak = days.map { $0.savedHeightValue + $0.spent }.max() ?? 0
        let barAreaBottom = bounds.height - Self.captionHeight - Self.rowGap
        let barAreaHeight = max(0, barAreaBottom)

        for (index, column) in columns.enumerated() {
            let day = days[index]
            let originX = CGFloat(index) * (columnWidth + Self.columnGap)
            let savedValue = day.savedHeightValue
            let savedHeight = height(for: savedValue, peak: peak, available: barAreaHeight)
            let lostHeight = height(for: day.spent, peak: peak, available: barAreaHeight)

            let savedTop = barAreaBottom - savedHeight
            column.savedBar.frame = CGRect(
                x: originX, y: savedTop, width: columnWidth, height: savedHeight
            )
            let lostBottom = savedValue > 0 ? savedTop - Self.segmentGap : barAreaBottom
            column.lostBar.frame = CGRect(
                x: originX, y: lostBottom - lostHeight, width: columnWidth, height: lostHeight
            )
            column.savedBar.applyCorners(
                top: day.spent > 0 ? Self.tightRadius : Self.cornerRadius,
                bottom: Self.cornerRadius
            )
            column.lostBar.applyCorners(
                top: Self.cornerRadius,
                bottom: savedValue > 0 ? Self.tightRadius : Self.cornerRadius
            )
            column.captionLabel.frame = CGRect(
                x: originX,
                y: bounds.height - Self.captionHeight,
                width: columnWidth,
                height: Self.captionHeight
            )
        }
    }

    /// Proportional segment height with a visible floor for non-zero values.
    /// `available` is reduced by the inter-segment gap so a stacked column
    /// can never overflow the chart area.
    private func height(for value: Double, peak: Double, available: CGFloat) -> CGFloat {
        guard value > 0, peak > 0, available > 0 else { return 0 }
        let usable = max(0, available - Self.segmentGap)
        return max(Self.minSegmentHeight, usable * CGFloat(value / peak))
    }
}

// MARK: - Segment

/// One gradient segment of a week column — money (saved) or pain (lost).
private final class MoneySegmentView: UIView {

    enum Kind {
        case saved
        case lost
    }

    private let gradient = CAGradientLayer()
    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        switch kind {
        case .saved: gradient.locations = SPSupport.moneyGradientLocations
        case .lost: gradient.locations = SPSupport.painGradientLocations
        }
        layer.addSublayer(gradient)
        layer.masksToBounds = true
        refreshGradientColors()
        // `CAGradientLayer.colors` holds plain `CGColor`s — resolved once and
        // frozen, so a segment built in one theme kept that theme's ramp for
        // the rest of the session. Same defect as `WalletWeeklyChartView`
        // (#494) and `SPCard` (#507).
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MoneySegmentView, _) in
                view.refreshGradientColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshGradientColors()
    }

    /// Re-resolve the ramp against THIS view's traits. Called from `init` and
    /// from the trait-change registration above.
    private func refreshGradientColors() {
        switch kind {
        case .saved: gradient.colors = SPSupport.moneyGradientColors(for: traitCollection)
        case .lost: gradient.colors = SPSupport.painGradientColors(for: traitCollection)
        }
    }

    /// Rounds the two ends independently so stacked segments meet flush.
    /// A single `layer.cornerRadius` can't express "6pt on top, 2pt below",
    /// so the shape is masked with a bezier path rebuilt on every layout.
    func applyCorners(top: CGFloat, bottom: CGFloat) {
        topRadius = top
        bottomRadius = bottom
        setNeedsLayout()
    }

    private var topRadius: CGFloat = 6
    private var bottomRadius: CGFloat = 6

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let maxRadius = min(bounds.height / 2, bounds.width / 2)
        installMask(
            top: min(topRadius, maxRadius),
            bottom: min(bottomRadius, maxRadius)
        )
    }

    /// `UIBezierPath(byRoundingCorners:)` only takes one radius for all the
    /// corners it rounds, and appending two such paths unions them back into
    /// a plain rect — so the asymmetric outline is traced explicitly.
    private func installMask(top: CGFloat, bottom: CGFloat) {
        let rect = bounds
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY),
            controlPoint: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + top),
            controlPoint: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            controlPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            controlPoint: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.close()
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        layer.mask = shape
    }
}
