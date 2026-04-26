import UIKit

/// Main screen: alarm list with balance card header and navigation to create/edit alarms.
class AlarmsListViewController: UIViewController {

    // MARK: - ViewModel

    private let viewModel = AlarmsListViewModel()

    // MARK: - UI Elements

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .systemGroupedBackground
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = "⏰"
        iconLabel.font = UIFont.systemFont(ofSize: 64)

        let titleLabel = UILabel()
        titleLabel.text = "Нет будильников"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Нажмите + чтобы добавить"
        subtitleLabel.font = UIFont.systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel

        stack.addArrangedSubview(iconLabel)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }()

    // MARK: - Balance Card (table header)

    private let balanceCard = UIView()
    private let balanceAmountLabel = UILabel()
    private let topUpButton = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupNavigationBar()
        setupTableView()
        setupBalanceHeader()
        setupEmptyState()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadData()
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.title = "Будильники"
        navigationController?.navigationBar.prefersLargeTitles = false

        // "+" button using SF Symbol
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle.fill"),
            style: .plain,
            target: self,
            action: #selector(addAlarmTapped)
        )
        navigationItem.rightBarButtonItem = addButton
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AlarmCell.self, forCellReuseIdentifier: AlarmCell.reuseID)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBalanceHeader() {
        // Container for the balance card with padding
        let headerContainer = UIView()

        // Balance card styling — blue background
        balanceCard.backgroundColor = AppColors.accentBlue
        balanceCard.layer.cornerRadius = AppRadius.md
        balanceCard.clipsToBounds = true
        balanceCard.translatesAutoresizingMaskIntoConstraints = false

        // "БАЛАНС" small label
        let titleLabel = UILabel()
        titleLabel.text = "БАЛАНС"
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Amount label (large, white)
        balanceAmountLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        balanceAmountLabel.textColor = .white
        balanceAmountLabel.translatesAutoresizingMaskIntoConstraints = false

        // Top-up button (white pill with wallet icon)
        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.baseBackgroundColor = .white
        buttonConfig.baseForegroundColor = AppColors.accentBlue
        buttonConfig.cornerStyle = .capsule
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        let walletImage = UIImage(systemName: "wallet.pass.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        buttonConfig.image = walletImage
        buttonConfig.imagePadding = 6
        buttonConfig.imagePlacement = .leading

        var titleAttr = AttributedString("Пополнить")
        titleAttr.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        buttonConfig.attributedTitle = titleAttr

        topUpButton.configuration = buttonConfig
        topUpButton.addTarget(self, action: #selector(topUpTapped), for: .touchUpInside)
        topUpButton.translatesAutoresizingMaskIntoConstraints = false

        balanceCard.addSubview(titleLabel)
        balanceCard.addSubview(balanceAmountLabel)
        balanceCard.addSubview(topUpButton)

        headerContainer.addSubview(balanceCard)

        NSLayoutConstraint.activate([
            balanceCard.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: AppSpacing.sm),
            balanceCard.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: AppSpacing.lg),
            balanceCard.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -AppSpacing.lg),
            balanceCard.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -AppSpacing.sm),

            titleLabel.topAnchor.constraint(equalTo: balanceCard.topAnchor, constant: AppSpacing.md),
            titleLabel.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: AppSpacing.lg),

            balanceAmountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.xs),
            balanceAmountLabel.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: AppSpacing.lg),
            balanceAmountLabel.bottomAnchor.constraint(equalTo: balanceCard.bottomAnchor, constant: -AppSpacing.md),

            topUpButton.centerYAnchor.constraint(equalTo: balanceCard.centerYAnchor),
            topUpButton.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -AppSpacing.lg),
            topUpButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: balanceAmountLabel.trailingAnchor,
                constant: AppSpacing.md
            )
        ])

        // Size the header to fit its content
        let targetSize = CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        headerContainer.frame.size.width = view.bounds.width
        headerContainer.setNeedsLayout()
        headerContainer.layoutIfNeeded()
        let height = headerContainer.systemLayoutSizeFitting(targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        headerContainer.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)

        tableView.tableHeaderView = headerContainer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Recalculate header height on layout changes (rotation, etc.)
        guard let header = tableView.tableHeaderView else { return }
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let newHeight = header.systemLayoutSizeFitting(targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        if header.frame.height != newHeight {
            header.frame.size = CGSize(width: tableView.bounds.width, height: newHeight)
            tableView.tableHeaderView = header
        }
    }

    private func setupEmptyState() {
        view.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.onAlarmsUpdated = { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            self.emptyStateView.isHidden = !self.viewModel.alarms.isEmpty
            self.tableView.isHidden = self.viewModel.alarms.isEmpty
        }

        viewModel.onBalanceUpdated = { [weak self] _ in
            guard let self else { return }
            self.balanceAmountLabel.text = "₽ \(self.viewModel.formattedBalance)"
        }
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

    @objc private func topUpTapped() {
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
            fatalError("dequeueReusableCell returned wrong type for \(AlarmCell.reuseID)")
        }

        let alarm = viewModel.alarms[indexPath.row]
        cell.configure(
            time: viewModel.alarmTimeString(at: indexPath.row),
            detail: viewModel.alarmDetail(at: indexPath.row),
            penalty: viewModel.alarmPenaltyString(at: indexPath.row),
            enabled: alarm.enabled
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
        let alarm = viewModel.alarms[indexPath.row]
        let editVC = CreateAlarmViewController(alarm: alarm)
        editVC.onSave = { [weak self] in
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
            self?.viewModel.deleteAlarm(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
