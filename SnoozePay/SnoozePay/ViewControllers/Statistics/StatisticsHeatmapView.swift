import UIKit

/// Calendar-month heatmap for the V3 statistics hero card (#235, artboards
/// 27/27a). Renders a Пн–Вс header row plus one row of rounded squares per
/// week of the current month. Cell colour encodes the day's snooze status:
/// money gradient = "встал сразу", warn = 1–2 snoozes, pain = 3+, near-black
/// = no alarm / padding / future.
///
/// Tapping a cell shows a tonal selection ring around it and a tooltip bubble
/// below (date + status + optional spent amount, arrow pointing at the cell).
/// Tapping the selected cell again, or anywhere outside the grid, hides it.
///
/// Layout is manual (`layoutSubviews`) rather than collection-view based —
/// the grid is a fixed ≤42 views and the ring/tooltip overlay needs absolute
/// frames anyway.
final class StatisticsHeatmapView: UIView {

    // MARK: - Public API

    /// Replace the rendered days. Resets any active selection.
    var days: [StatisticsViewModel.HeatmapDay] = [] {
        didSet {
            clearSelection()
            rebuildCells()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// Supplies tooltip copy for a tapped day — wired to
    /// `StatisticsViewModel.tooltip(for:)` so the view stays a pure renderer.
    var tooltipProvider: ((StatisticsViewModel.HeatmapDay) -> StatisticsViewModel.HeatmapTooltip)?

    /// Fired when the tooltip shows/hides so the owning VC can fix z-order
    /// (the bubble may overlap the next card in the stack).
    var onSelectionChanged: ((Bool) -> Void)?

    // MARK: - Constants

    private static let columnCount = 7
    private static let cellSpacing: CGFloat = 4
    private static let cellCornerRadius: CGFloat = 5
    private static let headerHeight: CGFloat = 16
    private static let ringInset: CGFloat = 4
    private static let tooltipGap: CGFloat = 10

    // MARK: - Subviews

    private var headerLabels: [UILabel] = []
    private var cellViews: [HeatmapDayCell] = []
    private let ringView = UIView()
    private let tooltipView = HeatmapTooltipView()
    private var selectedIndex: Int?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        backgroundColor = .clear
        // Tooltip below the last row must escape the grid bounds.
        clipsToBounds = false

        for text in StatisticsViewModel.weekdayShortLabels {
            let label = UILabel()
            label.text = text.uppercased()
            label.font = AppFonts.sans(.semibold, 10)
            label.textColor = AppColors.fg3
            label.textAlignment = .center
            headerLabels.append(label)
            addSubview(label)
        }

        ringView.isUserInteractionEnabled = false
        ringView.layer.borderWidth = 2
        ringView.layer.cornerRadius = Self.cellCornerRadius + Self.ringInset
        ringView.layer.cornerCurve = .continuous
        ringView.isHidden = true
        addSubview(ringView)

        tooltipView.isHidden = true
        addSubview(tooltipView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    // MARK: - Cells

    private func rebuildCells() {
        cellViews.forEach { $0.removeFromSuperview() }
        cellViews = days.map { day in
            let cell = HeatmapDayCell()
            cell.apply(status: day.status)
            insertSubview(cell, belowSubview: ringView)
            return cell
        }
    }

    // MARK: - Layout

    private var cellSide: CGFloat {
        let totalGutter = Self.cellSpacing * CGFloat(Self.columnCount - 1)
        return max(8, floor((bounds.width - totalGutter) / CGFloat(Self.columnCount)))
    }

    private func frameForCell(at index: Int) -> CGRect {
        let side = cellSide
        let row = index / Self.columnCount
        let column = index % Self.columnCount
        // Distribute the rounding remainder by anchoring each column to its
        // fractional slot so the 7th column stays flush with the right edge.
        let slot = (bounds.width + Self.cellSpacing) / CGFloat(Self.columnCount)
        let x = CGFloat(column) * slot
        let y = Self.headerHeight + Self.cellSpacing + CGFloat(row) * (side + Self.cellSpacing)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let slot = (bounds.width + Self.cellSpacing) / CGFloat(Self.columnCount)
        for (index, label) in headerLabels.enumerated() {
            label.frame = CGRect(
                x: CGFloat(index) * slot,
                y: 0,
                width: slot - Self.cellSpacing,
                height: Self.headerHeight
            )
        }
        for (index, cell) in cellViews.enumerated() {
            cell.frame = frameForCell(at: index)
        }
        layoutSelectionOverlay()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        guard !days.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: Self.headerHeight)
        }
        let rowCount = Int(ceil(Double(days.count) / Double(Self.columnCount)))
        let side = cellSide
        let gridHeight = side * CGFloat(rowCount) + Self.cellSpacing * CGFloat(max(0, rowCount - 1))
        return CGSize(
            width: UIView.noIntrinsicMetric,
            height: Self.headerHeight + Self.cellSpacing + gridHeight
        )
    }

    // MARK: - Selection + tooltip (artboard 27a)

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard
            let index = cellViews.firstIndex(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }),
            index < days.count,
            index != selectedIndex
        else {
            clearSelection()
            return
        }
        selectedIndex = index
        if let tooltip = tooltipProvider?(days[index]) {
            tooltipView.apply(tooltip)
            tooltipView.isHidden = false
        }
        ringView.isHidden = false
        ringView.layer.borderColor = Self.ringColor(for: days[index].status).cgColor
        layoutSelectionOverlay()
        onSelectionChanged?(true)
    }

    /// Hides the ring + tooltip. Safe to call repeatedly.
    func clearSelection() {
        guard selectedIndex != nil || !tooltipView.isHidden else { return }
        selectedIndex = nil
        ringView.isHidden = true
        tooltipView.isHidden = true
        onSelectionChanged?(false)
    }

    private func layoutSelectionOverlay() {
        guard let index = selectedIndex, index < cellViews.count else { return }
        let cellFrame = frameForCell(at: index)
        ringView.frame = cellFrame.insetBy(dx: -Self.ringInset, dy: -Self.ringInset)

        let size = tooltipView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        // Clamp horizontally inside the grid so edge-column tooltips don't
        // run off-screen; the arrow keeps pointing at the cell regardless.
        var x = cellFrame.midX - size.width / 2
        x = max(0, min(x, bounds.width - size.width))
        let y = cellFrame.maxY + Self.tooltipGap
        tooltipView.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        tooltipView.setArrowCenterX(cellFrame.midX - x)
    }

    // MARK: - Status palette

    static func ringColor(for status: StatisticsViewModel.DayStatus) -> UIColor {
        switch status {
        case .woke: return AppColors.money300.withAlphaComponent(0.6)
        case .light: return AppColors.warn300.withAlphaComponent(0.7)
        case .heavy: return AppColors.pain300.withAlphaComponent(0.7)
        case .empty: return AppColors.fg1.withAlphaComponent(0.4)
        }
    }

    static func toneColor(for status: StatisticsViewModel.DayStatus) -> UIColor {
        switch status {
        case .woke: return AppColors.money300
        case .light: return AppColors.warn300
        case .heavy: return AppColors.pain300
        case .empty: return AppColors.fg3
        }
    }

    /// Gradient stops matching the heatmap cell fill for each status — used by
    /// the tooltip swatch so it mirrors the tapped cell rather than a flat tone
    /// (#289). `nil` for `.empty` (the swatch falls back to the flat tone).
    static func gradientStops(
        for status: StatisticsViewModel.DayStatus
    ) -> (colors: [CGColor], locations: [NSNumber])? {
        switch status {
        case .woke: return (SPSupport.moneyGradientColors, SPSupport.moneyGradientLocations)
        case .light: return (SPSupport.warnGradientColors, SPSupport.warnGradientLocations)
        case .heavy: return (SPSupport.painGradientColors, SPSupport.painGradientLocations)
        case .empty: return nil
        }
    }
}

