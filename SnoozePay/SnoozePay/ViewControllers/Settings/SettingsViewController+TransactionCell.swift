import UIKit
import os

// MARK: - Transaction History VC + cell
//
// Extracted from `SettingsViewController.swift` (#182) so the host file
// stays under SwiftLint's `file_length` cap. These two siblings used to
// live at file scope below the main VC — only the physical location moved;
// behaviour is verbatim.

/// Pushed by `SettingsViewController` when the user taps "История транзакций"
/// in the .account section. Renders the latest ledger entries as inset-grouped
/// rows with the `TransactionCell` below.
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
        view.backgroundColor = AppColors.bg0
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

    private func loadTransactions() {
        // Use the checked variant so a corrupt ledger surfaces an alert
        // instead of rendering the misleading "Нет транзакций" empty state
        // — that would let the user assume the app reset itself (issue #117).
        do {
            transactions = try TransactionRepository.shared.fetchAllChecked()
        } catch let error as TransactionRepository.RepositoryError {
            transactions = []
            presentLoadError(error)
        } catch {
            transactions = []
        }
        tableView.reloadData()
    }

    private func presentLoadError(_ error: LocalizedError) {
        let alert = UIAlertController(
            title: "Ошибка",
            message: error.errorDescription,
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

        // Look up alarm name if available — best-effort enrichment. If the
        // alarm store is corrupt we log and fall back to nil so the row
        // still renders (transaction amount/date is still meaningful).
        // Without this, a single corrupt alarms blob would silently strip
        // alarm names from every history row (issue #117).
        var alarmName: String?
        if let alarmIDString = transaction.alarmID, let alarmUUID = UUID(uuidString: alarmIDString) {
            do {
                alarmName = try alarmRepository.fetchChecked(id: alarmUUID)?.name
            } catch {
                let errorDesc = String(describing: error)
                AppLogger.ui.error(
                    "TxHistory: name lookup failed for \(alarmUUID, privacy: .private): \(errorDesc, privacy: .public)"
                )
            }
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

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return nil
        }
        return SectionHeaderView(text: title)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    /// Mirror SettingsViewController so the transaction list reads as a card
    /// in light mode rather than blending into the page.
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position = CardRowPosition.resolve(row: indexPath.row, totalRows: totalRows)
        cell.styleAsCardRow(position: position)
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
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyMd
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
        let isCredit = transaction.type != .charge

        // Icon — credits (topup, promotion) read green/up; charges red/down.
        // Promotion gets a distinct gift glyph so the user can tell a
        // referral bonus apart from an IAP top-up at a glance (issue #144).
        iconContainer.backgroundColor = isCredit ? AppColors.money500 : AppColors.pain500
        let iconName: String
        switch transaction.type {
        case .topup:     iconName = "arrow.up"
        case .charge:    iconName = "arrow.down"
        case .promotion: iconName = "gift.fill"
        }
        iconImageView.image = UIImage(systemName: iconName)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        )

        // Title — promotion reads "Бонус" so the row doesn't claim the user
        // paid for the credit (which would mislead anyone scanning their
        // history for IAP receipts).
        switch transaction.type {
        case .topup:     titleLabel.text = "Пополнение"
        case .charge:    titleLabel.text = "Откладывание"
        case .promotion: titleLabel.text = "Бонус"
        }

        // Subtitle: alarm name + date for charges; just the date otherwise.
        let dateString = Self.formatDate(transaction.createdAt)
        if let name = alarmName, transaction.type == .charge {
            subtitleLabel.text = "\(name) \u{00B7} \(dateString)"
        } else {
            subtitleLabel.text = dateString
        }

        // Amount
        let amount = Int(transaction.amount)
        if isCredit {
            amountLabel.text = "+₽\(amount)"
            amountLabel.textColor = AppColors.money500
        } else {
            amountLabel.text = "₽\(amount)"
            amountLabel.textColor = AppColors.pain500
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
