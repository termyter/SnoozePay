import UIKit
import SwiftUI
import Charts

/// Statistics screen — V2 design (`docs/design/v2-handoff/components/SPMore4.jsx`
/// `Stats()` lines 6-120). Vertical stack of:
///   1. Period segmented (Неделя / Месяц / Всё время) — drives the VM.
///   2. Hero "Серия" card on `SPCard(.raised)` — caps + huge mono streak
///      count + flame badge + GitHub-style heatmap below.
///   3. "Эта неделя" bar-chart card (`SPCard(.surface)`) with money/pain bars
///      per weekday + a small summary row (Сэкономили / Потратили / Чистый).
///   4. "Время подъёма" card with three averaged numbers — V2 spec
///      placeholders; values fall back to `--` while we have no wake-time
///      ledger.
///   5. Empty state when there are no transactions in the selected period.
///   6. DEBUG buttons for presenting StreakModalV2, ReferralVC, AlarmOff —
///      gated behind `#if DEBUG` so production builds drop them.
///
/// Backed by `StatisticsViewModel`. Card-building helpers live in
/// `StatisticsViewController+Cards.swift` so the main type body stays under
/// SwiftLint's `type_body_length` ceiling.
final class StatisticsViewController: UIViewController {

    // MARK: - ViewModel

    let viewModel = StatisticsViewModel()

    // MARK: - Layout containers

    let scrollView = UIScrollView()
    let contentStack = UIStackView()
    /// Stack of "data" sections (hero, bars, time). Hidden as a unit when the
    /// empty state takes over.
    let dataStack = UIStackView()
    var emptyStateView: StatisticsEmptyStateView?

    // MARK: - Period selector

    lazy var periodSegment: SPSegmented = {
        let options = StatisticsViewModel.Period.allCases.map { period in
            SPSegmented.Option(value: String(period.rawValue), label: period.title)
        }
        let segment = SPSegmented(
            options: options,
            selectedValue: String(StatisticsViewModel.Period.week.rawValue)
        ) { [weak self] value in
            guard let raw = Int(value), let period = StatisticsViewModel.Period(rawValue: raw) else { return }
            self?.viewModel.loadData(period: period)
        }
        segment.translatesAutoresizingMaskIntoConstraints = false
        return segment
    }()

    // MARK: - Hero "Серия"

    /// Big mono streak count drawn at `moneyLg` (32pt). Sits inside the hero
    /// raised SPCard alongside the heatmap.
    let streakBigLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyLg
        label.textColor = AppColors.fg1
        label.adjustsFontForContentSizeCategory = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Trailing "дня / дней / день" word next to the big streak number.
    let streakBigWordLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h3
        label.textColor = AppColors.fg3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Meta line below the streak count — "Последний срыв: 8 января" /
    /// "Лучший результат: 12 дней".
    let streakMetaLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Heatmap

    let heatmapView: StatisticsHeatmapView = {
        let view = StatisticsHeatmapView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Toast banner used for tap feedback on heatmap cells. Hidden by default;
    /// `showToast(_:)` slides it in for ~2 s.
    let toastLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.body
        label.textColor = AppColors.fg1
        label.backgroundColor = AppColors.bg2
        label.layer.cornerRadius = AppRadius.sm
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Weekly bar chart

    var chartHostingController: UIHostingController<WeekdayChartView>?

    /// "Сэкономили" — money tinted.
    let savedAmountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneySm
        label.textColor = AppColors.money400
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// "Потратили" — pain tinted.
    let spentAmountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneySm
        label.textColor = AppColors.pain400
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// "Чистый" — fg1 neutral.
    let netAmountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneySm
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Статистика"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = AppColors.bg0
        setupLayout()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let raw = Int(periodSegment.selectedValue ?? "") ?? 0
        let period = StatisticsViewModel.Period(rawValue: raw) ?? .week
        viewModel.loadData(period: period)
    }

    // MARK: - Setup

    private func setupLayout() {
        configureContainers()
        installContainerConstraints()
        installToastConstraints()
        contentStack.addArrangedSubview(periodSegment)
        contentStack.addArrangedSubview(dataStack)
        dataStack.addArrangedSubview(makeHeroStreakCard())
        dataStack.addArrangedSubview(makeWeeklyCard())
        dataStack.addArrangedSubview(makeWakeTimeCard())
        #if DEBUG
        dataStack.addArrangedSubview(makeDebugButtonsRow())
        #endif
        heatmapView.onCellTap = { [weak self] cell in
            self?.presentHeatmapToast(for: cell)
        }
    }