// MARK: - Day cell

/// Single rounded square. Gradient fill for the woke/light/heavy statuses,
/// flat near-black overlay for empty days.
private final class HeatmapDayCell: UIView {

    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        layer.insertSublayer(gradient, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    func apply(status: StatisticsViewModel.DayStatus) {
        switch status {
        case .woke:
            gradient.isHidden = false
            gradient.colors = SPSupport.moneyGradientColors
            gradient.locations = SPSupport.moneyGradientLocations
        case .light:
            gradient.isHidden = false
            gradient.colors = SPSupport.warnGradientColors
            gradient.locations = SPSupport.warnGradientLocations
        case .heavy:
            gradient.isHidden = false
            gradient.colors = SPSupport.painGradientColors
            gradient.locations = SPSupport.painGradientLocations
        case .empty:
            gradient.isHidden = true
            backgroundColor = AppColors.whiteOverlay04
        }
        if status != .empty {
            backgroundColor = .clear
        }
    }
}

// MARK: - Tooltip bubble

/// Tooltip from artboard 27a — bg3 bubble with a hairline border, drop
/// shadow, an upward arrow, the date headline and a swatch + status line.
private final class HeatmapTooltipView: UIView {

    private let arrowView = UIView()
    private let dateLabel = UILabel()
    private let swatchView = UIView()
    /// Gradient fill for the swatch so it matches the tapped cell's gradient
    /// (#289). Hidden for `.empty`, where the flat tone is used instead.
    private let swatchGradient = CAGradientLayer()
    private let statusLabel = UILabel()
    private let spentLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        backgroundColor = AppColors.bg3
        layer.cornerRadius = AppRadius.sm
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = AppColors.whiteOverlay08.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowOffset = CGSize(width: 0, height: 12)
        layer.shadowRadius = 16
        isUserInteractionEnabled = false

