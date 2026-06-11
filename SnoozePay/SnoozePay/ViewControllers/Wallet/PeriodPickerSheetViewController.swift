import UIKit

/// Period picker bottom sheet — V3 design `PeriodPickerSheet` in
/// `docs/design/v2-handoff/components/SPMore3.jsx` (artboards 21a/21b,
/// issue #234).
///
/// Presented over the (dimmed) transaction-history screen as a page sheet.
/// Layout, top-down: drag handle → "Период" header + "Сбросить" text button
/// → selected-range summary row → years, each with a 4×3 month grid →
/// money CTA "Применить".
///
/// Selection follows calendar range-selection conventions: tap one month for
/// a single-month period, tap a second month to extend into a range (the
/// in-between months get a continuous light fill, the endpoints render as
/// solid discs with dark text). Months after the current one are disabled.
/// Tap rules live in `TxHistoryPeriodSelection` so they stay unit-testable.
final class PeriodPickerSheetViewController: UIViewController {

    // MARK: - State

    private var selection: TxHistoryPeriodSelection
    private let years: [Int]
    private let currentMonth: YearMonth
    /// Called on "Применить". `nil` means the selection was reset — the
    /// caller falls back to its default period (current month).
    private let onApply: (TxHistoryPeriod?) -> Void

    private var cells: [YearMonth: MonthCell] = [:]

    // MARK: - Subviews

    private let dragHandle: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay12
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let summaryContainer: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay06
        view.layer.cornerRadius = AppRadius.sm
        return view
    }()

    private let summaryDot: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.fg1
        view.layer.cornerRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = AppFonts.sans(.semibold, 14)
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let summaryCountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var applyButton: SPButton = {
        let button = SPButton(title: "Применить", variant: .money, size: .lg, fullWidth: true)
        button.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - selected: Period currently applied on the history screen.
    ///   - years: Years to render grids for (ascending, e.g. `[2024, 2025,
    ///     2026]`) — derived from the oldest recorded transaction.
    ///   - now: Injectable clock; months after `now`'s month are disabled.
    ///   - onApply: Receives the chosen period (`nil` after "Сбросить").
    init(
        selected: TxHistoryPeriod?,
        years: [Int],
        now: Date = Date(),
        onApply: @escaping (TxHistoryPeriod?) -> Void
    ) {
        self.selection = TxHistoryPeriodSelection(period: selected)
        self.years = years
        self.currentMonth = YearMonth(date: now)
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            if #available(iOS 16.0, *) {
                let custom = UISheetPresentationController.Detent.custom(
                    identifier: UISheetPresentationController.Detent.Identifier("snoozepay.periodpicker")
                ) { context in
                    min(640, context.maximumDetentValue)
                }
                sheet.detents = [custom, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = false  // we render our own handle
            sheet.preferredCornerRadius = AppRadius.xl
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg1
        setupLayout()
        refreshSelectionUI()
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(dragHandle)
        view.addSubview(scrollView)
        view.addSubview(applyButton)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeHeaderRow())
        contentStack.addArrangedSubview(makeSummaryRow())
        for year in years {
            contentStack.addArrangedSubview(makeYearBlock(year: year))
        }

        applyButton.translatesAutoresizingMaskIntoConstraints = false

        let inset = AppSpacing.screenInset
        NSLayoutConstraint.activate([
            dragHandle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            dragHandle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            scrollView.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: AppSpacing.sp4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -AppSpacing.sp3),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: inset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -inset
            ),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * inset
            ),

            applyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            applyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            applyButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -AppSpacing.sp3
            )
        ])
    }

    private func makeHeaderRow() -> UIView {
        let title = UILabel()
        title.attributedText = NSAttributedString(
            string: "Период",
            attributes: [
                .font: AppTypography.h3,
                .kern: -20 * 0.01,
                .foregroundColor: AppColors.fg1
            ]
        )

        let reset = UIButton(type: .system)
        reset.setTitle("Сбросить", for: .normal)
        reset.titleLabel?.font = AppFonts.sans(.medium, 14)
        reset.setTitleColor(AppColors.fg3, for: .normal)
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [title, UIView(), reset])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func makeSummaryRow() -> UIView {
        summaryContainer.addSubview(summaryDot)
        summaryContainer.addSubview(summaryLabel)
        summaryContainer.addSubview(summaryCountLabel)
        NSLayoutConstraint.activate([
            summaryContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),

            summaryDot.leadingAnchor.constraint(
                equalTo: summaryContainer.leadingAnchor, constant: 14
            ),
            summaryDot.centerYAnchor.constraint(equalTo: summaryContainer.centerYAnchor),
            summaryDot.widthAnchor.constraint(equalToConstant: 6),
            summaryDot.heightAnchor.constraint(equalToConstant: 6),

            summaryLabel.leadingAnchor.constraint(equalTo: summaryDot.trailingAnchor, constant: 10),
            summaryLabel.topAnchor.constraint(equalTo: summaryContainer.topAnchor, constant: 10),
            summaryLabel.bottomAnchor.constraint(equalTo: summaryContainer.bottomAnchor, constant: -10),

            summaryCountLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: summaryLabel.trailingAnchor, constant: AppSpacing.sp2
            ),
            summaryCountLabel.trailingAnchor.constraint(
                equalTo: summaryContainer.trailingAnchor, constant: -14
            ),
            summaryCountLabel.centerYAnchor.constraint(equalTo: summaryContainer.centerYAnchor)
        ])
        return summaryContainer
    }

    private func makeYearBlock(year: Int) -> UIView {
        let caption = UILabel()
        caption.attributedText = NSAttributedString(
            string: "\(year)",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )

        // 4×3 grid: zero column gap so the range fill reads as one continuous
        // strip; 6pt row gap (SPMore3.jsx L300-307).
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 6
        for rowStart in stride(from: 1, through: 12, by: 4) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 0
            for month in rowStart..<(rowStart + 4) {
                let yearMonth = YearMonth(year: year, month: month)
                let cell = MonthCell(month: yearMonth, column: (month - 1) % 4) { [weak self] in
                    self?.monthTapped(yearMonth)
                }
                cells[yearMonth] = cell
                row.addArrangedSubview(cell)
            }
            grid.addArrangedSubview(row)
        }

        let block = UIStackView(arrangedSubviews: [caption, grid])
        block.axis = .vertical
        block.spacing = AppSpacing.sp2
        return block
    }

    // MARK: - Actions

    private func monthTapped(_ month: YearMonth) {
        selection.tap(month)
        refreshSelectionUI()
    }

    @objc private func resetTapped() {
        selection.reset()
        refreshSelectionUI()
    }

    @objc private func applyTapped() {
        onApply(selection.period)
        dismiss(animated: true)
    }

    // MARK: - Selection rendering

    private func refreshSelectionUI() {
        let period = selection.period
        if let period {
            summaryLabel.text = period.pickerCaption
            summaryCountLabel.text = period.monthCountText
        } else {
            summaryLabel.text = "Выберите месяц"
            summaryCountLabel.text = nil
        }
        for (month, cell) in cells {
            cell.apply(
                role: Self.role(of: month, in: period),
                isFuture: month > currentMonth
            )
        }
    }

    static func role(of month: YearMonth, in period: TxHistoryPeriod?) -> MonthCellRole {
        guard let period, period.contains(month) else { return .none }
        if month == period.start && month == period.end { return .single }
        if month == period.start { return .start }
        if month == period.end { return .end }
        return .mid
    }
}

