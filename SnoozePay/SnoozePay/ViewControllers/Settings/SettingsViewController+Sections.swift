import UIKit

// MARK: - Section + cell builders
//
// Extracted from `SettingsViewController.swift` (#182) so the host file stays
// under SwiftLint's `file_length` cap. Rewritten in #203 to dequeue reusable
// `SettingsIconRowCell` instances instead of building nil-reuseIdentifier
// cells from scratch on every `cellForRowAt:` (which UITableView can never
// recycle — every `reloadData` accumulated a fresh cell hierarchy).

extension SettingsViewController {

    // MARK: Account section

    func makeTransactionHistoryRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "list.bullet.rectangle",
            iconColor: AppColors.info500,
            title: "История транзакций",
            accessory: .disclosureIndicator
        )
        return cell
    }

    func makeBalanceRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        // The amount is read fresh on every dequeue, so the row is always
        // current when it (re-)enters the viewport; live updates while the
        // row is visible arrive via the balance observer's `reloadRows`.
        cell.configure(
            systemName: "rublesign.circle",
            iconColor: AppColors.money500,
            title: "Баланс",
            trailingText: Decimal(BalanceService.shared.balance).formattedRubles(),
            trailingColor: AppColors.money500,
            accessory: .none,
            selectionStyle: .none
        )
        return cell
    }

    // MARK: Finance section

    /// Display-only "Цена откладывания по умолчанию · 50 ₽" row (#237).
    /// The value mirrors `AlarmsListViewModel.defaultPenaltyAmount` (the
    /// `Alarm.init` default applied to new alarms); per-alarm price editing
    /// lives on the Create/Edit screen, so this row carries no navigation.
    /// "Способы оплаты" is intentionally absent — PaymentMethods is V2.
    func makeDefaultPriceRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "rublesign.circle",
            iconColor: AppColors.warn500,
            title: "Цена откладывания по умолчанию",
            trailingText: Decimal(AlarmsListViewModel.defaultPenaltyAmount).formattedRubles(),
            trailingColor: AppColors.warn500,
            accessory: .none,
            selectionStyle: .none
        )
        return cell
    }

    // MARK: Info section

    func makeInfoRow(at indexPath: IndexPath) -> UITableViewCell {
        let title = indexPath.row == 0 ? "Политика конфиденциальности" : "Пользовательское соглашение"
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "doc.text",
            iconColor: UIColor.systemGray,
            title: title,
            accessory: .disclosureIndicator
        )
        return cell
    }

    // MARK: Contact section

    func makeContactRow(at indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueIconRowCell(at: indexPath)
        cell.configure(
            systemName: "envelope",
            iconColor: AppColors.warn500,
            title: "Связаться с нами",
            subtitle: "support@alarmcash.app",
            accessory: .disclosureIndicator
        )
        return cell
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
}

// MARK: - Section header view

/// Caps-styled section header used by both `SettingsViewController` and the
/// nested `TransactionHistoryViewController`. Mirrors `CreateAlarmViewController`'s
/// shared `SectionHeaderView` (#177); kept as a private file-scoped duplicate
/// inside the Settings stack per #182's "don't touch the private header" note.
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
