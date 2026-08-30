import UIKit

/// 7-day mini chart — `WalletV2` «Последние 7 дней» section in
/// `docs/design/v2-handoff/components/SPScreensV2.jsx` (L450-467).
///
/// Each column is a day. Non-zero days render the pain gradient bar; the
/// height encodes the relative penalty total (max in window → full height),
/// with a floor so a small penalty still reads as a bar. Empty days render a
/// shorter half-opacity `whiteOverlay08` stub so the row reads as a 7-step
/// rhythm rather than a sparse line — and so "no spending" is told apart from
/// "a little spending" by HEIGHT, not by hue alone (#635).
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
        /// Height of the stub drawn for a day with no penalties. Matches the
        /// canon's flat 4pt track (`SPScreensV2.jsx` L456).
        static let emptyTrackHeight: CGFloat = 4
        /// Floor for a day that DOES have penalties. Deliberately taller than
        /// `emptyTrackHeight`: a −50 ₽ day against a −650 ₽ week resolves to
        /// 3pt, and at the old shared 4pt floor it rendered pixel-identical to
        /// a day with no spending at all — leaving hue as the only signal, and
        /// red-on-grey is the pair colour vision loss collapses first (#635).
        static let minDataBarHeight: CGFloat = 10
        /// Canon draws the empty stub at half opacity (`opacity: .5`), so the
        /// rhythm of seven steps stays visible without reading as data.
        static let emptyTrackAlpha: CGFloat = 0.5
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

    // MARK: - Bar geometry

    /// Tallest a data bar may grow. The column budget covers bar + gap +
    /// label, so the bar gets whatever the label pair leaves behind.
    static var maxBarHeight: CGFloat {
        Layout.barAreaHeight - Layout.labelHeight - Layout.labelTopGap
    }

    /// Resolve a bar height from an intensity in `0...1` (relative to the
    /// tallest bar in the window).
    ///
    /// Zero and non-zero take DIFFERENT floors on purpose — that separation
    /// is the whole point of #635. The linear mapping itself is untouched:
    /// only the clamp for small non-zero values moved, so every bar tall
    /// enough to clear `minDataBarHeight` keeps the exact height it had.
    static func barHeight(forIntensity intensity: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, intensity))
        guard clamped > 0 else { return Layout.emptyTrackHeight }
        return max(Layout.minDataBarHeight, maxBarHeight * clamped)
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
        bar.alpha = layoutSpec.emptyTrackAlpha
        bar.layer.cornerRadius = layoutSpec.barCornerRadius
        bar.layer.masksToBounds = true
        addSubview(bar)

        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.font = AppTypography.meta
        labelView.textColor = WalletQuietInk.caption
        labelView.textAlignment = .center
        addSubview(labelView)

        let height = bar.heightAnchor.constraint(equalToConstant: layoutSpec.emptyTrackHeight)
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
    /// non-zero intensity unhides the gradient and takes the taller data
    /// floor; zero falls back to the dimmed empty track.
    func setIntensity(_ intensity: CGFloat) {
        let clamped = max(0, min(1, intensity))
        barHeightConstraint?.constant = WalletWeeklyChartView.barHeight(forIntensity: clamped)
        if clamped > 0 {
            if gradient.superlayer !== bar.layer {
                bar.layer.addSublayer(gradient)
            }
            bar.backgroundColor = .clear
            bar.alpha = 1
        } else {
            gradient.removeFromSuperlayer()
            bar.backgroundColor = AppColors.whiteOverlay08
            bar.alpha = layoutSpec.emptyTrackAlpha
        }
        setNeedsLayout()
    }
}
