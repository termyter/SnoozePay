import UIKit

/// Settings screen matching Figma design: account, theme, legal, contact sections.
class SettingsViewController: UIViewController {

    // MARK: - Dependencies

    private let themeService: ThemeService

    // MARK: - UI

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    /// Held weakly so the cell may be recycled (and the label deallocated)
    /// without leaving the observer with a dangling reference.
    private weak var balanceAmountLabel: UILabel?

    // MARK: - Init

    init(themeService: ThemeService = .shared) {
        self.themeService = themeService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// NotificationCenter token for balance-change updates. Removed in `deinit`.
    private var balanceObserver: NSObjectProtocol?

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case account    // Transaction history + Balance
        case appearance // Theme selector (system / light / dark)
        case info       // Privacy policy + Terms
        case contact    // Contact us
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Настройки"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground
        setupUI()
        observeBalanceChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    deinit {
        if let token = balanceObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Balance live-update

    /// Subscribe to balance changes so the row updates immediately after a
    /// top-up that happens while Settings is on-screen (e.g. another tab posts
    /// a change). Without this, the balance only refreshes on `viewWillAppear`.
    private func observeBalanceChanges() {
        balanceObserver = NotificationCenter.default.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let newBalance = note.userInfo?[BalanceService.balanceUserInfoKey] as? Double else { return }
            self.balanceAmountLabel?.text = "₽\(Int(newBalance))"
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(ThemeSegmentCell.self, forCellReuseIdentifier: ThemeSegmentCell.reuseID)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Theme

    /// Map stored preference to segment index: 0=system, 1=light, 2=dark.
    private var themeSegmentIndex: Int {
        switch themeService.current {
        case .system: return 0
        case .light: return 1
        case .dark: return 2
        }
    }

    private func handleThemeSegmentChange(_ index: Int) {
        let theme: ThemeService.Theme
        switch index {
        case 1: theme = .light
        case 2: theme = .dark
        default: theme = .system
        }
        themeService.setTheme(theme)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .account: return 2    // Transaction history, Balance
        case .appearance: return 1 // Dark theme
        case .info: return 2       // Privacy, Terms
        case .contact: return 1    // Contact us
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .account: return "АККАУНТ"
        case .appearance: return "ОФОРМЛЕНИЕ"
        case .info: return "ИНФОРМАЦИЯ"
        case .contact: return "СВЯЗАТЬСЯ"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }

        switch section {
        case .account:
            if indexPath.row == 0 {
                return makeIconRow(
                    systemName: "list.bullet.rectangle",
                    iconColor: AppColors.accentBlue,
                    title: "История транзакций",
                    accessory: .disclosureIndicator
                )
            } else {
                let cell = makeIconRow(
                    systemName: "dollarsign.circle",
                    iconColor: AppColors.accentGreen,
                    title: "Баланс",
                    accessory: .none
                )

                let balanceAmount = UILabel()
                balanceAmount.text = "₽\(Int(BalanceService.shared.balance))"
                balanceAmount.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
                balanceAmount.textColor = AppColors.accentBlue
                balanceAmount.translatesAutoresizingMaskIntoConstraints = false
                balanceAmount.setContentHuggingPriority(.required, for: .horizontal)
                cell.contentView.addSubview(balanceAmount)

                NSLayoutConstraint.activate([
                    balanceAmount.trailingAnchor.constraint(
                        equalTo: cell.contentView.trailingAnchor,
                        constant: -AppSpacing.lg
                    ),
                    balanceAmount.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
                ])

                // Track the latest label instance so the balance observer can
                // refresh it. When the cell is recycled the weak ref nils out
                // automatically, so the observer becomes a no-op until the row
                // is rebuilt — at which point this assignment captures the new label.
                self.balanceAmountLabel = balanceAmount

                cell.selectionStyle = .none
                return cell
            }

        case .appearance:
            // Dedicated cell type owns the segment control — avoids the previous
            // removeFromSuperview/re-add dance that left the control bound to
            // whichever cell rendered last.
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ThemeSegmentCell.reuseID,
                for: indexPath
            ) as? ThemeSegmentCell else {
                assertionFailure("dequeueReusableCell returned wrong type for \(ThemeSegmentCell.reuseID)")
                return UITableViewCell()
            }
            cell.configure(selectedIndex: themeSegmentIndex) { [weak self] index in
                self?.handleThemeSegmentChange(index)
            }
            return cell

        case .info:
            let title = indexPath.row == 0 ? "Политика конфиденциальности" : "Пользовательское соглашение"
            return makeIconRow(
                systemName: "doc.text",
                iconColor: UIColor.systemGray,
                title: title,
                accessory: .disclosureIndicator
            )

        case .contact:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .secondarySystemBackground

            let icon = makeSettingsIcon(systemName: "envelope", backgroundColor: AppColors.accentOrange)
            let titleLabel = UILabel()
            titleLabel.text = "Связаться с нами"
            titleLabel.font = UIFont.systemFont(ofSize: 17)
            titleLabel.textColor = .label

            let detailLabel = UILabel()
            detailLabel.text = "support@alarmcash.app"
            detailLabel.font = UIFont.systemFont(ofSize: 13)
            detailLabel.textColor = .secondaryLabel

            let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
            textStack.axis = .vertical
            textStack.spacing = 2

            let stack = UIStackView(arrangedSubviews: [icon, textStack])
            stack.axis = .horizontal
            stack.spacing = AppSpacing.md
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(
                    equalTo: cell.contentView.leadingAnchor,
                    constant: AppSpacing.lg
                ),
                stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                stack.trailingAnchor.constraint(
                    lessThanOrEqualTo: cell.contentView.trailingAnchor,
                    constant: -AppSpacing.lg
                )
            ])

            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    // MARK: - Cell factory helpers

    private func makeIconRow(
        systemName: String,
        iconColor: UIColor,
        title: String,
        accessory: UITableViewCell.AccessoryType
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .secondarySystemBackground

        let icon = makeSettingsIcon(systemName: systemName, backgroundColor: iconColor)
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .label

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = AppSpacing.md
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: AppSpacing.lg),
            stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])

        cell.accessoryType = accessory
        return cell
    }

    /// Creates a rounded-rect icon with an SF Symbol, similar to iOS Settings style
    private func makeSettingsIcon(systemName: String, backgroundColor: UIColor) -> UIView {
        let size: CGFloat = 30
        let container = UIView()
        container.backgroundColor = backgroundColor
        container.layer.cornerRadius = 7
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView()
        imageView.image = UIImage(systemName: systemName)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 52 }
        return section == .appearance ? 56 : 52
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .account:
            if indexPath.row == 0 {
                let historyVC = TransactionHistoryViewController()
                navigationController?.pushViewController(historyVC, animated: true)
            }

        case .appearance:
            break

        case .info:
            let title = indexPath.row == 0 ? "Политика конфиденциальности" : "Пользовательское соглашение"
            let legalVC = LegalViewController(title: title)
            navigationController?.pushViewController(legalVC, animated: true)

        case .contact:
            openMailto()
        }
    }

    private func openMailto() {
        if let url = URL(string: "mailto:support@alarmcash.app") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Transaction History VC

final class TransactionHistoryViewController: UIViewController {

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private var transactions: [Transaction] = []
    private let alarmRepository = AlarmRepository.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "История транзакций"
        view.backgroundColor = .systemGroupedBackground
        setupTableView()
        loadTransactions()
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Loads transactions through the checked variant so a corrupt ledger
    /// surfaces an alert instead of rendering as an indistinguishable
    /// "Нет транзакций" empty state (gauntlet CRITICAL #2 / issue #72 —
    /// mirrors the treatment already in StatisticsViewModel and
    /// AlarmsListViewModel).
    private func loadTransactions() {
        do {
            transactions = try TransactionRepository.shared.fetchAllChecked()
        } catch let error as TransactionRepository.RepositoryError {
            transactions = []
            presentRepositoryError(error)
        } catch {
            transactions = []
            presentRepositoryError(TransactionRepository.RepositoryError.decodeFailure(underlying: error))
        }
        tableView.reloadData()
    }

    /// Guarded against double-presentation in case `loadTransactions` is
    /// invoked again (e.g. via VC reload) while the alert is still on screen.
    private func presentRepositoryError(_ error: LocalizedError) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Ошибка данных",
            message: error.errorDescription ?? "Не удалось загрузить транзакции.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension TransactionHistoryViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        transactions.isEmpty ? 1 : transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if transactions.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Нет транзакций"
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.textAlignment = .center
            cell.backgroundColor = .secondarySystemBackground
            cell.selectionStyle = .none
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: TransactionCell.reuseID, for: indexPath
        ) as? TransactionCell else {
            assertionFailure("dequeueReusableCell returned wrong type for \(TransactionCell.reuseID)")
            return UITableViewCell()
        }

        let transaction = transactions[indexPath.row]

        // Look up alarm name if available
        var alarmName: String?
        if let alarmIDString = transaction.alarmID, let alarmUUID = UUID(uuidString: alarmIDString) {
            alarmName = alarmRepository.fetch(id: alarmUUID)?.name
        }

        cell.configure(with: transaction, alarmName: alarmName)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        transactions.isEmpty ? 52 : 64
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "ИСТОРИЯ"
    }
}

