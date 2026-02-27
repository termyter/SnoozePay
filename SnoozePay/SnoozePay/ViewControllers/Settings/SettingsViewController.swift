import UIKit

/// Settings screen: global snooze time, transaction history, legal docs.
class SettingsViewController: UIViewController {

    // MARK: - Data

    private let defaults = UserDefaults.standard
    private let snoozeKey = "global_snooze_minutes"

    private var globalSnoozeMinutes: Int {
        get { defaults.integer(forKey: snoozeKey) == 0 ? 9 : defaults.integer(forKey: snoozeKey) }
        set { defaults.set(newValue, forKey: snoozeKey) }
    }

    // MARK: - UI

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let snoozeValueLabel = UILabel()
    private let snoozeStepper: UIStepper = {
        let s = UIStepper()
        s.minimumValue = 1
        s.maximumValue = 30
        s.stepValue = 1
        return s
    }()

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case balance, info, legal
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Настройки"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        snoozeStepper.value = Double(globalSnoozeMinutes)
        snoozeStepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        updateSnoozeLabel()
    }

    private func updateSnoozeLabel() {
        snoozeValueLabel.text = "\(globalSnoozeMinutes) мин"
        snoozeValueLabel.font = UIFont.systemFont(ofSize: 17)
        snoozeValueLabel.textColor = .secondaryLabel
        snoozeValueLabel.sizeToFit()
    }

    @objc private func stepperChanged() {
        globalSnoozeMinutes = Int(snoozeStepper.value)
        updateSnoozeLabel()
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
        case .balance: return 2 // Snooze time, Transaction history
        case .info: return 2    // About, Contact
        case .legal: return 2   // Privacy, Terms
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .balance: return "БАЛАНС"
        case .info: return "ИНФОРМАЦИЯ"
        case .legal: return "ДОКУМЕНТЫ"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .secondarySystemBackground

        switch section {
        case .balance:
            if indexPath.row == 0 {
                // Snooze stepper row
                cell.textLabel?.text = "Время откладывания"
                let stack = UIStackView(arrangedSubviews: [snoozeValueLabel, snoozeStepper])
                stack.axis = .horizontal
                stack.spacing = 8
                cell.accessoryView = stack
                cell.selectionStyle = .none
            } else {
                cell.textLabel?.text = "История транзакций"
                cell.accessoryType = .disclosureIndicator
            }

        case .info:
            if indexPath.row == 0 {
                cell.textLabel?.text = "О приложении"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Связаться с разработчиком"
                cell.accessoryType = .disclosureIndicator
            }

        case .legal:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Политика конфиденциальности"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Пользовательское соглашение"
                cell.accessoryType = .disclosureIndicator
            }
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 48 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .balance:
            if indexPath.row == 1 {
                let historyVC = TransactionHistoryViewController()
                navigationController?.pushViewController(historyVC, animated: true)
            }

        case .info:
            if indexPath.row == 0 {
                showAbout()
            } else {
                openMailto()
            }

        case .legal:
            let title = indexPath.row == 0 ? "Политика конфиденциальности" : "Пользовательское соглашение"
            let vc = LegalViewController(title: title)
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let alert = UIAlertController(
            title: "SnoozePay",
            message: "Версия \(version)\n\nБудильник с финансовой мотивацией — платите за каждое откладывание.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func openMailto() {
        if let url = URL(string: "mailto:support@snooze-pay.app") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Transaction History VC

final class TransactionHistoryViewController: UIViewController {

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private var transactions: [Transaction] = []

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadTransactions() {
        transactions = TransactionRepository().fetchAll()
        tableView.reloadData()
    }
}

extension TransactionHistoryViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        transactions.isEmpty ? 1 : transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)

        if transactions.isEmpty {
            cell.textLabel?.text = "Нет транзакций"
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.textAlignment = .center
            return cell
        }

        let tx = transactions[indexPath.row]
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        cell.textLabel?.text = tx.type == .charge ? "Откладывание" : "Пополнение"
        cell.detailTextLabel?.text = tx.formattedAmount
        cell.detailTextLabel?.textColor = tx.type == .charge ? AppColors.accentOrange : AppColors.accentGreen

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "ИСТОРИЯ"
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