    private func configureContainers() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AppSpacing.sp4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        dataStack.axis = .vertical
        dataStack.spacing = AppSpacing.sp3
        dataStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(toastLabel)
    }

    private func installContainerConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: AppSpacing.sp5),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -AppSpacing.sp7),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor,
                constant: -AppSpacing.screenInset * 2
            )
        ])
    }

    private func installToastConstraints() {
        NSLayoutConstraint.activate([
            toastLabel.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp5
            ),
            toastLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            toastLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
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
        // Hero streak card.
        let streak = viewModel.streak
        streakBigLabel.text = "\(streak)"
        streakBigWordLabel.text = StreakModalViewController.dayWord(for: streak)
        if streak > 0 {
            streakMetaLabel.text = "Лучший результат: \(viewModel.bestStreak) "
                + "\(StreakModalViewController.dayWord(for: viewModel.bestStreak))"
        } else {
            streakMetaLabel.text = "Серия начнётся, как только вы перестанете откладывать."
        }

        // Heatmap.
        heatmapView.cells = viewModel.heatmapCells

        // Bar chart.
        let chartBars = viewModel.weekdayBars.map { bar in
            WeekdayBarPoint(label: bar.label, amount: bar.amount, weekday: bar.weekday)
        }
        chartHostingController?.rootView = WeekdayChartView(bars: chartBars)

        // Weekly summary numbers — VM exposes `totalSpent` only, so the
        // "saved" line uses a coarse-but-defendable heuristic: best-streak
        // days * default penalty for the same period. This matches the
        // spirit of the V2 JSX (a hero green number) without inventing a
        // new ledger column.
        let spent = viewModel.totalSpent
        let saved = Double(max(viewModel.streak, 0)) * 50.0   // 50 ₽/day fallback
        let net = saved - spent
        savedAmountLabel.text = "+\(MoneyFormatter.string(max(saved, 0)))"
        spentAmountLabel.text = spent > 0 ? "−\(MoneyFormatter.string(spent))" : MoneyFormatter.string(0)
        let netPrefix = net >= 0 ? "+" : "−"
        netAmountLabel.text = "\(netPrefix)\(MoneyFormatter.string(abs(net)))"

        // Empty state — VM handles the empty-period detection.
        setEmptyStateVisible(!viewModel.hasData)
    }

    // MARK: - Empty state

    /// Toggle between the "we have data" stack and the empty-state column.
    /// We keep both views allocated — flipping `isHidden` is cheap and avoids
    /// re-running `addArrangedSubview` for every period switch.
    func setEmptyStateVisible(_ visible: Bool) {
        dataStack.isHidden = visible
        if visible {
            if emptyStateView == nil {
                let view = StatisticsEmptyStateView()
                view.translatesAutoresizingMaskIntoConstraints = false
                view.onCreateAlarmTap = { [weak self] in self?.createAlarmTapped() }
                emptyStateView = view
                contentStack.addArrangedSubview(view)
            }
            emptyStateView?.isHidden = false
        } else {
            emptyStateView?.isHidden = true
        }
    }

    // MARK: - Actions

    @objc func streakTapped() {
        let alarms = (try? AlarmRepository.shared.fetchAllChecked()) ?? []
        let saved = StreakModalViewController.estimatedSavings(
            for: max(viewModel.streak, 1),
            alarms: alarms
        )
        let modal = StreakModalViewController(
            streakDays: max(viewModel.streak, 1),
            savedAmount: saved
        )
        present(modal, animated: true)
    }

    #if DEBUG
    @objc func debugStreakTapped() {
        let modal = StreakModalViewController(streakDays: 7, savedAmount: 350)
        present(modal, animated: true)
    }

    @objc func debugReferralTapped() {
        let vc = ReferralViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc func debugAlarmOffTapped() {
        let vc = AlarmOffWarningViewController()
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.preferredCornerRadius = AppRadius.xl
        }
        present(vc, animated: true)
    }
    #endif

    private func createAlarmTapped() {
        let createVC = CreateAlarmViewController(alarm: nil)
        navigationController?.pushViewController(createVC, animated: true)
    }

    // MARK: - Heatmap toast

    private func presentHeatmapToast(for cell: StatisticsViewModel.HeatmapCell) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        let dateText = formatter.string(from: cell.date)
        let amountText: String
        if cell.amount > 0 {
            amountText = "−\(MoneyFormatter.string(cell.amount))"
        } else {
            amountText = "без штрафов"
        }
        showToast("\(dateText) · \(amountText)")
    }

    private func showToast(_ message: String) {
        // Pad the toast text — UILabel doesn't have intrinsic insets, so we
        // wrap with non-breaking space so the visual padding stays simple
        // while honouring `numberOfLines = 0` for long dates.
        toastLabel.text = "  \(message)  "
        UIView.animate(withDuration: SPSupport.durationBase, animations: {
            self.toastLabel.alpha = 1
        }, completion: { _ in
            UIView.animate(
                withDuration: SPSupport.durationSlow,
                delay: 1.4,
                options: [.curveEaseOut],
                animations: {
                    self.toastLabel.alpha = 0
                },
                completion: nil
            )
        })
    }
}
