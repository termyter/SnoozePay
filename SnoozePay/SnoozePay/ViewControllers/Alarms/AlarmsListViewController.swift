import UIKit

/// V2 alarms list screen.
///
/// Layout (top → bottom inside `view`):
/// ```
/// safeArea.top
///   ├─ SPAlarmsListHeader (sticky)
///   │     ├─ title row "Будильники" + 40×40 "+" button
///   │     └─ compact balance pill (auto-warn-tint when balance < 100)
///   └─ UITableView (scrolls)
///         ├─ tableHeaderView: AlarmsStreakBannerView (when streak > 0)
///         └─ rows: AlarmCell
///         └─ overlay: SPAlarmsListEmptyState (when alarms.isEmpty)
/// safeArea.bottom
/// ```
///
/// The big balance card + amber "БАЛАНС ПОЧТИ ПУСТ" banner from the V1 header
/// are gone — the compact pill folds urgency into a single line. The nav-bar
/// "+" button is suppressed because the header carries its own 40×40 plus;
/// the gear and DEBUG entries are preserved as required by the design brief.
class AlarmsListViewController: UIViewController {

    // MARK: - ViewModel

    private let viewModel = AlarmsListViewModel()

    // MARK: - UI Elements

    private let header: SPAlarmsListHeader = {
        let view = SPAlarmsListHeader()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 160
        table.contentInset = UIEdgeInsets(
            top: AppSpacing.sp4,
            left: 0,
            bottom: AppSpacing.sp4,
            right: 0
        )
        return table
    }()

    private let streakBanner: AlarmsStreakBannerView = {
        let view = AlarmsStreakBannerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let emptyStateView: SPAlarmsListEmptyState = {
        let view = SPAlarmsListEmptyState()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        setupNavigationBar()
        setupLayout()
        setupCallbacks()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadData()
        tableView.reloadData()
        refreshStreakBanner()
        presentStreakModalIfNeeded()
    }

    // MARK: - Streak modal

    private static let streakMilestoneDays: [Int] = [3, 7, 14, 30]
    private static let streakMilestonesShownKey = "streak_milestones_shown"

    /// Presents `StreakModalViewController` when the current streak hits a
    /// new milestone. Preserved from V1.
    func presentStreakModalIfNeeded(in viewController: UIViewController? = nil) {
        let host = viewController ?? self
        guard host.presentedViewController == nil else { return }
        let streak = TransactionRepository.shared.currentStreak()
        guard Self.streakMilestoneDays.contains(streak) else { return }
        var shown = UserDefaults.standard.array(forKey: Self.streakMilestonesShownKey) as? [Int] ?? []
        guard !shown.contains(streak) else { return }
        shown.append(streak)
        UserDefaults.standard.set(shown, forKey: Self.streakMilestonesShownKey)
        presentStreakModal(streakDays: streak, on: host)
    }

    func presentStreakModal(streakDays: Int, on viewController: UIViewController? = nil) {
        let host = viewController ?? self
        guard host.presentedViewController == nil else { return }
        // V3 modal (#236) is de-monetized — no saved-amount input anymore.
        let modal = StreakModalViewController(streakDays: streakDays)
        host.present(modal, animated: true)
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        // V2 header carries its own title — suppress the nav bar's title so
        // the screen doesn't render the word twice.
        navigationItem.title = ""
        navigationController?.navigationBar.prefersLargeTitles = false

        // V1 had a "+" button on the right edge of the nav bar; the V2 header
        // moves that affordance into the title row so the user always sees
        // the CTA near the balance. Drop the nav-bar plus to avoid two CTAs.
        navigationItem.rightBarButtonItem = nil

        // Gear icon — preserved entry point for Settings.
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.leftBarButtonItem = settingsButton

        // DEBUG-only entries — streak modal trigger + onboarding reset.
        // Required to stay functional after the V2 rewrite.
        #if DEBUG
        let streakButton = UIBarButtonItem(
            image: UIImage(systemName: "flame.fill"),
            style: .plain,
            target: self,
            action: #selector(debugTriggerStreakModal)
        )
        let resetButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.counterclockwise"),
            style: .plain,
            target: self,
            action: #selector(debugResetOnboarding)
        )
        navigationItem.leftBarButtonItems = [settingsButton, streakButton, resetButton]
        #endif
    }

    @objc private func openSettings() {
        // Child screen with a back arrow (#237) — pushed onto the tab's
        // existing navigation stack instead of a standalone modal.
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }

    #if DEBUG
    @objc private func debugTriggerStreakModal() {
        presentStreakModal(streakDays: 7)
    }

