import UIKit

/// Wallet tab — V3 informational layout (issue #233, artboard 18 in
/// `docs/design/v2-handoff/components/SPScreensV2.jsx` `WalletV2`). Hosts:
///
/// - Page-title header: h1 «Кошелёк» + small money "Пополнить" pill +
///   bottom hairline (same pattern as `SPAlarmsListHeader`)
/// - SPBalanceCard hero with live weekly delta + affordability hint
/// - 7-day mini chart (`WalletWeeklyChartView`) summing pain transactions
/// - "История операций" preview — last 3 transactions + "Все операции →"
///   link into `WalletTransactionHistoryViewController`
/// - Quiet footer disclaimer
///
/// Amount selection moved into `DepositBottomSheetViewController`
/// (artboard 19) — the preset grid, bottom CTA and the "Способы оплаты"
/// row were removed from this tab per #233.
///
/// Layout helpers live in `WalletViewController+Layout.swift`; balance
/// hints live in `WalletHints.swift`.
final class WalletViewController: UIViewController {

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let balanceCard: SPBalanceCard
    private let weeklyChart = WalletWeeklyChartView()

    /// Single-child host whose transaction-preview card is rebuilt on every
    /// refresh — transactions change behind this screen's back (snoozes,
    /// firing-time top-ups), so the rows can't be static.
    private let txPreviewHost: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        return stack
    }()

    private lazy var pageHeader = makePageHeader(
        target: self,
        action: #selector(presentDepositSheet)
    )

    // MARK: - Init

    init() {
        let initialBalance = Decimal(BalanceService.shared.balance)
        balanceCard = SPBalanceCard(
            balance: initialBalance,
            delta: nil,
            hint: WalletHints.defaultBalanceHint()
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
        // The custom page header carries the h1 — suppress the nav-bar title
        // so the word doesn't render twice (same as the Alarms tab).
        navigationItem.title = ""
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        // The design has no Settings entry on the Wallet tab (#280) — the gear
        // was an invented affordance. Drop the bar item and hide the system
        // nav bar entirely (mirrors the Alarms tab); the bar is restored just
        // before child screens are pushed so they keep their back arrow.
        navigationItem.rightBarButtonItem = nil

        setupLayout()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceChanged),
            name: BalanceService.balanceChangedNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the system nav bar on this tab — the custom page header owns the
        // title and there's no bar item to show (#280). Restored before a child
        // push (`openHistory`) so the child keeps its back arrow; popping back
        // here re-hides it.
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refresh()
    }

    // MARK: - Layout

    private func setupLayout() {
        pageHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageHeader)

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
        contentStack.addArrangedSubview(makeWeeklyChartSection())
        contentStack.addArrangedSubview(makeTxPreviewSection())
        contentStack.addArrangedSubview(makeFooterCaption())

        NSLayoutConstraint.activate([
            pageHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pageHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: pageHeader.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            weeklyChart.heightAnchor.constraint(equalToConstant: 80)
        ])
    }

    private func makeWeeklyChartSection() -> UIView {
        let header = makeWeeklyChartHeader()
        let stack = UIStackView(arrangedSubviews: [header, weeklyChart])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        return stack
    }

    private func makeTxPreviewSection() -> UIView {
        let header = makeTxPreviewHeader(target: self, action: #selector(openHistory))
        let stack = UIStackView(arrangedSubviews: [header, txPreviewHost])
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        return stack
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
        let hint = WalletHints.affordHint(forBalance: balance, averagePrice: 50)
        balanceCard.update(balance: decimal, delta: delta, hint: hint)
        weeklyChart.update(values: WalletStats.weeklyPenaltyTotals())
        rebuildTxPreview()
    }

    private func rebuildTxPreview() {
        for sub in txPreviewHost.arrangedSubviews {
            txPreviewHost.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        let items = WalletTransactionPreview.items(
            from: TransactionRepository.shared.fetchAll(),
            alarmLookup: { AlarmRepository.shared.fetch(id: $0) }
        )
        txPreviewHost.addArrangedSubview(makeTxPreviewCard(items: items))
    }

    // MARK: - Navigation

    @objc private func presentDepositSheet() {
        let sheet = DepositBottomSheetViewController()
        present(sheet, animated: true)
    }

    @objc private func openHistory() {
        // The nav bar is hidden on this root (#280) — restore it before the
        // push so the history screen keeps its standard back arrow + title.
        // `viewWillAppear` re-hides it when the user pops back.
        navigationController?.setNavigationBarHidden(false, animated: true)
        let history = WalletTransactionHistoryViewController()
        navigationController?.pushViewController(history, animated: true)
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
