import UIKit
import os

/// Settings screen, V3 layout per design (`SPMore4.jsx:344-431`, #283).
///
/// Sections: Финансы (default price · snooze duration) · Звук и уведомления
/// (volume → picker · Critical Alerts · vibration) · Правила (progressive
/// price) · Пригласить друга · Прочее (privacy · terms · contact · theme) +
/// a `SnoozePay {version} · build {build}` footer.
///
/// The legacy АККАУНТ section (transaction history + balance) was removed —
/// history is canonical in the Wallet tab now, so the duplicate row pushed a
/// stale non-V3 list.
class SettingsViewController: UIViewController {

    // MARK: - Dependencies

    private let themeService: ThemeService
    let alarmDefaults: AlarmDefaults

    // MARK: - UI

    /// Internal so `SettingsViewController+Referral` can call
    /// `reloadSections` after a successful friend-code apply (issue #144).
    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    // MARK: - Init

    init(themeService: ThemeService = .shared, alarmDefaults: AlarmDefaults = .shared) {
        self.themeService = themeService
        self.alarmDefaults = alarmDefaults
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Sections

    /// `internal` so the cross-file `SettingsViewController+Referral`
    /// extension can read `Section.referral` for the `reloadSections`
    /// call (issue #144).
    enum Section: Int, CaseIterable {
        case finance            // Default price + snooze duration
        case soundNotifications // Volume → picker · Critical Alerts · vibration
        case rules              // Progressive price default
        case referral           // My code (copyable) + friend's code input + caption
        case other              // Privacy · Terms · Contact · Theme segment
        case diagnostics        // Corrupt-data recovery row — hidden unless a repo load failed (#102)
    }

    /// Whether the corrupt-data recovery section should be visible. Surfaced
    /// only when a repository is locked after a failed load (`lastLoadFailed`),
    /// so the normal Settings screen never shows the destructive escape hatch
    /// (#102). Factored out as a pure predicate for unit testing.
    static func shouldShowRecovery(
        alarmFailed: Bool,
        transactionFailed: Bool
    ) -> Bool {
        alarmFailed || transactionFailed
    }

    /// Live recovery visibility, reading the shared repositories.
    var isRecoveryVisible: Bool {
        Self.shouldShowRecovery(
            alarmFailed: AlarmRepository.shared.lastLoadFailed,
            transactionFailed: TransactionRepository.shared.lastLoadFailed
        )
    }

    /// Row layout inside `.finance`.
    enum FinanceRow: Int, CaseIterable {
        case defaultPrice    // "Цена откладывания по умолчанию · 50 ₽"
        case snoozeDuration  // "Длительность откладывания · 9 мин"
    }

    /// Row layout inside `.soundNotifications`.
    enum SoundRow: Int, CaseIterable {
        case volume          // "Громкость · 80%" → VolumePickerViewController
        case criticalAlerts  // disabled switch + "Недоступно" hint
        case vibration       // switch (global default)
    }

    /// Row layout inside `.other`.
    enum OtherRow: Int, CaseIterable {
        case privacy
        case terms
        case contact
        case theme           // SPSegmented system / light / dark
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
        // Settings is a child screen pushed from the gear icon on
        // AlarmsList/Wallet (#237) — inline title keeps the standard back
        // arrow visible and avoids flipping the shared nav bar into
        // large-title mode for the parent screen.
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = AppColors.bg0
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-read defaults (volume may have changed in the pushed picker).
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(tableView)
        // The table covers the whole view: without these it painted
        // `systemGroupedBackground` over `bg0`, and a heavier divider (#496).
        tableView.backgroundColor = AppColors.bg0
        tableView.separatorColor = AppColors.stroke1
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SettingsIconRowCell.self, forCellReuseIdentifier: SettingsIconRowCell.reuseID)
        tableView.register(ThemeSegmentCell.self, forCellReuseIdentifier: ThemeSegmentCell.reuseID)
        tableView.register(ReferralMyCodeCell.self, forCellReuseIdentifier: ReferralMyCodeCell.reuseID)
        tableView.register(
            ReferralFriendInputCell.self,
            forCellReuseIdentifier: ReferralFriendInputCell.reuseID
        )
        tableView.register(ReferralCaptionCell.self, forCellReuseIdentifier: ReferralCaptionCell.reuseID)

        tableView.tableFooterView = makeVersionFooter()

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Theme

    /// Map stored preference to segment index: 0=system, 1=light, 2=dark.
    var themeSegmentIndex: Int {
        switch themeService.current {
        case .system: return 0
        case .light: return 1
        case .dark: return 2
        }
    }

    func handleThemeSegmentChange(_ index: Int) {
        let theme: ThemeService.Theme
        switch index {
        case 1: theme = .light
        case 2: theme = .dark
        default: theme = .system
        }
        themeService.setTheme(theme)
        // Theme flips overrideUserInterfaceStyle live, but already-displayed rows
        // baked their mode-specific shadow + (light-only) ambient layer in
        // willDisplay. Reload so willDisplay re-runs styleAsCardRow for visible rows.
        // Still needed after #496: CardRowBackgroundView self-heals on a trait
        // change, cell *content* layers (SPSegmented, SPInput) don't.
        tableView.reloadData()
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
        case .finance:            return FinanceRow.allCases.count
        case .soundNotifications: return SoundRow.allCases.count
        case .rules:              return 1 // Прогрессивная цена
        case .referral:           return ReferralRow.allCases.count
        case .other:              return OtherRow.allCases.count
        case .diagnostics:        return isRecoveryVisible ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .finance:            return "ФИНАНСЫ"
        case .soundNotifications: return "ЗВУК И УВЕДОМЛЕНИЯ"
        case .rules:              return "ПРАВИЛА"
        case .referral:           return "ПРИГЛАСИТЬ ДРУГА"
        case .other:              return "ПРОЧЕЕ"
        // No header when the recovery row is hidden, so the empty section
        // collapses entirely rather than leaving a stray caps title.
        case .diagnostics:        return isRecoveryVisible ? "ВОССТАНОВЛЕНИЕ" : nil
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
        case .finance:            return makeFinanceCell(at: indexPath)
        case .soundNotifications: return makeSoundCell(at: indexPath)
        case .rules:              return makeRulesCell(at: indexPath)
        case .referral:           return makeReferralCell(at: indexPath)
        case .other:              return makeOtherCell(tableView, at: indexPath)
        case .diagnostics:        return makeRecoveryCell(at: indexPath)
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 52 }
        switch section {
        case .other where OtherRow(rawValue: indexPath.row) == .theme:
            // Two-storey cell — glyph + «Тема» title, then a 36pt SPSegmented
            // below (~90pt total). A fixed 56pt clipped the title and squashed
            // the segment; self-size instead (#314).
            return UITableView.automaticDimension
        case .rules:
            // «Прогрессивная цена» carries a wrapping subtitle — self-size so it
            // isn't truncated ("...") on narrow screens (#313).
            return UITableView.automaticDimension
        case .referral:
            return referralRowHeight(row: indexPath.row)
        case .soundNotifications where SoundRow(rawValue: indexPath.row) == .criticalAlerts:
            // Two-line subtitle hint ("Недоступно — нужно одобрение Apple").
            return UITableView.automaticDimension
        case .diagnostics:
            // Title + subtitle ("Хранилище повреждено и заблокировано") — let it
            // self-size so the hint isn't clipped on narrow screens (#102).
            return UITableView.automaticDimension
        default:
            return 52
        }
    }

