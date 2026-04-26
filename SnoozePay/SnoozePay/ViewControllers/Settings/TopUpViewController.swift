import UIKit
import StoreKit

/// Top-up balance screen with balance card, 5 IAP packages, and restore button.
class TopUpViewController: UIViewController {

    // MARK: - Package Data

    private struct Package {
        let amount: Int
        let subtitle: String
        let isPopular: Bool
    }

    private let packages: [Package] = [
        Package(amount: 49, subtitle: "~1 откладывание", isPopular: false),
        Package(amount: 149, subtitle: "~3 откладывания", isPopular: true),
        Package(amount: 299, subtitle: "~6 откладываний", isPopular: false),
        Package(amount: 499, subtitle: "~10 откладываний", isPopular: false),
        Package(amount: 999, subtitle: "~20 откладываний", isPopular: false)
    ]

    // MARK: - UI

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let storeService = StoreKitService.shared
    private var loadingProductID: String?

    /// NotificationCenter tokens — removed in `deinit`.
    private var purchaseFailedObserver: NSObjectProtocol?
    private var purchasePendingObserver: NSObjectProtocol?

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case packages
        case restore
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Пополнить баланс"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        setupTableView()
        wireStoreCallbacks()
        loadStoreProducts()
    }

    private func wireStoreCallbacks() {
        // loadProducts() and the foreground purchase path post `purchaseFailedNotification`
        // when the store is unreachable or a verification/cancel error occurs.
        // Without this wiring, the user-visible error message added in IOS-032
        // would silently drop on the floor.
        purchaseFailedObserver = NotificationCenter.default.addObserver(
            forName: StoreKitService.purchaseFailedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let message = note.userInfo?[StoreKitService.messageUserInfoKey] as? String else { return }
            self.presentErrorAlert(message)
        }
    }

    deinit {
        if let token = purchaseFailedObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = purchasePendingObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func presentErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Ошибка", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Setup

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TopUpPackageCell.self, forCellReuseIdentifier: TopUpPackageCell.reuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "restore")

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        tableView.tableHeaderView = makeBalanceHeader()
    }

    // MARK: - Balance Header

    private func makeBalanceHeader() -> UIView {
        let headerHeight: CGFloat = 140
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight))

        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = AppRadius.md
        card.layer.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(card)

        let titleLabel = UILabel()
        titleLabel.text = "Текущий баланс"
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let balanceLabel = UILabel()
        balanceLabel.text = "₽\(Int(BalanceService.shared.balance))"
        balanceLabel.font = UIFont.systemFont(ofSize: 42, weight: .bold)
        balanceLabel.textColor = AppColors.accentBlue
        balanceLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, balanceLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: AppSpacing.xl),
            card.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -AppSpacing.xl),
            card.topAnchor.constraint(equalTo: header.topAnchor, constant: AppSpacing.lg),
            card.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -AppSpacing.sm),

            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        return header
    }

    private func loadStoreProducts() {
        Task {
            await storeService.loadProducts()
            tableView.reloadData()
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func purchaseProduct(at index: Int) {
        let products = storeService.products
        guard index < products.count else {
            let alert = UIAlertController(
                title: "Недоступно",
                message: "Магазин временно недоступен. Попробуйте позже.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let product = products[index]

        // Subscribe per-purchase. Removed at the end of the Task so the observer
        // does not outlive the purchase attempt that registered it. NotificationCenter
        // tolerates multiple observers on the same name from the same instance —
        // we still defensively remove the previous token (if any) to avoid two
        // alerts for back-to-back taps.
        if let previousToken = purchasePendingObserver {
            NotificationCenter.default.removeObserver(previousToken)
        }
        purchasePendingObserver = NotificationCenter.default.addObserver(
            forName: StoreKitService.purchasePendingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentPendingAlert()
        }

        Task {
            loadingProductID = product.id
            tableView.reloadData()

            await storeService.purchase(product)

            loadingProductID = nil
            // Refresh balance header
            tableView.tableHeaderView = makeBalanceHeader()
            tableView.reloadData()
            // Always clear — including the .pending case where the alert was shown.
            // The actual credit happens later via Transaction.updates listener; the
            // pending observer's job ends with the alert.
            if let token = purchasePendingObserver {
                NotificationCenter.default.removeObserver(token)
                purchasePendingObserver = nil
            }
        }
    }

    private func presentPendingAlert() {
        let alert = UIAlertController(
            title: "Ожидаем подтверждения",
            message: "Покупка ожидает одобрения родителя. Баланс пополнится автоматически.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension TopUpViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .packages: return packages.count
        case .restore: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .packages: return "ВЫБЕРИТЕ ПАКЕТ"
        case .restore: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .packages:
            return "Средства добавляются на ваш баланс мгновенно. Неиспользованный баланс не сгорает."
        case .restore: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }

        switch section {
        case .restore:
            let cell = UITableViewCell(style: .default, reuseIdentifier: "restore")
            cell.textLabel?.text = "Восстановить покупки"
            cell.textLabel?.textColor = .systemBlue
            cell.textLabel?.textAlignment = .center
            cell.backgroundColor = .secondarySystemBackground
            return cell

        case .packages:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: TopUpPackageCell.reuseID, for: indexPath
            ) as? TopUpPackageCell else {
                assertionFailure("dequeueReusableCell returned wrong type for \(TopUpPackageCell.reuseID)")
                return UITableViewCell()
            }

            let pkg = packages[indexPath.row]
            let products = storeService.products
            let isLoading = indexPath.row < products.count && products[indexPath.row].id == loadingProductID
            cell.configure(amount: pkg.amount, subtitle: pkg.subtitle, isPopular: pkg.isPopular, isLoading: isLoading)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension TopUpViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let sec = Section(rawValue: indexPath.section) else { return 44 }
        switch sec {
        case .packages: return 64
        case .restore: return 48
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sec = Section(rawValue: indexPath.section) else { return }

        switch sec {
        case .restore:
            performRestorePurchases()
        case .packages:
            purchaseProduct(at: indexPath.row)
        }
    }
}

// MARK: - Restore Purchases

extension TopUpViewController {

    /// Wraps `AppStore.sync()` and surfaces typed errors instead of swallowing them
    /// with `try?`. A silent failure here would let the user think no past purchases
    /// exist and re-buy a package — a real financial loss path (#71).
    fileprivate func performRestorePurchases() {
        let balanceBeforeSync = BalanceService.shared.balance

        Task { [weak self] in
            guard let self else { return }
            do {
                try await AppStore.sync()
                self.tableView.tableHeaderView = self.makeBalanceHeader()

                // Heuristic: `AppStore.sync()` triggers `Transaction.updates` which
                // credits the balance asynchronously. We sample after the await; if
                // nothing changed we tell the user no purchases were found rather than
                // leaving the screen silent.
                let creditedSomething = BalanceService.shared.balance > balanceBeforeSync
                self.presentRestoreSuccess(credited: creditedSomething)
            } catch {
                self.presentRestoreError(error)
            }
        }
    }

    private func presentRestoreSuccess(credited: Bool) {
        let title = credited ? "Покупки восстановлены" : "Покупок не найдено"
        let message = credited
            ? "Баланс обновлён."
            : "Мы не нашли предыдущих покупок, привязанных к вашему Apple ID."
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentRestoreError(_ error: Error) {
        let alert = UIAlertController(
            title: "Не удалось восстановить покупки",
            message: restoreErrorMessage(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Maps StoreKit / URLError failures to actionable Russian copy. Generic errors
    /// fall back to the underlying `localizedDescription` plus support hint so the
    /// user is never left with a silent button tap.
    private func restoreErrorMessage(for error: Error) -> String {
        let nsError = error as NSError

        // Network reachability — URLError or NSURLErrorDomain bubbles up here.
        if nsError.domain == NSURLErrorDomain {
            return "Проверьте подключение к интернету и попробуйте снова."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return "Проверьте подключение к интернету и попробуйте снова."
            default:
                break
            }
        }

        // StoreKit auth — codes vary by iOS version, fall back to substring match
        // on the localized description which is what AppStore.sync surfaces.
        let description = nsError.localizedDescription.lowercased()
        if description.contains("not authenticated")
            || description.contains("sign")
            || description.contains("apple id") {
            return "Войдите в Apple ID в Настройках и попробуйте снова."
        }

        return "\(error.localizedDescription)\n\nЕсли проблема повторяется, свяжитесь с поддержкой."
    }
}

// MARK: - Top-Up Package Cell

final class TopUpPackageCell: UITableViewCell {

    static let reuseID = "TopUpPackageCell"

    // MARK: - UI

    private let coinIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "rublesign.circle.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        )
        imageView.tintColor = AppColors.accentOrange
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    private let popularBadge: UILabel = {
        let label = UILabel()
        label.text = "Популярный"
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = AppColors.accentBlue
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
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

        let textStack = UIStackView(arrangedSubviews: [amountLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let leftStack = UIStackView(arrangedSubviews: [coinIcon, textStack])
        leftStack.axis = .horizontal
        leftStack.spacing = AppSpacing.md
        leftStack.alignment = .center
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(leftStack)
        contentView.addSubview(popularBadge)

        NSLayoutConstraint.activate([
            coinIcon.widthAnchor.constraint(equalToConstant: 36),
            coinIcon.heightAnchor.constraint(equalToConstant: 36),

            leftStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            leftStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            popularBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            popularBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            popularBadge.widthAnchor.constraint(equalToConstant: 86),
            popularBadge.heightAnchor.constraint(equalToConstant: 22)
        ])

        accessoryType = .disclosureIndicator
    }

    // MARK: - Configure

    func configure(amount: Int, subtitle: String, isPopular: Bool, isLoading: Bool) {
        amountLabel.text = "₽\(amount)"
        subtitleLabel.text = subtitle
        popularBadge.isHidden = !isPopular

        if isLoading {
            spinner.startAnimating()
            accessoryView = spinner
        } else {
            spinner.stopAnimating()
            accessoryView = nil
            accessoryType = .disclosureIndicator
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        popularBadge.isHidden = true
        spinner.stopAnimating()
        accessoryView = nil
        accessoryType = .disclosureIndicator
    }
}