    @objc private func debugResetOnboarding() {
        UserDefaults.standard.removeObject(forKey: OnboardingViewController.completedKey)
        UserDefaults.standard.removeObject(forKey: PermissionsViewController.hasBeenShownKey)
        let alert = UIAlertController(
            title: "Онбординг сброшен",
            message: "Закройте приложение и запустите заново — увидите экран приветствия.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    #endif

    private func setupLayout() {
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(header)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AlarmCell.self, forCellReuseIdentifier: AlarmCell.reuseID)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: tableView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupCallbacks() {
        header.onAddTap = { [weak self] in
            self?.addAlarmTapped()
        }
        header.onBalanceTopUpTap = { [weak self] in
            self?.presentTopUp()
        }
        header.onWarnTopUpTap = { [weak self] in
            self?.presentTopUp()
        }
        streakBanner.onTap = { [weak self] in
            guard let self else { return }
            let streak = TransactionRepository.shared.currentStreak()
            guard streak > 0 else { return }
            self.presentStreakModal(streakDays: streak)
        }
        emptyStateView.onAddAlarmTap = { [weak self] in
            self?.addAlarmTapped()
        }
    }

    private func bindViewModel() {
        viewModel.onAlarmsUpdated = { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            let isEmpty = self.viewModel.alarms.isEmpty
            self.emptyStateView.isHidden = !isEmpty
            self.tableView.isHidden = isEmpty
            self.refreshHeader()
            self.refreshStreakBanner()
        }

        viewModel.onBalanceUpdated = { [weak self] _ in
            self?.refreshHeader()
        }

        viewModel.onLoadError = { [weak self] error in
            self?.presentRepositoryError(error)
        }

        viewModel.onBalanceCorrupted = { [weak self] rawValue in
            self?.presentBalanceCorruptedAlert(rawValue: rawValue)
        }
    }

    /// Push the latest balance / hint state into the sticky header.
    private func refreshHeader() {
        let balance = Decimal(viewModel.balance)
        header.setBalance(
            balance,
            // `balanceHint` swaps in "Откладывать не получится" at 0 ₽
            // (#232) and falls back to the affordability line otherwise.
            hint: viewModel.balanceHint,
            delta: viewModel.weeklyDelta
        )
        // Legacy method preserved for source-compat — the V2 pill already
        // self-toggles its tone from `setBalance` based on the threshold.
        header.setWarning(visible: viewModel.isLowBalance, balance: balance)
    }

    /// Mount / dismount the streak banner above the alarm rows. When the
    /// current streak is 0, the banner is removed entirely so the empty
    /// state column doesn't collide with a stale header view.
    private func refreshStreakBanner() {
        let streak = TransactionRepository.shared.currentStreak()
        guard streak > 0 else {
            tableView.tableHeaderView = nil
            return
        }
        let saved = StreakModalViewController.estimatedSavings(
            for: streak,
            alarms: viewModel.alarms
        )
        streakBanner.configure(streakDays: streak, savedAmount: saved)
        // Size the table header view with a layout pass — UITableView's
        // tableHeaderView requires a non-zero frame to render at all.
        let targetWidth = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        if targetWidth > 0 {
            streakBanner.translatesAutoresizingMaskIntoConstraints = true
            streakBanner.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 84)
            let fittingSize = streakBanner.systemLayoutSizeFitting(
                CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            streakBanner.frame = CGRect(x: 0, y: 0, width: targetWidth, height: fittingSize.height)
        }
        if tableView.tableHeaderView !== streakBanner {
            tableView.tableHeaderView = streakBanner
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The banner's width depends on the live table-view width, so re-
        // measure on every layout pass (rotation, split-view resize).
        if tableView.tableHeaderView === streakBanner {
            refreshStreakBanner()
        }
    }

    private func presentRepositoryError(_ error: LocalizedError) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Ошибка данных",
            message: error.errorDescription ?? "Не удалось загрузить будильники.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Corrupt `user_balance` detected (#119) — possibly at cold start before
    /// any observer existed (#206). Pop-ups and top-ups are gated until the
    /// user acknowledges, so the alert offers an immediate reset to 0 ₽.
    private func presentBalanceCorruptedAlert(rawValue: Double) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Баланс повреждён",
            message: "В хранилище обнаружено некорректное значение баланса (\(rawValue)). "
                + "Пополнения и списания приостановлены. Сбросить баланс до 0 ₽?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive) { [weak self] _ in
            self?.viewModel.acknowledgeBalanceCorruption()
        })
        alert.addAction(UIAlertAction(title: "Позже", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func addAlarmTapped() {
        let createVC = CreateAlarmViewController(alarm: nil)
        createVC.onSave = { [weak self] in
            self?.viewModel.loadData()
        }
        let nav = UINavigationController(rootViewController: createVC)
        present(nav, animated: true)
    }

    private func presentTopUp() {
        let topUpVC = TopUpViewController()
        let nav = UINavigationController(rootViewController: topUpVC)
        present(nav, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AlarmsListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.alarms.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: AlarmCell.reuseID,
            for: indexPath
        ) as? AlarmCell else {
            assertionFailure("dequeueReusableCell returned wrong type for \(AlarmCell.reuseID)")
            return UITableViewCell()
        }

        let alarm = viewModel.alarms[indexPath.row]
        cell.configure(
            time: viewModel.alarmTimeString(at: indexPath.row),
            daysCaps: viewModel.alarmDaysCaps(at: indexPath.row),
            priceText: viewModel.alarmPriceText(at: indexPath.row),
            multiplier: viewModel.alarmMultiplierText(at: indexPath.row),
            soundName: viewModel.alarmSoundName(at: indexPath.row),
            enabled: alarm.enabled
        )

        let alarmID = alarm.id
        cell.onToggle = { [weak self] isOn in
            self?.viewModel.toggleAlarm(id: alarmID, enabled: isOn)
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension AlarmsListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let alarm = viewModel.alarms[indexPath.row]
        let editVC = CreateAlarmViewController(alarm: alarm)
        editVC.onSave = { [weak self] in
            self?.viewModel.loadData()
        }
        editVC.onDelete = { [weak self] in
            self?.viewModel.loadData()
        }
        let nav = UINavigationController(rootViewController: editVC)
        present(nav, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            guard indexPath.row < self.viewModel.alarms.count else {
                self.viewModel.loadData()
                completion(false)
                return
            }
            let alarmID = self.viewModel.alarms[indexPath.row].id
            guard self.viewModel.deleteAlarm(id: alarmID) else {
                self.viewModel.loadData()
                completion(false)
                return
            }
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
