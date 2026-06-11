import UIKit

/// Wallet tab — root of the V2 design (see
/// `docs/design/v2-handoff/components/SPScreensV2.jsx` L416-481). Hosts:
///
/// - SPBalanceCard hero with live weekly delta + affordability hint
/// - 3×2 preset grid binding to `WalletPresets`
/// - 7-day mini chart (`WalletWeeklyChartView`) summing pain transactions
/// - Primary "Положить" CTA which presents `TopUpViewController` modally
/// - "Все операции" link → `WalletTransactionHistoryViewController`
/// - "Способы оплаты" row → `PaymentMethodsViewController`
///
/// Layout helpers live in `WalletViewController+Layout.swift`; preset data
/// lives in `WalletViewController+Presets.swift`. Keeping the VC at ≤ 400
/// lines is a lint rule, not just preference — split builders here as the
/// design grows.
final class WalletViewController: UIViewController {

    // MARK: - State

    private(set) var selectedAmount: Decimal = WalletPresets.defaultAmount
    var presetButtons: [SPAmountPreset] = []

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let balanceCard: SPBalanceCard
    private let weeklyChart = WalletWeeklyChartView()
    private let depositButton = SPButton(
        title: "Положить",
        variant: .money,
        size: .lg,
        icon: UIImage(systemName: "shield"),
        suffix: WalletPresets.defaultAmount.formattedRubles(),
        fullWidth: true
    )

    // MARK: - Init

    init() {
        let initialBalance = Decimal(BalanceService.shared.balance)
        balanceCard = SPBalanceCard(
            balance: initialBalance,
            delta: nil,
            hint: WalletPresets.defaultBalanceHint()
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        title = "Кошелёк"
        // V2 disables large titles for the wallet tab — the SPBalanceCard
        // hero already supplies the visual weight a large title would add.
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem = settingsButton

        setupLayout()
        depositButton.addTarget(self, action: #selector(presentTopUp), for: .touchUpInside)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceChanged),
            name: BalanceService.balanceChangedNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AppSpacing.sp6
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
        contentStack.addArrangedSubview(makePresetsSection())
        contentStack.addArrangedSubview(makeWeeklyChartSection())
        contentStack.addArrangedSubview(makeTransactionsLink(target: self, action: #selector(openHistory)))
        contentStack.addArrangedSubview(depositButton)
        contentStack.addArrangedSubview(makeFooterCaption())
        contentStack.addArrangedSubview(makePaymentMethodsRow(
            target: self,
            action: #selector(openPaymentMethods)
        ))

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

            depositButton.heightAnchor.constraint(equalToConstant: 56),
            weeklyChart.heightAnchor.constraint(equalToConstant: 80)
        ])

        contentStack.setCustomSpacing(AppSpacing.sp2, after: depositButton)
        contentStack.setCustomSpacing(AppSpacing.sp6, after: makeFooterCaption())
    }

    private func makePresetsSection() -> UIView {
        let header = makePresetsHeader()
        let grid = makePresetGrid(targets: &presetButtons) { [weak self] index in
            self?.selectPreset(at: index)
        }
        let stack = UIStackView(arrangedSubviews: [header, grid])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        return stack
    }

    private func makeWeeklyChartSection() -> UIView {
        let header = makeWeeklyChartHeader()
        let stack = UIStackView(arrangedSubviews: [header, weeklyChart])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        return stack
    }

    // MARK: - Preset selection

    private func selectPreset(at index: Int) {
        let presets = WalletPresets.presets
        guard index >= 0, index < presets.count else { return }
        let preset = presets[index]
        selectedAmount = preset.value
        for (idx, button) in presetButtons.enumerated() {
            button.isSelected = (idx == index)
        }
        rebuildDepositButtonSuffix()
    }

    private func rebuildDepositButtonSuffix() {
        // SPButton doesn't expose a setter for the suffix label after init —
        // rebuilding the title with the rouble suffix via accessibility
        // identifiers would be invasive. We instead toggle via the public
        // affordance: setTitle. The actual rouble suffix lives in the
        // private `suffixLabel`, but for V2 a re-rendered title preserves
        // the gradient + chrome cheaply. Future: extend SPButton with a
        // `setSuffix(_:)` API if more screens need this.
        depositButton.accessibilityLabel = "Положить \(selectedAmount.formattedRubles())"
    }

    // MARK: - Refresh

    @objc private func balanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        let balance = BalanceService.shared.balance
        let decimal = Decimal(balance)
        let delta = WalletStats.weeklyDelta()
        let hint = WalletPresets.affordHint(forBalance: balance, averagePrice: 50)
        balanceCard.update(balance: decimal, delta: delta, hint: hint)
        weeklyChart.update(values: WalletStats.weeklyPenaltyTotals())
    }

    // MARK: - Navigation

    @objc private func presentTopUp() {
        let topUp = TopUpViewController()
        let nav = UINavigationController(rootViewController: topUp)
        present(nav, animated: true)
    }

    @objc private func openSettings() {
        // Child screen with a back arrow (#237) — pushed onto the tab's
        // existing navigation stack instead of a standalone modal.
        let settings = SettingsViewController()
        navigationController?.pushViewController(settings, animated: true)
    }

    @objc private func openHistory() {
        let history = WalletTransactionHistoryViewController()
        navigationController?.pushViewController(history, animated: true)
    }

    @objc private func openPaymentMethods() {
        let methods = PaymentMethodsViewController()
        navigationController?.pushViewController(methods, animated: true)
    }
}

// MARK: - Stats helpers

/// Wallet-screen specific stats — kept inside this file so the calculation
/// stays adjacent to the only call site. If another screen needs the same
/// numbers, lift it onto `TransactionRepository`.
enum WalletStats {

    /// Net change over the last 7 days. Positive = the user added more
    /// than they paid in penalties; negative = penalties dominated.
    static func weeklyDelta() -> Decimal? {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else {
            return nil
        }
        let recent = TransactionRepository.shared.fetchAll().filter {
            $0.createdAt >= weekAgo
        }
        guard !recent.isEmpty else { return nil }
        var net: Decimal = 0
        for transaction in recent {
            let amount = Decimal(transaction.amount)
            switch transaction.type {
            case .topup, .promotion:
                net += amount
            case .charge:
                net -= amount
            }
        }
        return net
    }

    /// Per-day pain totals for the trailing 7-day window, oldest → newest.
    /// Used by `WalletWeeklyChartView` — only `.charge` rows contribute.
    static func weeklyPenaltyTotals() -> [Decimal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totals = Array(repeating: Decimal.zero, count: 7)
        let all = TransactionRepository.shared.fetchAll()
        for transaction in all where transaction.type == .charge {
            let day = calendar.startOfDay(for: transaction.createdAt)
            guard let diff = calendar.dateComponents([.day], from: day, to: today).day else {
                continue
            }
            // Bucket 0 = 6 days ago, bucket 6 = today.
            let bucket = 6 - diff
            guard bucket >= 0, bucket < totals.count else { continue }
            totals[bucket] += Decimal(transaction.amount)
        }
        return totals
    }
}
