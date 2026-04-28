import UIKit
import os

/// Settings screen matching Figma design: account, theme, legal, contact sections.
class SettingsViewController: UIViewController {

    // MARK: - Dependencies

    private let themeService: ThemeService

    // MARK: - UI

    /// Internal so `SettingsViewController+Referral` can call
    /// `reloadSections` after a successful friend-code apply (issue #144).
    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    /// Held weakly so the cell may be recycled (and the label deallocated)
    /// without leaving the observer with a dangling reference. `internal`
    /// so the cross-file `+Sections.makeBalanceRow` can capture a fresh
    /// reference each time the row is dequeued (#182).
    weak var balanceAmountLabel: UILabel?

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

    /// `internal` so the cross-file `SettingsViewController+Referral`
    /// extension can read `Section.referral` for the `reloadSections`
    /// call (issue #144).
    enum Section: Int, CaseIterable {
        case account    // Transaction history + Balance
        case referral   // My code (copyable) + friend's code input + caption
        case appearance // Theme selector (system / light / dark)
        case info       // Privacy policy + Terms
        case contact    // Contact us
    }

    /// Row layout inside `.referral`. Indexed positions stay readable when
    /// the table calls `cellForRowAt:` — the alternative (raw `0/1/2`)
    /// trades a static enum mismatch error for a runtime off-by-one.
    enum ReferralRow: Int, CaseIterable {
        case myCode       // "Ваш код" + 6-char code + copy icon
        case friendInput  // SPInput "Код друга" + Применить button
        case caption      // "За каждого друга — +200 ₽ ..." footer text
    }

    let referralService = ReferralService.shared

    /// Held weak so the cell may be recycled without a dangling reference.
    /// Used to surface inline validation messages from
    /// `handleApplyFriendCodeTapped` without a full `reloadData`.
    weak var friendCodeInput: SPInput?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Настройки"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = AppColors.bg0
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
        case .referral: return ReferralRow.allCases.count
        case .appearance: return 1 // Dark theme
        case .info: return 2       // Privacy, Terms
        case .contact: return 1    // Contact us
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .account: return "АККАУНТ"
        case .referral: return "ПРИГЛАСИТЬ ДРУГА"
        case .appearance: return "ОФОРМЛЕНИЕ"
        case .info: return "ИНФОРМАЦИЯ"
        case .contact: return "СВЯЗАТЬСЯ"
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Custom header view so each section uses the design-system caps role
        // + tracking instead of the default footnote font (mirrors
        // CreateAlarmViewController's pattern for cross-screen consistency).
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return nil
        }
        return makeSettingsSectionHeader(text: title)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard self.tableView(tableView, titleForHeaderInSection: section) != nil else {
            return .leastNonzeroMagnitude
        }
        // Match the system's default grouped section header height so the
        // custom typography swap doesn't shift the form's vertical rhythm.
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }

        switch section {
        case .account:    return makeAccountCell(at: indexPath)
        case .referral:   return makeReferralCell(at: indexPath)
        case .appearance: return makeAppearanceCell(tableView, at: indexPath)
        case .info:       return makeInfoRow(at: indexPath)
        case .contact:    return makeContactRow()
        }
    }

    /// Account section dispatches between the History row (`row == 0`) and
    /// the Balance row (`row == 1`). Split off `cellForRowAt` so the main
    /// switch stays a one-screen overview (#182).
    private func makeAccountCell(at indexPath: IndexPath) -> UITableViewCell {
        indexPath.row == 0 ? makeTransactionHistoryRow() : makeBalanceRow()
    }

    /// Dequeue + configure for the segmented Theme cell. Pulled out of
    /// `cellForRowAt` so the main switch stays under SwiftLint's
    /// `function_body_length` cap (#182).
    private func makeAppearanceCell(
        _ tableView: UITableView,
        at indexPath: IndexPath
    ) -> UITableViewCell {
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
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 52 }
        switch section {
        case .appearance:
            return 56
        case .referral:
            // Friend-input row hosts an SPInput (52pt field + label + hint);
            // the caption row wraps to two lines on small screens — let
            // self-sizing handle both rather than guessing.
            guard let row = ReferralRow(rawValue: indexPath.row) else { return 52 }
            switch row {
            case .myCode:      return 52
            case .friendInput: return UITableView.automaticDimension
            case .caption:     return UITableView.automaticDimension
            }
        default:
            return 52
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // `automaticDimension` paths above need an estimate or the table
        // collapses on first layout pass. 52pt matches the rest of the
        // settings rows for visual continuity.
        guard let section = Section(rawValue: indexPath.section),
              section == .referral else { return 52 }
        return 80
    }

    /// Apply the shared card-style background to every row so each
    /// `.insetGrouped` section reads as a lifted card in light mode (where
    /// `secondarySystemBackground` is barely distinguishable from
    /// `systemGroupedBackground`).
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position = CardRowPosition.resolve(row: indexPath.row, totalRows: totalRows)
        cell.styleAsCardRow(position: position)
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

        case .referral:
            // Only the "Ваш код" row has a tap behaviour — the input row owns
            // its own controls (SPInput / SPButton) and the caption row is
            // non-interactive.
            if ReferralRow(rawValue: indexPath.row) == .myCode {
                copyMyCodeToPasteboard()
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

// `TransactionHistoryViewController`, `TransactionCell`,
// `SettingsSectionHeaderView`, and `LegalViewController` were extracted to
// sibling extension files (`+TransactionCell.swift`, `+Sections.swift`,
// `+Legal.swift`) in #182 to satisfy SwiftLint's `file_length` cap. Behaviour
// is unchanged — only the physical location moved.
