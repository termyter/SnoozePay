import UIKit

/// 7-day mini chart — `WalletV2` «Последние 7 дней» section in
/// `docs/design/v2-handoff/components/SPScreensV2.jsx` (L450-467).
///
/// Each column is a day. Non-zero days render the pain gradient bar; the
/// height encodes the relative penalty total (max in window → full height).
/// Empty days render a 4pt `whiteOverlay08` stub so the row reads as a
/// 7-step rhythm rather than a sparse line.
///
/// Data is supplied via `update(values:)` — an ordered `[Decimal]` of size 7
/// (oldest → newest). The caller resolves the day labels (П/В/С/Ч/П/С/В)
/// against `Calendar.current` so DST / locale shifts don't drift.
final class WalletWeeklyChartView: UIView {

    // MARK: - Configuration

    /// Layout constants — extracted so a future redesign that bumps the
    /// chart height doesn't have to chase magic numbers across the class.
    /// `fileprivate` so the nested helper `DayColumn` (kept private to
    /// this file) can refer to the same constants by type.
    fileprivate enum Layout {
        static let barCount = 7
        static let barAreaHeight: CGFloat = 60
        static let barCornerRadius: CGFloat = 4
        static let minBarHeight: CGFloat = 4
        static let labelHeight: CGFloat = 14
        static let columnGap: CGFloat = 4
        static let labelTopGap: CGFloat = 6
    }

    // MARK: - Subviews

    private var columns: [DayColumn] = []
    private let stack = UIStackView()

    // MARK: - State

    /// Day labels rendered under each bar, oldest → newest. Resolved from
    /// `Calendar.current` so the leftmost column is 6 days ago and the
    /// rightmost is today.
    private(set) var dayLabels: [String] = []

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        configure()
        dayLabels = Self.makeDayLabels()
        applyLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Replace the bar values. `values` must contain exactly 7 entries
    /// (oldest → newest). Extra entries are ignored; shorter arrays are
    /// padded with zero so the chart never collapses mid-render.
    func update(values: [Decimal]) {
        var padded = values
        if padded.count < Layout.barCount {
            padded.append(contentsOf: Array(
                repeating: Decimal.zero,
                count: Layout.barCount - padded.count
            ))
        }
        let window = Array(padded.prefix(Layout.barCount))
        let maxValue = window.max() ?? .zero
        for (idx, value) in window.enumerated() {
            let ratio: CGFloat
            if maxValue > 0 {
                let doubleValue = NSDecimalNumber(decimal: value).doubleValue
                let doubleMax = NSDecimalNumber(decimal: maxValue).doubleValue
                ratio = CGFloat(doubleValue / doubleMax)
            } else {
                ratio = 0
            }
            columns[idx].setIntensity(ratio)
        }
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = Layout.columnGap
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        for _ in 0..<Layout.barCount {
            let column = DayColumn(layout: Layout.self)
            columns.append(column)
            stack.addArrangedSubview(column)
        }
    }

    private func applyLabels() {
        for (idx, column) in columns.enumerated() where idx < dayLabels.count {
            column.setLabel(dayLabels[idx])
        }
    }

    /// Build the seven Cyrillic day initials (П/В/С/Ч/П/С/В) anchored on
    /// today. Index 0 is six days ago; index 6 is today.
    private static func makeDayLabels() -> [String] {
        // Derived from the locale's own standalone symbols rather than typed
        // out: `WeekdayNames.short` is Monday-first («Пн … Вс») and its first
        // letters are exactly the initials this chart used to carry as a
        // literal — the same equality #599 established for the full names.
        // Nothing on screen moves, and English arrives without a catalogue
        // entry, because a weekday initial is calendar data, not copy.
        let mondayFirst = WeekdayNames.short.map {
            $0.prefix(1).uppercased(with: AppLocale.display)
        }
        guard mondayFirst.count == Layout.barCount else { return [] }
        // `Calendar` numbers weekdays Sunday-first, so Sunday moves to front.
        let initials = [mondayFirst[6]] + mondayFirst.dropLast()
        let calendar = Calendar.current
        var labels: [String] = []
        for offset in (0..<Layout.barCount).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: date)
            // `weekday` is 1-based, Sunday = 1.
            let initial = initials[(weekday - 1) % 7]
            labels.append(initial)
        }
        return labels
    }
}