// MARK: - Transaction Cell

final class TransactionCell: UITableViewCell {

    static let reuseID = "TransactionCell"

    // MARK: - UI

    private let iconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        selectionStyle = .none

        iconContainer.addSubview(iconImageView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [iconContainer, textStack, amountLabel])
        mainStack.axis = .horizontal
        mainStack.spacing = AppSpacing.md
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm)
        ])
    }

    // MARK: - Configure

    func configure(with transaction: Transaction, alarmName: String?) {
        let isTopup = transaction.type == .topup

        // Icon
        iconContainer.backgroundColor = isTopup ? AppColors.accentGreen : AppColors.destructiveRed
        iconImageView.image = UIImage(systemName: isTopup ? "arrow.up" : "arrow.down")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        )

        // Title
        titleLabel.text = isTopup ? "Пополнение" : "Откладывание"

        // Subtitle: alarm name + date
        let dateString = Self.formatDate(transaction.createdAt)
        if let name = alarmName, !isTopup {
            subtitleLabel.text = "\(name) \u{00B7} \(dateString)"
        } else {
            subtitleLabel.text = dateString
        }

        // Amount
        let amount = Int(transaction.amount)
        if isTopup {
            amountLabel.text = "+₽\(amount)"
            amountLabel.textColor = AppColors.accentGreen
        } else {
            amountLabel.text = "₽\(amount)"
            amountLabel.textColor = AppColors.destructiveRed
        }
    }

    // MARK: - Date formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM 'в' HH:mm"
        return formatter
    }()

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

// MARK: - Legal VC (simple text placeholder)

final class LegalViewController: UIViewController {

    private let legalTitle: String

    init(title: String) {
        self.legalTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = legalTitle
        view.backgroundColor = .systemGroupedBackground

        let textView = UITextView()
        textView.text = "\(legalTitle)\n\nДокумент будет добавлен перед публикацией в App Store."
        textView.font = UIFont.systemFont(ofSize: 15)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
