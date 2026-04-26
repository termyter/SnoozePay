import UIKit
import SwiftUI
import Charts

/// Statistics screen: spending summary, bar chart, streak, motivation.
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

    // MARK: Two-column summary

    private let spentTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Потрачено"
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let spentAmountLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        l.textColor = AppColors.accentOrange
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let snoozeTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Откладываний"
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let snoozeCountLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: Average card

    private let averageTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Среднее"
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let averageValueLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: Chart

    private let chartTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "График по дням"
        l.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var chartHostingController: UIHostingController<StatisticsChartView>?

    /// Explicit reference to the streak card so `refresh()` can toggle its
    /// visibility without walking the view-hierarchy via `superview?.superview`.
    private var streakCard: UIView?

    // MARK: Streak

    private let streakIconView: UIView = {
        let container = UIView()
        container.backgroundColor = AppColors.accentOrange.withAlphaComponent(0.15)
        container.layer.cornerRadius = 22
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "🔥"
        label.font = UIFont.systemFont(ofSize: 22)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 44),
            container.heightAnchor.constraint(equalToConstant: 44),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }()

    private let streakLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let bestStreakLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: Motivation banner

    private let motivationCard: UIView = {
        let v = UIView()
        v.backgroundColor = AppColors.accentOrange
        v.layer.cornerRadius = AppRadius.md
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let motivationIconLabel: UILabel = {
        let l = UILabel()
        l.text = "↗️"
        l.font = UIFont.systemFont(ofSize: 24)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let motivationTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Мотивация"
        l.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let motivationMessageLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 14)
        l.textColor = UIColor.white.withAlphaComponent(0.9)
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

        // Two-column summary (Spent + Snooze Count)
        contentStack.addArrangedSubview(makeTwoColumnSummary())

        // Average card
        contentStack.addArrangedSubview(makeAverageCard())

        // Chart card
        contentStack.addArrangedSubview(makeChartCard())

        // Streak card
        let streakCardView = makeStreakCard()
        streakCard = streakCardView
        contentStack.addArrangedSubview(streakCardView)

        // Motivation banner
        contentStack.addArrangedSubview(makeMotivationBanner())
    }

    // MARK: - Card Builders

    private func makeTwoColumnSummary() -> UIView {
        // Left card — amount spent
        let leftCard = makeCard()
        let leftStack = UIStackView(arrangedSubviews: [spentTitleLabel, spentAmountLabel])
        leftStack.axis = .vertical
        leftStack.spacing = AppSpacing.xs
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftCard.addSubview(leftStack)
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leftCard.leadingAnchor, constant: AppSpacing.lg),
            leftStack.trailingAnchor.constraint(equalTo: leftCard.trailingAnchor, constant: -AppSpacing.lg),
            leftStack.topAnchor.constraint(equalTo: leftCard.topAnchor, constant: AppSpacing.lg),
            leftStack.bottomAnchor.constraint(equalTo: leftCard.bottomAnchor, constant: -AppSpacing.lg)
        ])

        // Right card — snooze count
        let rightCard = makeCard()
        let rightStack = UIStackView(arrangedSubviews: [snoozeTitleLabel, snoozeCountLabel])
        rightStack.axis = .vertical
        rightStack.spacing = AppSpacing.xs
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightCard.addSubview(rightStack)
        NSLayoutConstraint.activate([
            rightStack.leadingAnchor.constraint(equalTo: rightCard.leadingAnchor, constant: AppSpacing.lg),
            rightStack.trailingAnchor.constraint(equalTo: rightCard.trailingAnchor, constant: -AppSpacing.lg),
            rightStack.topAnchor.constraint(equalTo: rightCard.topAnchor, constant: AppSpacing.lg),
            rightStack.bottomAnchor.constraint(equalTo: rightCard.bottomAnchor, constant: -AppSpacing.lg)
        ])

        // Horizontal row
        let row = UIStackView(arrangedSubviews: [leftCard, rightCard])
        row.axis = .horizontal
        row.spacing = AppSpacing.sm
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeAverageCard() -> UIView {
        let card = makeCard()
        let stack = UIStackView(arrangedSubviews: [averageTitleLabel, averageValueLabel])
        stack.axis = .vertical
        stack.spacing = AppSpacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.lg),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.lg),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.lg)
        ])
        return card
    }

    private func makeChartCard() -> UIView {
        let card = makeCard()
        // Don't clip — `applyCardStyle()` needs `masksToBounds = false` so the
        // drop shadow renders. Chart subviews are constrained inside `card`
        // via Auto Layout below, so they won't visually overflow without the
        // clip.

        // Title label
        card.addSubview(chartTitleLabel)

        // SwiftUI chart
        let chartSwiftUIView = StatisticsChartView(data: [])
        let hostingController = UIHostingController(rootView: chartSwiftUIView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        card.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            chartTitleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.lg),
            chartTitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.lg),
            chartTitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.lg),

            hostingController.view.topAnchor.constraint(equalTo: chartTitleLabel.bottomAnchor, constant: AppSpacing.sm),
            hostingController.view.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.md),
            hostingController.view.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.md),
            hostingController.view.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.md),
            hostingController.view.heightAnchor.constraint(equalToConstant: 200)
        ])

        chartHostingController = hostingController
        return card
    }

    private func makeStreakCard() -> UIView {
        let card = makeCard()

        // Text stack (title + subtitle)
        let textStack = UIStackView(arrangedSubviews: [streakLabel, bestStreakLabel])
        textStack.axis = .vertical
        textStack.spacing = AppSpacing.xs
        textStack.translatesAutoresizingMaskIntoConstraints = false

        // Horizontal layout: icon | text
        let hStack = UIStackView(arrangedSubviews: [streakIconView, textStack])
        hStack.axis = .horizontal
        hStack.spacing = AppSpacing.md
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.lg),
            hStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.lg),
            hStack.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.lg),
            hStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.lg)
        ])

        return card
    }

    private func makeMotivationBanner() -> UIView {
        // Icon container
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(motivationIconLabel)
        NSLayoutConstraint.activate([
            motivationIconLabel.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            motivationIconLabel.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            motivationIconLabel.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 32)
        ])

        // Text stack
        let textStack = UIStackView(arrangedSubviews: [motivationTitleLabel, motivationMessageLabel])
        textStack.axis = .vertical
        textStack.spacing = AppSpacing.xs
        textStack.translatesAutoresizingMaskIntoConstraints = false

        // Horizontal layout: icon | text
        let hStack = UIStackView(arrangedSubviews: [iconContainer, textStack])
        hStack.axis = .horizontal
        hStack.spacing = AppSpacing.md
        hStack.alignment = .top
        hStack.translatesAutoresizingMaskIntoConstraints = false

        motivationCard.addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: motivationCard.leadingAnchor, constant: AppSpacing.lg),
            hStack.trailingAnchor.constraint(equalTo: motivationCard.trailingAnchor, constant: -AppSpacing.lg),
            hStack.topAnchor.constraint(equalTo: motivationCard.topAnchor, constant: AppSpacing.lg),
            hStack.bottomAnchor.constraint(equalTo: motivationCard.bottomAnchor, constant: -AppSpacing.lg)
        ])

        return motivationCard
    }

    /// Standard widget card — surface colour, hairline border, subtle shadow.
    /// Without the border + shadow these widgets dissolve into
    /// `systemGroupedBackground` in light mode. `CardView` owns its shadow-path
    /// rasterisation and trait-change refresh so the call site doesn't have to.
    private func makeCard() -> CardView {
        let view = CardView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.onDataUpdated = { [weak self] in
            self?.refresh()
        }
        viewModel.onLoadError = { [weak self] error in
            self?.presentRepositoryError(error)
        }
    }

    /// Alerts the user when the transaction ledger can't be decoded.
    /// Empty stats look identical to a brand-new user, so without this
    /// banner a corrupt blob hides itself behind "ноль откладываний"
    /// (issue #72). Guarded against double-presentation in case load is
    /// triggered repeatedly while the alert is still on screen.
    private func presentRepositoryError(_ error: LocalizedError) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Ошибка данных",
            message: error.errorDescription ?? "Не удалось загрузить статистику.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func refresh() {
        // Two-column summary — colour and text both come from the VM so the
        // empty-state vs has-data branching lives in one place.
        spentAmountLabel.textColor = viewModel.spentColor
        spentAmountLabel.text = viewModel.totalSpentFormatted

        snoozeCountLabel.textColor = viewModel.snoozeCountColor
        snoozeCountLabel.text = viewModel.snoozeCountFormatted

        // Average
        averageValueLabel.text = viewModel.averagePerDayFormatted

        // Streak — when no active streak we show the zero-state caption but
        // keep the card visible so the layout doesn't jump.
        if viewModel.streakActive {
            streakLabel.text = viewModel.streakMessage
            bestStreakLabel.text = viewModel.bestStreakFormatted
        } else {
            streakLabel.text = viewModel.streakZeroMessage
            bestStreakLabel.text = ""
        }
        streakCard?.isHidden = false

        // Motivation banner — VM decides whether there's anything to motivate
        // against; view just toggles visibility off the bool.
        motivationMessageLabel.text = viewModel.motivationalMessage
        motivationCard.isHidden = !viewModel.motivationVisible

        // Chart
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
