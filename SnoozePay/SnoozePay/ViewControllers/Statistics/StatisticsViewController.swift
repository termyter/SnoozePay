import UIKit
import SwiftUI
import Charts

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

    // Chart hosting controller
    private var chartHostingController: UIHostingController<StatisticsChartView>?

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

        // Chart card with embedded SwiftUI chart
        let chartCard = makeCard()
        chartCard.clipsToBounds = true

        let chartSwiftUIView = StatisticsChartView(data: [])
        let hostingController = UIHostingController(rootView: chartSwiftUIView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        chartCard.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: chartCard.topAnchor, constant: AppSpacing.md),
            hostingController.view.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor, constant: AppSpacing.md),
            hostingController.view.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor, constant: -AppSpacing.md),
            hostingController.view.bottomAnchor.constraint(equalTo: chartCard.bottomAnchor, constant: -AppSpacing.md),
            hostingController.view.heightAnchor.constraint(equalToConstant: 200)
        ])

        chartHostingController = hostingController
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
        // Update summary card with zero-state handling
        if viewModel.totalSpent > 0 {
            totalLabel.textColor = AppColors.accentOrange
            totalLabel.text = viewModel.totalSpentFormatted
        } else {
            totalLabel.textColor = .secondaryLabel
            totalLabel.text = "0 ₽"
        }

        if viewModel.snoozeCount > 0 {
            snoozeCountLabel.text = "Откладываний: \(viewModel.snoozeCountFormatted)"
        } else {
            snoozeCountLabel.text = "Откладываний: Ни разу"
        }

        streakLabel.text = viewModel.streak > 0 ? "🔥 \(viewModel.streakMessage)" : ""
        motivationLabel.text = viewModel.motivationalMessage

        // Update chart data with animation
        let chartData = viewModel.dailyChartData.map {
            ChartDataPoint(label: $0.label, amount: $0.amount)
        }
        chartHostingController?.rootView = StatisticsChartView(data: chartData)
    }

    // MARK: - Actions

    @objc private func periodChanged() {
        let period = StatisticsViewModel.Period(rawValue: periodSegment.selectedSegmentIndex) ?? .week
        viewModel.loadData(period: period)
    }
}

// MARK: - Swift Charts data model

/// Single data point for the bar chart.
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double
}

// MARK: - SwiftUI Chart View

/// Bar chart built with Swift Charts framework, wrapped for UIKit embedding.
struct StatisticsChartView: View {

    let data: [ChartDataPoint]

    @State private var animateChart = false

    var body: some View {
        if data.isEmpty || data.allSatisfy({ $0.amount == 0 }) {
            // Empty state
            VStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Нет данных")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(data) { point in
                BarMark(
                    x: .value("День", point.label),
                    y: .value("Сумма", animateChart ? point.amount : 0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .annotation(position: .top, spacing: 4) {
                    if point.amount > 0 {
                        Text("\(Int(point.amount)) ₽")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.caption)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text("\(Int(amount))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...(maxAmount * 1.2))
            .animation(.easeOut(duration: 0.5), value: animateChart)
            .onAppear {
                // Trigger entrance animation
                withAnimation(.easeOut(duration: 0.5)) {
                    animateChart = true
                }
            }
            .onChange(of: data.map(\.amount)) { oldValue, newValue in
                // Re-animate when data changes
                guard oldValue != newValue else { return }
                animateChart = false
                withAnimation(.easeOut(duration: 0.5)) {
                    animateChart = true
                }
            }
        }
    }

    /// Maximum amount in the data set, at least 1 to avoid zero-range axis.
    private var maxAmount: Double {
        max(data.map(\.amount).max() ?? 1, 1)
    }
}
