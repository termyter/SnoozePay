import UIKit

/// Wallet tab — replaces the legacy Settings tab. This is a Phase-0 stub:
/// renders the SPBalanceCard hero and routes "Пополнить" through the
/// existing TopUpViewController. Agent C will replace the body with the
/// full V2 layout (presets grid, weekly bars, Apple Pay CTA).
final class WalletViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let balanceCard: SPBalanceCard
    private let topUpButton = SPButton(
        title: "Пополнить",
        variant: .money,
        size: .lg,
        icon: UIImage(systemName: "applelogo"),
        fullWidth: true
    )

    init() {
        let decimalBalance = Decimal(BalanceService.shared.balance)
        balanceCard = SPBalanceCard(
            balance: decimalBalance,
            delta: nil,
            hint: nil
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        title = "Кошелёк"
        navigationController?.navigationBar.prefersLargeTitles = true

        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem = settingsButton

        setupLayout()
        topUpButton.addTarget(self, action: #selector(presentTopUp), for: .touchUpInside)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceChanged),
            name: BalanceService.balanceChangedNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshBalance()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AppSpacing.sp5
        contentStack.alignment = .fill
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AppSpacing.sp4,
            leading: AppSpacing.screenInset,
            bottom: AppSpacing.sp7,
            trailing: AppSpacing.screenInset
        )
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)

        balanceCard.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(balanceCard)
        contentStack.addArrangedSubview(topUpButton)

        let placeholder = makePlaceholderCard()
        contentStack.addArrangedSubview(placeholder)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            topUpButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func makePlaceholderCard() -> UIView {
        let card = SPCard()
        card.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "История пополнений и операций появится здесь."
        label.font = AppTypography.body
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: AppSpacing.sp6),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp5),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppSpacing.sp5),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.sp6)
        ])
        return card
    }

    // MARK: - Actions

    @objc private func presentTopUp() {
        let topUpVC = TopUpViewController()
        let nav = UINavigationController(rootViewController: topUpVC)
        present(nav, animated: true)
    }

    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }

    @objc private func balanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshBalance()
        }
    }

    private func refreshBalance() {
        balanceCard.update(
            balance: Decimal(BalanceService.shared.balance),
            delta: nil,
            hint: nil
        )
    }
}
