import UIKit

/// Statistics screen: spending summary, bar chart, streak.
class StatisticsViewController: UIViewController {

    // MARK: - ViewModel

    private let viewModel = StatisticsViewModel()

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = AppSpacing.lg
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let periodSegment: UISegmentedControl = {
        let items = StatisticsViewModel.Period.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    // Summary card
    private let totalLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 48, weight: .thin)
        l.textColor = AppColors.accentOrange
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let totalTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Потрачено на откладывание"
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let snoozeCountLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 17)
        l.textColor = .label
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Chart view
    private let chartView = BarChartView()

    // Streak view
    private let streakLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        l.textColor = AppColors.accentOrange
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Motivational message
    private let motivationLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 15)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Статистика"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground
        setupUI()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let period = StatisticsViewModel.Period(rawValue: periodSegment.selectedSegmentIndex) ?? .week
        viewModel.loadData(period: period)
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: AppSpacing.lg),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: AppSpacing.lg),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -AppSpacing.lg),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -AppSpacing.lg),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -AppSpacing.xxl)
        ])

        // Period selector
        periodSegment.addTarget(self, action: #selector(periodChanged), for: .valueChanged)
        contentStack.addArrangedSubview(periodSegment)

        // Summary card
        let summaryCard = makeCard()
        let summaryStack = UIStackView(arrangedSubviews: [totalTitleLabel, totalLabel, snoozeCountLabel])
        summaryStack.axis = .vertical
        summaryStack.spacing = 4
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(summaryStack)
        NSLayoutConstraint.activate([
            summaryStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: AppSpacing.lg),
            summaryStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -AppSpacing.lg),
            summaryStack.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: AppSpacing.lg),
            summaryStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -AppSpacing.lg)
        ])
        contentStack.addArrangedSubview(summaryCard)

        // Chart
        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let chartCard = makeCard()
        chartCard.addSubview(chartView)
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: chartCard.topAnchor, constant: AppSpacing.md),
            chartView.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor, constant: AppSpacing.md),
            chartView.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor, constant: -AppSpacing.md),
            chartView.bottomAnchor.constraint(equalTo: chartCard.bottomAnchor, constant: -AppSpacing.md)
        ])
        contentStack.addArrangedSubview(chartCard)

        // Streak card
        let streakCard = makeCard()
        let streakStack = UIStackView(arrangedSubviews: [streakLabel, motivationLabel])
        streakStack.axis = .vertical
        streakStack.spacing = 8
        streakStack.translatesAutoresizingMaskIntoConstraints = false
        streakCard.addSubview(streakStack)
        NSLayoutConstraint.activate([
            streakStack.leadingAnchor.constraint(equalTo: streakCard.leadingAnchor, constant: AppSpacing.lg),
            streakStack.trailingAnchor.constraint(equalTo: streakCard.trailingAnchor, constant: -AppSpacing.lg),
            streakStack.topAnchor.constraint(equalTo: streakCard.topAnchor, constant: AppSpacing.lg),
            streakStack.bottomAnchor.constraint(equalTo: streakCard.bottomAnchor, constant: -AppSpacing.lg)
        ])
        contentStack.addArrangedSubview(streakCard)
    }

    private func makeCard() -> UIView {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = AppRadius.md
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func bindViewModel() {
        viewModel.onDataUpdated = { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        totalLabel.text = viewModel.totalSpentFormatted
        snoozeCountLabel.text = "Откладываний: \(viewModel.snoozeCountFormatted)"
        streakLabel.text = viewModel.streak > 0 ? "🔥 \(viewModel.streakMessage)" : ""
        motivationLabel.text = viewModel.motivationalMessage
        chartView.data = viewModel.dailyChartData
    }

    // MARK: - Actions

    @objc private func periodChanged() {
        let period = StatisticsViewModel.Period(rawValue: periodSegment.selectedSegmentIndex) ?? .week
        viewModel.loadData(period: period)
    }
}

// MARK: - Simple bar chart view

/// Minimal bar chart — columns scaled to max value with day labels below.
final class BarChartView: UIView {

    var data: [(label: String, amount: Double)] = [] {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard !data.isEmpty, let ctx = UIGraphicsGetCurrentContext() else { return }

        let maxAmount = data.map { $0.amount }.max() ?? 1
        let barWidth = rect.width / CGFloat(data.count) - 4
        let labelHeight: CGFloat = 20
        let chartHeight = rect.height - labelHeight

        for (index, item) in data.enumerated() {
            let x = CGFloat(index) * (barWidth + 4)
            let barHeight = maxAmount > 0 ? CGFloat(item.amount / maxAmount) * chartHeight : 0

            // Bar
            let barRect = CGRect(
                x: x,
                y: chartHeight - barHeight,
                width: barWidth,
                height: barHeight
            )
            ctx.setFillColor(UIColor.systemOrange.withAlphaComponent(0.7).cgColor)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: 3)
            ctx.addPath(path.cgPath)
            ctx.fillPath()

            // Label
            let label = item.label as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let labelSize = label.size(withAttributes: attrs)
            let labelX = x + (barWidth - labelSize.width) / 2
            label.draw(at: CGPoint(x: labelX, y: chartHeight + 4), withAttributes: attrs)
        }
    }
}
