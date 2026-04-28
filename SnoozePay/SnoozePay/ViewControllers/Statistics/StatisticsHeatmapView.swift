import UIKit

/// GitHub-style heatmap calendar for the statistics screen.
///
/// Renders a 7-column × N-row grid of small squares (12pt at the smallest
/// scale, growing to fill horizontal space) where each square's tint encodes
/// the day's penalty total. The intensity bucket (0..4) comes pre-computed
/// from `StatisticsViewModel.HeatmapCell` so the view stays a pure renderer.
///
/// We use `UICollectionView` with a compositional layout instead of a hand-
/// rolled stack-of-stacks because:
///   1. Tap targets need cells (toast-on-tap surfaces date + amount).
///   2. The grid scales smoothly from 7 cells (week) → 84 cells (all-time)
///      without re-laying out an arbitrary stack tree on every period change.
///
/// The cell size is derived from the available width inside `layoutSubviews`
/// so a 7-cell wide row always packs flush; the height grows with row count.
final class StatisticsHeatmapView: UIView {

    // MARK: - Public API

    /// Replace the rendered cells. Triggers a collection-view reload and
    /// (since rows depend on cell count) a layout pass via
    /// `invalidateIntrinsicContentSize`.
    var cells: [StatisticsViewModel.HeatmapCell] = [] {
        didSet {
            collectionView.reloadData()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// Triggered when the user taps a cell — caller surfaces a toast / alert.
    var onCellTap: ((StatisticsViewModel.HeatmapCell) -> Void)?

    // MARK: - Constants

    /// Number of columns. The spec is GitHub-style — Monday → Sunday.
    private static let columnCount = 7
    /// Inner spacing between squares (matches `--sp-r-xs` / 4px gutter).
    private static let cellSpacing: CGFloat = 4
    /// Square corner radius — the spec calls for 3pt.
    static let cellCornerRadius: CGFloat = 3

    // MARK: - Subviews

    private let collectionView: UICollectionView
    private let flowLayout = UICollectionViewFlowLayout()

    // MARK: - Init

    override init(frame: CGRect) {
        flowLayout.scrollDirection = .vertical
        flowLayout.minimumInteritemSpacing = Self.cellSpacing
        flowLayout.minimumLineSpacing = Self.cellSpacing
        flowLayout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Compute cell side from current width — 7 columns + 6 gutters.
        let availableWidth = bounds.width
        let totalGutter = Self.cellSpacing * CGFloat(Self.columnCount - 1)
        let side = max(8, floor((availableWidth - totalGutter) / CGFloat(Self.columnCount)))
        if flowLayout.itemSize.width != side {
            flowLayout.itemSize = CGSize(width: side, height: side)
            flowLayout.invalidateLayout()
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        guard !cells.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        let rowCount = Int(ceil(Double(cells.count) / Double(Self.columnCount)))
        let side = flowLayout.itemSize.height > 0 ? flowLayout.itemSize.height : 12
        let height = side * CGFloat(rowCount) + Self.cellSpacing * CGFloat(max(0, rowCount - 1))
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isScrollEnabled = false
        collectionView.register(HeatmapCellView.self, forCellWithReuseIdentifier: HeatmapCellView.reuseID)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - Data + Delegate

extension StatisticsHeatmapView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        cells.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HeatmapCellView.reuseID,
                for: indexPath
            ) as? HeatmapCellView,
            indexPath.item < cells.count
        else { return UICollectionViewCell() }
        cell.apply(intensity: cells[indexPath.item].intensity)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < cells.count else { return }
        onCellTap?(cells[indexPath.item])
    }
}

// MARK: - Heatmap cell

/// Single square in the heatmap grid. Maps `intensity` (0..4) onto a tint
/// from the money palette so a denser day reads as a "more saved" colour.
/// Bucket 0 is the empty `whiteOverlay06` token — same affordance the
/// streak-modal uses for future / muted days.
private final class HeatmapCellView: UICollectionViewCell {

    static let reuseID = "HeatmapCellView"

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = StatisticsHeatmapView.cellCornerRadius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available; the legacy override below
        // remains as a fallback for older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: HeatmapCellView, _) in
                view.refreshDynamicColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes get the refresh through the registered observer
        // (see init); skip here so we don't refresh twice.
        if #available(iOS 17.0, *) { return }
        refreshDynamicColors()
    }

    private func refreshDynamicColors() {
        // Re-resolve dynamic colours so a light/dark switch re-tints buckets
        // 0 (whiteOverlay06) without leaving the previous theme baked in.
        contentView.backgroundColor = contentView.backgroundColor?.resolvedColor(with: traitCollection)
    }

    func apply(intensity: Int) {
        contentView.backgroundColor = Self.color(for: intensity)
    }

    /// Map a 0..4 bucket onto the money palette. 0 is the empty cell —
    /// `whiteOverlay06` so it matches the streak-modal "future / muted"
    /// affordance. 1..4 lerp between `money300` and `money700` so the
    /// gradient reads as "more saved → deeper green".
    private static func color(for intensity: Int) -> UIColor {
        switch intensity {
        case 0: return AppColors.whiteOverlay06
        case 1: return SPSupport.lerpColor(AppColors.money300, AppColors.money700, progress: 0.0)
        case 2: return SPSupport.lerpColor(AppColors.money300, AppColors.money700, progress: 0.33)
        case 3: return SPSupport.lerpColor(AppColors.money300, AppColors.money700, progress: 0.66)
        default: return AppColors.money700
        }
    }
}
