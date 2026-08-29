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

    /// Dedupe latch so the balance-corruption alert fires once per episode
    /// even though `viewWillAppear` runs on every tab switch (and the live
    /// notification + the pulled cold-start state could otherwise double-fire).
    /// Reset after the user acknowledges so a future re-corruption surfaces
    /// again. Mirrors `AlarmsListViewModel.hasSurfacedBalanceCorruption` (#206).
    private var hasSurfacedBalanceCorruption = false

    // MARK: - Init

    init() {
        let initialBalance = BalanceService.shared.balance
        balanceCard = SPBalanceCard(
            balance: Decimal(initialBalance),
            delta: nil,
            // Real hint from the first frame (#546). The placeholder this
            // replaced was a hardcoded "~17 откладываний" that the first
            // `refresh()` then contradicted.
            hint: WalletHints.affordHint(
                forBalance: initialBalance,
                alarms: AlarmRepository.shared.fetchAll()
            )
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
        // Wallet is the primary balance/top-up surface — it must surface a
        // corrupt `user_balance` (negative / NaN / infinite), which clamps to
        // `0` in `BalanceService.balance` and would otherwise render as a
        // silent "0 ₽" with no recovery path (#419). Covers corruption that
        // latches while this VC is alive; cold-start corruption is pulled in
        // `viewWillAppear` since NotificationCenter doesn't retro-deliver (#206).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceCorrupted),
            name: BalanceService.balanceCorruptedNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the system nav bar on this tab — the custom page header owns the
        // title and there's no bar item to show (#280). Restored before a child
        // push (`openHistory`) so the child keeps its back arrow; popping back
        // here re-hides it. Shared helper keeps the pair symmetric with the
        // other two bar-less tabs (#517).
        AppNavigationBarStyle.hideBar(on: self, animated: animated)
        refresh()
        // Pull corruption latched BEFORE this VC observed it (cold start: the
        // BalanceService init-time probe posts with no listener attached, and
        // NotificationCenter drops it for late subscribers — #206).
        surfacePendingBalanceCorruption()
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
        // Checked read so a corrupt ledger drives the error banner instead of
        // the lossy `fetchAll()` rendering a deceptive empty preview (#419).
        // Shared across the delta, the chart and the preview so a single
        // decode failure classifies all three the same way.
        let load = WalletLedgerLoad.load(from: TransactionRepository.shared)
        let transactions = load.transactions
        let delta = load.didFail ? nil : WalletStats.weeklyDelta(from: transactions)
        // Alarms feed the "Хватит на ~N" price (#546) — the number used to be
        // divided by a hardcoded 50 ₽ here, which is why this card and the
        // alarms list disagreed. The lossy `fetchAll` is deliberate: an
        // unreadable alarm store degrades the hint to the user's configured
        // default price, it does not put an error banner on the wallet.
        let hint = WalletHints.affordHint(
            forBalance: balance,
            alarms: AlarmRepository.shared.fetchAll()
        )
        balanceCard.update(balance: decimal, delta: delta, hint: hint)
        weeklyChart.update(values: WalletStats.weeklyPenaltyTotals(from: transactions))
        rebuildTxPreview(load: load)
    }

    private func rebuildTxPreview(load: WalletLedgerLoad) {
        for sub in txPreviewHost.arrangedSubviews {
            txPreviewHost.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        guard !load.didFail else {
            txPreviewHost.addArrangedSubview(makeTxPreviewErrorCard())
            return
        }
        let items = WalletTransactionPreview.items(
            from: load.transactions,
            // Checked read collapsed with `try?` (#271) — see the sibling site
            // in `WalletTransactionHistoryViewController`: an unreadable alarm
            // store degrades the row's caption, it does not fake an empty list.
            alarmLookup: { try? AlarmRepository.shared.fetchChecked(id: $0) }
        )
        txPreviewHost.addArrangedSubview(makeTxPreviewCard(items: items))
    }

    // MARK: - Balance corruption (#119 / #206 / #419)

    @objc private func balanceCorrupted(_ note: Notification) {
        let raw = note.userInfo?[BalanceService.balanceCorruptedRawValueKey] as? Double
        DispatchQueue.main.async { [weak self] in
            self?.surfaceBalanceCorruption(rawValue: raw)
        }
    }

    /// Pulls corruption state latched before this VC attached its observer.
    private func surfacePendingBalanceCorruption() {
        guard BalanceService.shared.balanceCorrupted else { return }
        surfaceBalanceCorruption(rawValue: BalanceService.shared.corruptedRawValue)
    }

    private func surfaceBalanceCorruption(rawValue: Double?) {
        guard !hasSurfacedBalanceCorruption else { return }
        hasSurfacedBalanceCorruption = true

        let alert = UIAlertController(
            title: "Баланс повреждён",
            message: "Сохранённый баланс некорректен и был сброшен в ноль. "
                + "Пополнения временно недоступны, пока вы не подтвердите сброс.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive) { [weak self] _ in
            BalanceService.shared.acknowledgeCorruption()
            // Allow a future re-corruption episode to surface a fresh alert.
            self?.hasSurfacedBalanceCorruption = false
            self?.refresh()
        })
        alert.addAction(UIAlertAction(title: "Позже", style: .cancel) { [weak self] _ in
            // Keep the gate visible: a dismissed alert must still re-prompt on
            // the next appearance until the user resets.
            self?.hasSurfacedBalanceCorruption = false
        })
        present(alert, animated: true)
    }

    // MARK: - Navigation

    @objc private func presentDepositSheet() {
        // Guard against double-present from a fast double-tap (#389).
        guard presentedViewController == nil else { return }
        let sheet = DepositBottomSheetViewController()
        present(sheet, animated: true)
    }

    @objc private func openHistory() {
        // The nav bar is hidden on this root (#280) — the helper restores it
        // before the push so the history screen keeps its standard back arrow
        // + title. `viewWillAppear` re-hides it when the user pops back.
        AppNavigationBarStyle.pushRestoringBar(
            WalletTransactionHistoryViewController(),
            from: self
        )
    }
}

