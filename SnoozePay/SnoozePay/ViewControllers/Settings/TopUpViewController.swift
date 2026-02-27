import UIKit
import StoreKit

/// Top-up balance screen with 5 fixed IAP packages.
class TopUpViewController: UIViewController {

    // MARK: - UI

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let balanceHeaderView = UIView()

    private let balanceLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 48, weight: .thin)
        l.textColor = .label
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let balanceTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Текущий баланс"
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let storeService = StoreKitService.shared
    private var loadingProductID: String?

    // Fixed packages shown while products load
    private let fallbackPackages: [(label: String, amount: Double)] = [
        ("49 ₽", 49), ("149 ₽", 149), ("299 ₽", 299), ("499 ₽", 499), ("999 ₽", 999)
    ]

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
        updateBalanceLabel()
        loadStoreProducts()
    }

    // MARK: - Setup

    private func setupTableView() {
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

        // Header with balance
        balanceHeaderView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 130)
        balanceHeaderView.addSubview(balanceTitleLabel)
        balanceHeaderView.addSubview(balanceLabel)
        NSLayoutConstraint.activate([
            balanceTitleLabel.topAnchor.constraint(equalTo: balanceHeaderView.topAnchor, constant: 20),
            balanceTitleLabel.centerXAnchor.constraint(equalTo: balanceHeaderView.centerXAnchor),
            balanceLabel.topAnchor.constraint(equalTo: balanceTitleLabel.bottomAnchor, constant: 4),
            balanceLabel.centerXAnchor.constraint(equalTo: balanceHeaderView.centerXAnchor)
        ])
        tableView.tableHeaderView = balanceHeaderView
    }

    private func updateBalanceLabel() {
        balanceLabel.text = "\(Int(BalanceService.shared.balance)) ₽"
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
            // Products not yet loaded — show alert
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
        Task {
            loadingProductID = product.id
            tableView.reloadData()

            await storeService.purchase(product)

            loadingProductID = nil
            updateBalanceLabel()
            tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource

extension TopUpViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? fallbackPackages.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "ВЫБЕРИТЕ ПАКЕТ" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Оплата через App Store" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Восстановить покупки"
            cell.textLabel?.textColor = .systemBlue
            cell.textLabel?.textAlignment = .center
            return cell
        }

        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let fallback = fallbackPackages[indexPath.row]
        let products = storeService.products

        if indexPath.row < products.count {
            let product = products[indexPath.row]
            cell.textLabel?.text = product.displayName.isEmpty ? fallback.label : product.displayName
            cell.detailTextLabel?.text = product.displayPrice
        } else {
            cell.textLabel?.text = fallback.label
            cell.textLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        }

        // Loading indicator
        if let loading = loadingProductID, indexPath.row < products.count,
           products[indexPath.row].id == loading {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
        } else {
            cell.accessoryView = nil
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension TopUpViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 56 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 1 {
            // Restore purchases
            Task {
                try? await AppStore.sync()
                updateBalanceLabel()
            }
            return
        }

        purchaseProduct(at: indexPath.row)
    }
}
