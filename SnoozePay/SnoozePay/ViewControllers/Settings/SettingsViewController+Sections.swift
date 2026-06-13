import UIKit

// MARK: - Section + cell builders
//
// V3 (#283): builders for Финансы / Звук и уведомления / Правила / Прочее.
// Each row dequeues a reusable `SettingsIconRowCell` (or `ThemeSegmentCell`
// for the theme segment) — never builds a nil-identifier cell, which
// UITableView can't recycle (#203).

extension SettingsViewController {

    // MARK: Финансы

    func makeFinanceCell(at indexPath: IndexPath) -> UITableViewCell {
        switch FinanceRow(rawValue: indexPath.row) {
        case .defaultPrice:   return makeDefaultPriceRow(at: indexPath)
        case .snoozeDuration: return makeSnoozeDurationRow(at: indexPath)
        case .none:           return UITableViewCell()
        }
    }

    /// Tappable "Цена откладывания по умолчанию · 50 ₽" row (#237/#283/#315).
    /// The value is the global default penalty seeding new alarms
    /// (`AlarmDefaults.penaltyAmount`); tapping opens a price editor and the
    /// chevron signals the affordance, symmetric with the snooze-duration row
    /// (design `SPMore4.jsx:362`). Existing alarms keep their own saved price.
    func makeDefaultPriceRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "rublesign.circle",
            iconColor: AppColors.warn400,
            title: "Цена откладывания по умолчанию",
            trailingText: Decimal(alarmDefaults.penaltyAmount).formattedRubles(),
            trailingColor: AppColors.warn400,
            accessory: .disclosureIndicator,
            selectionStyle: .default
        )
        return cell
    }

    /// "Длительность откладывания · 9 мин" — global default seeding new alarms
    /// (#283). Tap presents a minute picker; existing alarms are untouched.
    func makeSnoozeDurationRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "clock",
            iconColor: AppColors.fg3,
            title: "Длительность откладывания",
            trailingText: "\(alarmDefaults.snoozeMinutes) мин",
            trailingColor: AppColors.fg3,
            accessory: .disclosureIndicator,
            selectionStyle: .default
        )
        return cell
    }

    // MARK: Звук и уведомления

    func makeSoundCell(at indexPath: IndexPath) -> UITableViewCell {
        switch SoundRow(rawValue: indexPath.row) {
        case .volume:         return makeVolumeRow(at: indexPath)
        case .criticalAlerts: return makeCriticalAlertsRow(at: indexPath)
        case .vibration:      return makeVibrationRow(at: indexPath)
        case .none:           return UITableViewCell()
        }
    }

    /// "Громкость · 80%" → `VolumePickerViewController` (#283, resolves the
    /// reachability part of #270). The percentage reflects the global default.
    func makeVolumeRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        let percent = Int((alarmDefaults.volume * 100).rounded())
        cell.configure(
            systemName: "speaker.wave.2",
            iconColor: AppColors.fg3,
            title: "Громкость",
            trailingText: "\(percent)%",
            trailingColor: AppColors.fg3,
            accessory: .disclosureIndicator,
            selectionStyle: .default
        )
        return cell
    }

    /// Critical Alerts row — rendered DISABLED with a hint. The entitlement is
    /// a no-touch / PM concern (Personal team, not granted by Apple), so the
    /// switch is greyed-out and the subtitle explains why (#283).
    func makeCriticalAlertsRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configureSwitch(
            systemName: "bell.badge",
            iconColor: AppColors.fg3,
            title: "Critical Alerts",
            subtitle: "Недоступно — нужно одобрение Apple",
            isOn: false,
            enabled: false,
            onChange: { _ in }
        )
        return cell
    }

    /// Vibration default for new alarms (#283). Toggling writes the global
    /// default; existing alarms keep their own saved value.
    func makeVibrationRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configureSwitch(
            systemName: "iphone.radiowaves.left.and.right",
            iconColor: AppColors.fg3,
            title: "Вибрация",
            isOn: alarmDefaults.vibrationEnabled,
            onChange: { [weak self] isOn in
                self?.alarmDefaults.vibrationEnabled = isOn
            }
        )
        return cell
    }

    // MARK: Правила

    /// Only «Прогрессивная цена» is implemented — it maps to a real per-alarm
    /// field (`Alarm.progressiveScale`) for which a sane global default exists.
    /// «Бонус за серию» / «Защита от скуки» from the design have no backing
    /// rule, so they are intentionally omitted rather than faked (#283).
    func makeRulesCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configureSwitch(
            systemName: "flame",
            iconColor: AppColors.pain400,
            title: "Прогрессивная цена",
            // Design copy (`SPMore4.jsx:381`) — the doubling ramp reads clearer
            // than prose and won't clip (#313).
            subtitle: "50 → 100 → 200 → 400",
            isOn: alarmDefaults.progressiveScale,
            onChange: { [weak self] isOn in
                self?.alarmDefaults.progressiveScale = isOn
            }
        )
        return cell
    }

    // MARK: Прочее

    func makeOtherCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch OtherRow(rawValue: indexPath.row) {
        case .privacy:
            return makeInfoRow(at: indexPath, title: "Политика конфиденциальности")
        case .terms:
            return makeInfoRow(at: indexPath, title: "Пользовательское соглашение")
        case .contact:
            return makeContactRow(at: indexPath)
        case .theme:
            return makeThemeCell(tableView, at: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    func makeInfoRow(at indexPath: IndexPath, title: String) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "doc.text",
            iconColor: AppColors.fg3,
            title: title,
            accessory: .disclosureIndicator
        )
        return cell
    }

    func makeContactRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "envelope",
            iconColor: AppColors.fg3,
            title: "Связаться с нами",
            subtitle: "support@alarmcash.app",
            accessory: .disclosureIndicator
        )
        return cell
    }

    /// Theme segment — kept (PM decision) but restyled with SP tokens via
    /// `ThemeSegmentCell` (SPSegmented), moved under «Прочее» per design (#283).
    private func makeThemeCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
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

    // MARK: - Navigation helpers

    /// Pushes the shared volume picker, seeded with the global default. The
    /// picker auto-saves on every change via `onChange`, so the global default
    /// is updated as the user drags — `viewWillAppear`'s reload refreshes the
    /// "{N}%" trailing text when the picker pops.
    func pushVolumePicker() {
        let picker = VolumePickerViewController(
            volume: alarmDefaults.volume,
            fadeIn: false
        ) { [weak self] volume, _ in
            self?.alarmDefaults.volume = volume
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    /// Lightweight minute picker for the global snooze-duration default.
    /// An action sheet keeps it inline (no extra screen) and stays within the
    /// 1–15 form range.
    func presentSnoozeDurationPicker() {
        let sheet = UIAlertController(
            title: "Длительность откладывания",
            message: "Применяется к новым будильникам",
            preferredStyle: .actionSheet
        )
        for minutes in [3, 5, 9, 10, 15] {
            sheet.addAction(UIAlertAction(title: "\(minutes) мин", style: .default) { [weak self] _ in
                self?.alarmDefaults.snoozeMinutes = minutes
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        // iPad: anchor the popover to the tapped row.
        if let popover = sheet.popoverPresentationController {
            let indexPath = IndexPath(
                row: FinanceRow.snoozeDuration.rawValue,
                section: Section.finance.rawValue
            )
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }

    /// Interim default-price editor (#315). The design ultimately calls for the
    /// free-numeric SnoozePriceCard input (#230); until that lands this mirrors
    /// `presentSnoozeDurationPicker()` with the canonical price chips. Writing
    /// the global default never rewrites existing alarms — only new ones inherit.
    func presentDefaultPricePicker() {
        let sheet = UIAlertController(
            title: "Цена откладывания по умолчанию",
            message: "Применяется к новым будильникам",
            preferredStyle: .actionSheet
        )
        for amount in [20, 50, 100, 200, 500] {
            let title = Decimal(amount).formattedRubles()
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.alarmDefaults.penaltyAmount = Double(amount)
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        // iPad: anchor the popover to the tapped row.
        if let popover = sheet.popoverPresentationController {
            let indexPath = IndexPath(
                row: FinanceRow.defaultPrice.rawValue,
                section: Section.finance.rawValue
            )
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }

    // MARK: - Cell factory helpers

    /// Dequeues the shared icon-row cell, falling back to a plain cell (with
    /// an assertion in debug) if the registration ever drifts out of sync.
    private func dequeueIconRowCell(at indexPath: IndexPath) -> SettingsIconRowCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SettingsIconRowCell.reuseID,
            for: indexPath
        ) as? SettingsIconRowCell else {
            assertionFailure("dequeueReusableCell returned wrong type for \(SettingsIconRowCell.reuseID)")
            return SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        }
        return cell
    }

    // MARK: - Section header builder

    /// Returns the caps-styled header view for the given section title. Kept
    /// as a tiny helper so `viewForHeaderInSection` (in the host file) is a
    /// one-liner and the typography lives next to the rest of the row UI.
    func makeSettingsSectionHeader(text: String) -> UIView {
        SettingsSectionHeaderView(text: text)
    }

    // MARK: - Version footer

    /// "SnoozePay {version} · build {build}" read live from the bundle
    /// (`CFBundleShortVersionString` / `CFBundleVersion`) so a version bump
    /// never needs a code change here (#283).
    func makeVersionFooter() -> UIView {
        let container = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Self.versionFooterString()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.numberOfLines = 1
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppSpacing.lg),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppSpacing.lg),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: AppSpacing.sm),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -AppSpacing.xl)
        ])
        // A `tableFooterView` needs a non-zero frame to lay out; the table
        // re-stretches the width to its own bounds, so the initial width is a
        // placeholder. `.flexibleWidth` keeps the centred label aligned after
        // that stretch.
        container.frame = CGRect(x: 0, y: 0, width: 320, height: 56)
        container.autoresizingMask = [.flexibleWidth]
        return container
    }

    /// Pure string builder so the footer copy is unit-testable without a
    /// table. Falls back to "—" for either component if the bundle key is
    /// missing (it never is for a real build, but keeps the string total).
    static func versionFooterString(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "SnoozePay \(version) · build \(build)"
    }
}

// MARK: - Section header view

/// Caps-styled section header used by `SettingsViewController`. Mirrors
/// `CreateAlarmViewController`'s shared `SectionHeaderView` (#177); kept as a
/// file-scoped duplicate inside the Settings stack per #182's "don't touch the
/// private header" note.
final class SettingsSectionHeaderView: UIView {

    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = .clear
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.lg),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sm)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
