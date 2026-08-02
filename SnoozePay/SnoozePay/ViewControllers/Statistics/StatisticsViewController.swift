import UIKit

/// Statistics screen — V3 behavioural redesign (#235, `SPMore4.jsx` `Stats()`,
/// artboards 27/27a). Top-level tab (no back button, large "Статистика"
/// title):
///   1. Hero "Серия" — streak count + flame badge + calendar-month heatmap
///      (tap a cell → tonal ring + tooltip, artboard 27a).
///   2. "Эта неделя" — saved/lost money chart + "Сэкономили / Потратили /
///      Чистый" totals (#348).
///   3. "Время подъёма" — two-week wake-time average against the previous
///      two weeks (#348). Hidden while no exact wake instants exist.
///   4. "По дням недели" — average snoozes per weekday over 4 weeks, worst
///      day highlighted in the pain gradient.
///   5. "Динамика откладываний" — 8-week trend with better/same/worse
///      headline and a direction arrow.
///   6. DEBUG buttons for StreakModal / Referral / AlarmOff — `#if DEBUG`.
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

    /// Fixed page-title header (#319) — same chrome as Будильники / Кошелёк.
    private let header: SPPageHeader = {
        let view = SPPageHeader(title: "Статистика")
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Shown over the scroll content when the user has no charges and no wake
    /// events — nothing to aggregate yet (`SPMore.jsx` `EmptyStats`, #289).
    let emptyState: SPStatsEmptyState = {
        let view = SPStatsEmptyState()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    /// Hero card reference — raised above its stack siblings while the
    /// heatmap tooltip is visible so the bubble isn't covered by the next
    /// card (the JSX gives the selected cell `zIndex: 3`).
    var heroCard: UIView?

    // MARK: - Hero "Серия"

    /// Big mono streak count drawn at `moneyXl` (56pt) — the hero number is
    /// the screen's focal point (`SPMore4.jsx`, audit P2-3 #289).
    let streakBigLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyXl
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

    /// Meta line below the streak count — "Последний срыв: 8 января".
    let streakMetaLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let heatmapView: StatisticsHeatmapView = {
        let view = StatisticsHeatmapView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Money / wake-time cards (#348)

    /// "ЭТА НЕДЕЛЯ" — saved/lost week chart + the three money totals.
    let weekMoneyCard: SPWeekMoneyCard = {
        let view = SPWeekMoneyCard()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// "ВРЕМЯ ПОДЪЁМА" — hidden entirely while no exact wake instants have
    /// been recorded (see `StatisticsViewModel.wakeTimeStats`).
    let wakeTimeCard: SPWakeTimeCard = {
        let view = SPWakeTimeCard()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Weekday card

    /// "Чаще всего — среда" headline (worst day tinted pain).
    let weekdayHeadlineLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h3
        label.textColor = AppColors.fg1
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let weekdayBarsView: StatisticsWeekdayBarsView = {
        let view = StatisticsWeekdayBarsView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Trend card

    /// "Становится лучше / Стабильно / Чаще, чем неделю назад".
    let trendHeadlineLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h3
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Diagonal trend arrow next to the headline. Hidden on a flat trend.
    let trendArrowView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// "−2 к прошлой неделе".
    let trendSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Big mono count under the right-aligned "Эта неделя" caption.
    let trendWeekValueLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyMd
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let trendBarsView: StatisticsTrendBarsView = {
        let view = StatisticsTrendBarsView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // The fixed page-title header carries the title; suppress the nav bar's
        // own title so the screen doesn't render «Статистика» twice (#319,
        // matching the AlarmsList #280 chrome).
        title = "Статистика"
        navigationItem.title = ""
        navigationController?.navigationBar.prefersLargeTitles = false
        view.backgroundColor = AppColors.bg0
        setupLayout()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hidden on this tab — the in-screen header owns the title (#319).
        navigationController?.setNavigationBarHidden(true, animated: animated)
        viewModel.loadData()
    }

    // MARK: - Setup

    private func setupLayout() {
        configureContainers()
        installContainerConstraints()
        let hero = makeHeroStreakCard()
        heroCard = hero
        contentStack.addArrangedSubview(hero)
        // Money + wake-time sit right under the hero, matching the artboard's
        // ordering (streak → неделя в деньгах → время подъёма → поведение).
        contentStack.addArrangedSubview(weekMoneyCard)
        contentStack.addArrangedSubview(wakeTimeCard)
        contentStack.addArrangedSubview(makeWeekdayCard())
        contentStack.addArrangedSubview(makeTrendCard())
        #if DEBUG
        contentStack.addArrangedSubview(makeDebugButtonsRow())
        #endif

        heatmapView.tooltipProvider = { [weak self] day in
            self?.viewModel.tooltip(for: day)
                ?? StatisticsViewModel.HeatmapTooltip(
                    dateText: "", statusText: "", spentText: nil, status: .empty
                )
        }
        heatmapView.onSelectionChanged = { [weak self] selected in
            guard let self, let hero = self.heroCard, selected else { return }
            // Keep layout untouched — only the drawing order changes, so the
            // tooltip can overhang the weekday card below.
            hero.superview?.bringSubviewToFront(hero)
        }
    }

    private func configureContainers() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AppSpacing.sp3
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(emptyState)
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Empty state fills the area below the header (not from safeArea
            // top — the header now occupies that band, #319).
            emptyState.topAnchor.constraint(equalTo: header.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func installContainerConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: AppSpacing.sp4),
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
        // The shared state column has two honest modes: a new account gets
        // the no-data copy from `SPMore.jsx` (`EmptyStats`, #289), while an
        // unreadable or partially read ledger names that failure and withholds
        // every ledger-derived card (#459).
        let unavailableReason = viewModel.moneyUnavailableReason
        let isEmpty = unavailableReason != nil || (viewModel.charges.isEmpty && viewModel.wakeDays.isEmpty)
        emptyState.isHidden = !isEmpty
        if let unavailableReason {
            emptyState.setUnavailable(unavailableReason.message)
        } else {
            emptyState.setStreak(viewModel.streak)
        }
        scrollView.isHidden = isEmpty
        if isEmpty { return }

        // Hero streak card.
        let streak = viewModel.streak
        streakBigLabel.text = "\(streak)"
        streakBigWordLabel.text = StreakModalViewController.dayWord(for: streak)
        streakMetaLabel.text = viewModel.lastSlipText
        heatmapView.days = viewModel.heatmapDays

        // "Эта неделя" money summary + "Время подъёма" (#348). Both cards are
        // gated on having data honest enough to publish:
        //   • money — the figures are withheld whenever the ledger couldn't be
        //     read in full. `wakeDays` survives a broken ledger, so without
        //     this gate every morning would look "clean" and the card would
        //     invent savings out of a corrupt blob (#348 review, finding 1).
        //     The card itself stays on screen and names the failure — hiding
        //     it swapped a visible lie for a silent one (#348 verification).
        //   • wake time — dropped when no exact wake instants were recorded;
        //     the alternative would be a fabricated clock reading.
        if let reason = viewModel.moneyUnavailableReason {
            weekMoneyCard.applyUnavailable(reason.message)
        } else {
            weekMoneyCard.apply(
                days: viewModel.weekMoneyDays,
                summary: viewModel.weekMoneySummary,
                savingsNote: viewModel.savingsNote
            )
        }
        if let wakeStats = viewModel.wakeTimeStats {
            wakeTimeCard.isHidden = false
            wakeTimeCard.apply(wakeStats)
        } else {
            wakeTimeCard.isHidden = true
        }

        // Weekday distribution.
        weekdayHeadlineLabel.attributedText = Self.weekdayHeadline(
            worstDayName: viewModel.worstWeekdayName
        )
        weekdayBarsView.stats = viewModel.weekdayStats

        // 8-week trend.
        let direction = viewModel.trendDirection
        trendHeadlineLabel.text = viewModel.trendHeadline
        trendSubtitleLabel.text = viewModel.trendSubtitle
        trendArrowView.isHidden = direction == .same
        trendArrowView.image = UIImage(
            systemName: direction == .better ? "arrow.down.right" : "arrow.up.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        )
        trendArrowView.tintColor = Self.trendColor(for: direction)
        trendWeekValueLabel.text = "\(viewModel.thisWeekCount)"
        trendWeekValueLabel.textColor = Self.trendColor(for: direction)
        trendBarsView.apply(points: viewModel.weeklyTrend, direction: direction)
    }

    // MARK: - Presentation helpers

    /// "Чаще всего — среда" with the day tinted pain; falls back to a neutral
    /// caption when the 4-week window has no snoozes.
    static func weekdayHeadline(worstDayName: String?) -> NSAttributedString {
        guard let name = worstDayName else {
            return NSAttributedString(
                string: "Откладываний не было",
                attributes: [.font: AppTypography.h3, .foregroundColor: AppColors.fg1]
            )
        }
        let headline = NSMutableAttributedString(
            string: "Чаще всего — ",
            attributes: [.font: AppTypography.h3, .foregroundColor: AppColors.fg1]
        )
        headline.append(NSAttributedString(
            string: name,
            attributes: [.font: AppTypography.h3, .foregroundColor: AppColors.pain300]
        ))
        return headline
    }

    /// money = improving, neutral = flat, pain = worse — shared by the arrow,
    /// the "Эта неделя" number and the current-week bar tint.
    static func trendColor(for direction: StatisticsViewModel.TrendDirection) -> UIColor {
        switch direction {
        case .better: return AppColors.money400
        case .same: return AppColors.fg2
        case .worse: return AppColors.pain400
        }
    }

    // MARK: - Actions

    @objc func streakTapped() {
        // A tap anywhere on the hero card lands here — clear an open tooltip
        // first so the modal doesn't stack on top of a stale selection.
        heatmapView.clearSelection()
        let saved = StatisticsViewModel.SavingsEstimate.savedDisplayAmount(
            cleanDays: viewModel.streak,
            price: viewModel.snoozePrice
        )
        let modal = StreakModalViewController(
            streakDays: viewModel.streak,
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
}