        arrowView.backgroundColor = AppColors.bg3
        arrowView.layer.borderWidth = 1
        arrowView.layer.borderColor = AppColors.whiteOverlay08.cgColor
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        addSubview(arrowView)

        dateLabel.font = AppFonts.sans(.bold, 14)
        dateLabel.textColor = AppColors.fg1
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        swatchView.layer.cornerRadius = 2
        swatchView.layer.masksToBounds = true
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchGradient.startPoint = SPSupport.gradientStart
        swatchGradient.endPoint = SPSupport.gradientEnd
        swatchView.layer.insertSublayer(swatchGradient, at: 0)

        statusLabel.font = AppFonts.sans(.semibold, 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        spentLabel.font = AppFonts.sans(.medium, 12)
        spentLabel.textColor = AppColors.fg3
        spentLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = UIStackView(arrangedSubviews: [swatchView, statusLabel, spentLabel])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 6
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [dateLabel, statusRow])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = AppSpacing.sp1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            swatchView.widthAnchor.constraint(equalToConstant: 8),
            swatchView.heightAnchor.constraint(equalToConstant: 8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
    }

    func apply(_ tooltip: StatisticsViewModel.HeatmapTooltip) {
        dateLabel.text = tooltip.dateText
        statusLabel.text = tooltip.statusText
        statusLabel.textColor = StatisticsHeatmapView.toneColor(for: tooltip.status)
        if let stops = StatisticsHeatmapView.gradientStops(for: tooltip.status) {
            swatchGradient.isHidden = false
            swatchGradient.colors = stops.colors
            swatchGradient.locations = stops.locations
            swatchView.backgroundColor = .clear
        } else {
            swatchGradient.isHidden = true
            swatchView.backgroundColor = StatisticsHeatmapView.toneColor(for: tooltip.status)
        }
        spentLabel.text = tooltip.spentText
        spentLabel.isHidden = tooltip.spentText == nil
    }

    /// Positions the upward arrow so it points at the tapped cell even when
    /// the bubble itself is clamped to the grid edges.
    func setArrowCenterX(_ centerX: CGFloat) {
        let side: CGFloat = 12
        let clamped = max(side, min(centerX, bounds.width - side))
        arrowView.frame = CGRect(x: clamped - side / 2, y: -side / 2, width: side, height: side)
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the shadow path in sync so the arrow doesn't cast a hole.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
        swatchGradient.frame = swatchView.bounds
    }
}
