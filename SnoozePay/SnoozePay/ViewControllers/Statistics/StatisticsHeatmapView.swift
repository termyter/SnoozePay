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
    private static let cellSpacing = AppSpacing.sp1
    /// Cell radius sits between `AppRadius`'s steps on purpose — a 40pt square
    /// takes the 8pt `xs` badly. Named rather than inlined so the grid and the
    /// selection ring can't drift apart.
    static let cellCornerRadius: CGFloat = 5
    private static let headerHeight = AppSpacing.sp4
    private static let ringInset = AppSpacing.sp1
    /// Gap between the tapped cell and the tooltip's arrow tip. Off the 4pt
    /// grid by design — the arrow eats 6pt of it, so `sp3` would read as a
    /// detached bubble. Named, not inlined, so it stays a decision.
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

        // The ring is a CALayer border, so its CGColor has to be re-resolved
        // by hand when the theme flips under an open selection.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StatisticsHeatmapView, _) in
            view.refreshRingColor()
        }
    }

    private func refreshRingColor() {
        guard let index = selectedIndex, index < days.count else { return }
        ringView.layer.borderColor = Self.ringColor(for: days[index].status)
            .resolvedColor(with: traitCollection).cgColor
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
        refreshRingColor()
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

    /// Selection ring. The dark alphas are the canon; light floors them at
    /// 0.70 because the woke ring at 0.60 is 2.70:1 on `bg2` — under the 3:1
    /// WCAG 1.4.11 bar for a UI affordance. At 0.70 it is 3.28:1.
    static func ringColor(for status: StatisticsViewModel.DayStatus) -> UIColor {
        let base: UIColor
        let darkAlpha: CGFloat
        switch status {
        case .woke: base = StatisticsAccentTones.money; darkAlpha = 0.6
        case .light: base = StatisticsAccentTones.warn; darkAlpha = 0.7
        case .heavy: base = StatisticsAccentTones.pain; darkAlpha = 0.7
        case .empty: base = AppColors.fg1; darkAlpha = 0.4
        }
        return UIColor { trait in
            let alpha = trait.userInterfaceStyle == .light ? max(darkAlpha, 0.7) : darkAlpha
            return base.resolvedColor(with: trait).withAlphaComponent(alpha)
        }
    }

    /// Flat tone for the tooltip's status line — 12pt semibold, so it needs
    /// the light theme's body-text step (`StatisticsAccentTones`), not the
    /// decorative 300 the dark canon uses.
    static func toneColor(for status: StatisticsViewModel.DayStatus) -> UIColor {
        switch status {
        case .woke: return StatisticsAccentTones.money
        case .light: return StatisticsAccentTones.warn
        case .heavy: return StatisticsAccentTones.pain
        case .empty: return AppColors.fg3
        }
    }

    /// Fill for a day with no alarm (padding / future / untracked).
    ///
    /// The dark canon is `whiteOverlay04` — a 2.9 ΔE00 whisper against `bg2`,
    /// just enough to draw the calendar's skeleton. The same 4% ink on the
    /// light card is only 1.9 ΔE00, i.e. below the just-noticeable difference:
    /// the empty days vanish and the month loses its shape. 6% ink restores
    /// exactly the dark theme's perceptual weight (2.9 ΔE00) without
    /// promoting an empty day to something that looks like data.
    static let emptyFillColor = UIColor { trait in
        let token = trait.userInterfaceStyle == .light
            ? AppColors.whiteOverlay06
            : AppColors.whiteOverlay04
        return token.resolvedColor(with: trait)
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
    private var status: StatisticsViewModel.DayStatus = .empty

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = StatisticsHeatmapView.cellCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        layer.insertSublayer(gradient, at: 0)
        // A CAGradientLayer holds resolved CGColors, which never re-resolve on
        // their own. Without this the whole month keeps the palette of
        // whichever theme was active when the grid was built.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: HeatmapDayCell, _) in
            cell.applyPalette()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    func apply(status: StatisticsViewModel.DayStatus) {
        self.status = status
        applyPalette()
    }

    private func applyPalette() {
        // `performAsCurrent` so the dynamic tokens inside `SPSupport` resolve
        // against *this view's* traits rather than whatever
        // `UITraitCollection.current` happens to be when the grid is rebuilt.
        traitCollection.performAsCurrent {
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
                backgroundColor = StatisticsHeatmapView.emptyFillColor
            }
        }
        if status != .empty {
            backgroundColor = .clear
        }
    }
}