// MARK: - DayColumn

/// Vertical column = pain-gradient bar on top, caps label underneath.
/// Extracted as a nested class so `WalletWeeklyChartView` stays declarative
/// and the bar gradient mask doesn't escape the view's coordinate system.
private final class DayColumn: UIView {

    private let bar = UIView()
    private let labelView = UILabel()
    private let gradient = CAGradientLayer()
    private var barHeightConstraint: NSLayoutConstraint?
    private let layoutSpec: WalletWeeklyChartView.Layout.Type

    init(layout: WalletWeeklyChartView.Layout.Type) {
        self.layoutSpec = layout
        super.init(frame: .zero)
        configure()
        // `CAGradientLayer.colors` holds plain `CGColor`s — they are resolved
        // once and never follow a theme flip. Without this the bars keep the
        // theme the view was BUILT in: launch in dark, switch to light, and
        // the dark `pain300` top stop (`#FFB4A8`) stays put at 1.9:1 on the
        // white card. Same defect class as `SPAmountPreset` (#489).
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: DayColumn, _) in
            view.refreshGradientColors()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bar.bounds
        bar.layer.cornerRadius = layoutSpec.barCornerRadius
    }

    private func configure() {
        backgroundColor = .clear
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = AppColors.whiteOverlay08
        bar.layer.cornerRadius = layoutSpec.barCornerRadius
        bar.layer.masksToBounds = true
        addSubview(bar)

        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.font = AppTypography.meta
        labelView.textColor = WalletQuietInk.caption
        labelView.textAlignment = .center
        addSubview(labelView)

        let height = bar.heightAnchor.constraint(equalToConstant: layoutSpec.minBarHeight)
        barHeightConstraint = height

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: labelView.topAnchor, constant: -layoutSpec.labelTopGap),
            height,
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: trailingAnchor),
            labelView.bottomAnchor.constraint(equalTo: bottomAnchor),
            labelView.heightAnchor.constraint(equalToConstant: layoutSpec.labelHeight)
        ])

        gradient.locations = SPSupport.painGradientLocations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        refreshGradientColors()
    }

    /// Re-resolve the bar gradient against THIS view's traits. Called from
    /// `configure()` and from the trait-change registration above.
    func refreshGradientColors() {
        gradient.colors = SPSupport.painGradientColors(for: traitCollection)
    }

    func setLabel(_ text: String) {
        labelView.text = text
    }

    /// `intensity` is `0...1` relative to the tallest bar in the window. A
    /// non-zero intensity unhides the gradient; the min height keeps the
    /// stub legible even for very small values.
    func setIntensity(_ intensity: CGFloat) {
        let clamped = max(0, min(1, intensity))
        if clamped > 0 {
            // Total column = bar + gap + label. The bar can take everything
            // above the label/gap pair.
            let maxBarHeight = layoutSpec.barAreaHeight
                - layoutSpec.labelHeight
                - layoutSpec.labelTopGap
            let resolved = max(layoutSpec.minBarHeight, maxBarHeight * clamped)
            barHeightConstraint?.constant = resolved
            if gradient.superlayer !== bar.layer {
                bar.layer.addSublayer(gradient)
            }
            bar.backgroundColor = .clear
        } else {
            barHeightConstraint?.constant = layoutSpec.minBarHeight
            gradient.removeFromSuperlayer()
            bar.backgroundColor = AppColors.whiteOverlay08
        }
        setNeedsLayout()
    }
}