// MARK: - Stats helpers

/// Wallet-screen specific stats — kept inside this file so the calculation
/// stays adjacent to the only call site. If another screen needs the same
/// numbers, lift it onto `TransactionRepository`.
enum WalletStats {

    /// Net change over the last 7 days. Positive = the user added more
    /// than they paid in penalties; negative = penalties dominated.
    ///
    /// Takes a pre-loaded, decode-checked transaction list (#419) so the
    /// caller's single `WalletLedgerLoad` drives the delta, the chart and the
    /// preview together — a corrupt ledger surfaces a banner instead of these
    /// reading a lossy `fetchAll()` and silently rendering a zero delta.
    static func weeklyDelta(from transactions: [Transaction]) -> Decimal? {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else {
            return nil
        }
        let recent = transactions.filter {
            $0.createdAt >= weekAgo
        }
        guard !recent.isEmpty else { return nil }
        var net: Decimal = 0
        for transaction in recent {
            let amount = Decimal(transaction.amount)
            switch transaction.type {
            case .topup, .promotion, .refund:
                // `.refund` still moves money INTO the wallet — excluding it
                // would make the delta contradict the actual balance, which is
                // why #358 changed the ledger type, not the balance maths.
                net += amount
            case .charge:
                net -= amount
            case .unknown:
                continue // direction unknown — can't be signed into the delta
            }
        }
        return net
    }

    /// Per-day pain totals for the trailing 7-day window, oldest → newest.
    /// Used by `WalletWeeklyChartView` — only `.charge` rows contribute.
    /// Takes the caller's decode-checked transaction list (#419).
    static func weeklyPenaltyTotals(from transactions: [Transaction]) -> [Decimal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totals = Array(repeating: Decimal.zero, count: 7)
        for transaction in transactions where transaction.type == .charge {
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