// MARK: - Month cell

/// Position of a month inside the selected range — drives the fill shape
/// (rounded vs. square edges) and the endpoint disc.
enum MonthCellRole {
    case none
    /// Single-month selection — disc only, no range strip.
    case single
    case start
    case mid
    case end
}

/// One month in the picker grid. Two layers: a full-width range-fill strip
/// (light overlay, square edges towards the range interior) and the label
/// pill on top (solid disc for endpoints).
private final class MonthCell: UIControl {

    private let month: YearMonth
    /// 0...3 — position inside the 4-column grid row; outer row edges of a
    /// range fill get rounded so the strip doesn't bleed past the grid.
    private let column: Int
    private let onTap: () -> Void

    private let fillView = UIView()
    private let pill = UILabel()

    init(month: YearMonth, column: Int, onTap: @escaping () -> Void) {
        self.month = month
        self.column = column
        self.onTap = onTap
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true

        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.backgroundColor = AppColors.whiteOverlay08
        fillView.isUserInteractionEnabled = false
        addSubview(fillView)

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.text = month.gridLabel
        pill.textAlignment = .center
        pill.layer.cornerRadius = 18
        pill.layer.masksToBounds = true
        pill.isUserInteractionEnabled = false
        addSubview(pill)

        NSLayoutConstraint.activate([
            fillView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor),

            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            pill.heightAnchor.constraint(equalToConstant: 36)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(YearMonth.fullNames[month.month - 1]) \(month.year)"
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap() {
        onTap()
    }

    func apply(role: MonthCellRole, isFuture: Bool) {
        isEnabled = !isFuture

        // Range strip: rounded on the outer edge of the range, square towards
        // its interior so consecutive cells merge into one continuous fill.
        // The outer edges of each grid row also round (smaller radius) so the
        // strip wraps cleanly when the range spans multiple rows
        // (SPMore3.jsx L314-339).
        switch role {
        case .none, .single:
            fillView.isHidden = true
        case .start, .mid, .end:
            fillView.isHidden = false
            var corners: CACornerMask = []
            if role == .start || column == 0 {
                corners.insert(.layerMinXMinYCorner)
                corners.insert(.layerMinXMaxYCorner)
            }
            if role == .end || column == 3 {
                corners.insert(.layerMaxXMinYCorner)
                corners.insert(.layerMaxXMaxYCorner)
            }
            let isEndpointEdge = role == .start || role == .end
            fillView.layer.cornerRadius = corners.isEmpty ? 0 : (isEndpointEdge ? 18 : 14)
            fillView.layer.maskedCorners = corners
        }

        let isEndpoint = role == .single || role == .start || role == .end
        if isEndpoint {
            pill.backgroundColor = AppColors.fg1
            pill.textColor = AppColors.bg0
            pill.font = AppFonts.sans(.bold, 14)
        } else {
            pill.backgroundColor = .clear
            pill.font = AppFonts.sans(.medium, 14)
            if isFuture {
                pill.textColor = AppColors.fg4
            } else {
                pill.textColor = role == .mid ? AppColors.fg1 : AppColors.fg2
            }
        }
    }
}
