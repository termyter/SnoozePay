import UIKit

/// Main screen — alarm list with a sticky balance header that stays pinned
/// above the scroll, an optional low-balance warning banner under it, the
/// alarm list itself, and an empty-state column that overlays the table when
/// there are no alarms yet.
///
/// Layout (top → bottom inside `view`):
/// ```
/// safeArea.top
///   ├─ SPAlarmsListHeader (sticky)
///   │     ├─ balance card (caps + value + centered hint + trailing pill)
///   │     └─ optional low-balance warning banner
///   └─ UITableView (scrolls)
///         └─ overlay: SPAlarmsListEmptyState (when alarms.isEmpty)
/// safeArea.bottom
/// ```
///
/// The header is pinned to the safe area — it does NOT live as
/// `tableView.tableHeaderView` so it can't scroll away with the list. The
/// table is anchored beneath the header with a small gap so the warning
/// banner shadow can breathe before the list begins.
class AlarmsListViewController: UIViewController {

    // MARK: - ViewModel

    private let viewModel = AlarmsListViewModel()

    // MARK: - UI Elements

    private let header: SPAlarmsListHeader = {
        let view = SPAlarmsListHeader()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AppSpacing.sp3,
            leading: AppSpacing.screenInset,
            bottom: AppSpacing.sp3,
            trailing: AppSpacing.screenInset
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
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
        presentStreakModalIfNeeded()
    }

    // MARK: - Streak modal

    /// Streak milestones that fire the celebratory modal exactly once each.
    /// 3 / 7 / 14 / 30 days are the milestones called out in #146; once a
    /// milestone has fired we record it in `streakMilestonesShownKey` so the
    /// user never sees the same modal twice for the same achievement.
    private static let streakMilestoneDays: [Int] = [3, 7, 14, 30]
    /// UserDefaults key that stores `[Int]` of milestones already shown.
    private static let streakMilestonesShownKey = "streak_milestones_shown"

    /// Presents `StreakModalViewController` over `viewController` (defaults
    /// to `self`) when:
    ///   - the current streak hits one of the milestone values, AND
    ///   - that milestone has not been shown for this install yet, AND
    ///   - no other modal is already on screen.
    /// Wiring this into `viewWillAppear` keeps the trigger close to a state
    /// observation point (alarms list refresh) without coupling the modal
    /// to the firing flow. PM follow-up: replace the static milestone list
    /// with a dedicated trigger service so notifications and the modal can
    /// share one source of truth.
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

    /// Direct entry point — used by the DEBUG trigger button below and
    /// available to other controllers that want to celebrate an arbitrary
    /// streak. Bypasses the milestone gate but still respects the
    /// "no double-presentation" guard.
    func presentStreakModal(streakDays: Int, on viewController: UIViewController? = nil) {
        let host = viewController ?? self
        guard host.presentedViewController == nil else { return }
        let saved = StreakModalViewController.estimatedSavings(
            for: streakDays,
            alarms: viewModel.alarms
        )
        let modal = StreakModalViewController(streakDays: streakDays, savedAmount: saved)
        host.present(modal, animated: true)
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.title = "Будильники"
        navigationController?.navigationBar.prefersLargeTitles = false

        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle.fill"),
            style: .plain,
            target: self,
            action: #selector(addAlarmTapped)
        )
        navigationItem.rightBarButtonItem = addButton

        // Settings moved out of the tab bar per V2 design — entry point is
        // the gear icon on the Alarms header (matches "more / account"
        // pattern used in Wallet header).
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.leftBarButtonItem = settingsButton

        // DEBUG-only entries — streak modal trigger and onboarding reset so
        // designers / QA can iterate without manufacturing real state.
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
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }

    #if DEBUG
    @objc private func debugTriggerStreakModal() {
        // Skip the milestone gate and the no-double-show flag — debug button
        // should always render the modal regardless of how many times PM has
        // already opened it this session. 7 days matches the spec screenshot.
        presentStreakModal(streakDays: 7)
    }

    @objc private func debugResetOnboarding() {
        // Clears the onboarding-completed + permissions-shown flags so the
        // next cold launch walks through Splash → Onboarding → Permissions
        // again. Lets PM verify the V2 onboarding redesign without
        // re-installing the app.
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
        // Order matters — header is added LAST so it draws on top of the
        // table content shadow if any of the alarm cards bleed under the
        // safe-area inset during scroll.
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(header)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AlarmCell.self, forCellReuseIdentifier: AlarmCell.reuseID)

        NSLayoutConstraint.activate([
            // Sticky header pinned to safe-area top.
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Table flows beneath the header.
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Empty state overlays the same area as the table so the
            // sticky header still shows the user their balance even
            // when the list is empty.
            emptyStateView.topAnchor.constraint(equalTo: tableView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupCallbacks() {
        header.onBalanceTopUpTap = { [weak self] in
            self?.presentTopUp()
        }
        header.onWarnTopUpTap = { [weak self] in
            self?.presentTopUp()
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
            // Refresh the affordability hint — it depends on the
            // current alarm set's average penalty, so a delete /
            // create can change the snooze count even when the
            // balance hasn't moved.
            self.refreshHeader()
        }

        viewModel.onBalanceUpdated = { [weak self] _ in
            self?.refreshHeader()
        }

        viewModel.onLoadError = { [weak self] error in
            self?.presentRepositoryError(error)
        }
    }

    /// Push the latest balance / hint / warning state into the sticky
    /// header. Called both from `onBalanceUpdated` (BalanceService
    /// notification) and `onAlarmsUpdated` (alarm-set change shifts the
    /// average penalty). Also pipes the rolling weekly delta from the
    /// transaction ledger (#175) so the sticky header echoes the
    /// `.sp-balance__delta` row from the design spec.
    private func refreshHeader() {
        let balance = Decimal(viewModel.balance)
        header.setBalance(
            balance,
            hint: viewModel.affordabilityHint,
            delta: viewModel.weeklyDelta
        )
        header.setWarning(visible: viewModel.isLowBalance, balance: balance)
    }

    /// Shows a non-blocking alert when the repository couldn't load or
    /// persist data. Without this the user would see an empty list and
    /// assume the app wiped their alarms — then recreate them, and the
    /// next save would clobber the recoverable corrupt JSON for good
    /// (issue #72). Guarded against double-presentation so a load failure
    /// followed quickly by a persist failure doesn't stack alerts.
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
            detail: viewModel.alarmDetail(at: indexPath.row),
            penalty: viewModel.alarmPenaltyString(at: indexPath.row),
            enabled: alarm.enabled,
            theme: alarm.theme
        )

        // Capture the alarm's stable UUID rather than the row index — the
        // index becomes invalid after delete/reorder, but the id never does.
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
        // Re-fetch from the source of truth instead of mutating by row index —
        // the row that was tapped may have shifted after another in-flight
        // delete (e.g. swipe + detail open near-simultaneously).
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
            // Capture the alarm id before the action fires so a concurrent mutation
            // that re-orders rows (delete from detail, programmatic reload) cannot
            // make us delete the wrong alarm. Index-based delete would silently
            // drop whichever alarm now sits at the swiped row, with no feedback
            // to the user. Identity-based delete short-circuits if the alarm has
            // already been removed and triggers a full reload to resync the UI.
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
        // SF Symbol gives the action a recognisable affordance even before the
        // user has read the title — addresses the PM feedback that the swipe
        // gesture was not obvious.
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