    /// Row heights inside `.referral`, split off to keep `heightForRowAt` under
    /// SwiftLint's cyclomatic-complexity cap. Friend-input row hosts an SPInput
    /// (52pt field + label + hint); the caption row wraps to two lines on small
    /// screens — let self-sizing handle both rather than guessing.
    private func referralRowHeight(row: Int) -> CGFloat {
        switch ReferralRow(rawValue: row) {
        case .myCode:      return 52
        case .friendInput: return UITableView.automaticDimension
        case .caption:     return UITableView.automaticDimension
        case .none:        return 52
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // `automaticDimension` paths above need an estimate or the table
        // collapses on first layout pass. The two-storey theme row (~90pt) gets
        // its own estimate so it doesn't jump on first display; the rest match
        // the 52pt row rhythm.
        if Section(rawValue: indexPath.section) == .other,
           OtherRow(rawValue: indexPath.row) == .theme {
            return 90
        }
        return 52
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
        case .finance:
            handleFinanceTap(row: indexPath.row)

        case .soundNotifications:
            if SoundRow(rawValue: indexPath.row) == .volume {
                pushVolumePicker()
            }

        case .rules:
            break

        case .referral:
            // Only the "Ваш код" row has a tap behaviour — the input row owns
            // its own controls (SPInput / SPButton) and the caption row is
            // non-interactive.
            if ReferralRow(rawValue: indexPath.row) == .myCode {
                copyMyCodeToPasteboard()
            }

        case .other:
            handleOtherTap(row: indexPath.row)

        case .diagnostics:
            presentRecoveryConfirmation()
        }
    }

    /// `.finance` row taps split off so `didSelectRowAt` stays under SwiftLint's
    /// cyclomatic-complexity cap (same reason as `handleOtherTap`).
    private func handleFinanceTap(row: Int) {
        switch FinanceRow(rawValue: row) {
        case .defaultPrice:   presentDefaultPricePicker()
        case .snoozeDuration: presentSnoozeDurationPicker()
        case .none:           break
        }
    }

    /// `.other` row taps split off so `didSelectRowAt` stays under SwiftLint's
    /// cyclomatic-complexity cap (the nested switch otherwise pushes it over).
    private func handleOtherTap(row: Int) {
        switch OtherRow(rawValue: row) {
        case .privacy:
            pushLegal(title: "Политика конфиденциальности")
        case .terms:
            pushLegal(title: "Пользовательское соглашение")
        case .contact:
            openMailto()
        case .theme, .none:
            break
        }
    }

    private func pushLegal(title: String) {
        navigationController?.pushViewController(LegalViewController(title: title), animated: true)
    }

    private func openMailto() {
        guard let url = URL(string: "mailto:\(AppConstants.supportEmail)") else { return }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            // No Mail client configured (common — many users live in Gmail/
            // Outlook apps). Don't strand them on a dead «Связаться» tap (#316):
            // copy the address and tell them so support is still reachable.
            UIPasteboard.general.string = AppConstants.supportEmail
            let alert = UIAlertController(
                title: "Почта не настроена",
                message: "Адрес поддержки \(AppConstants.supportEmail) скопирован в буфер обмена.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Ок", style: .default))
            self?.present(alert, animated: true)
        }
    }
}
