import UIKit

// MARK: - Section + cell builders
//
// Extracted from `SettingsViewController.swift` (#182) so the host file stays
// under SwiftLint's `file_length` cap. Each helper owns its row's UIKit
// composition; behaviour is verbatim — only the physical location moved.

extension SettingsViewController {

    // MARK: Account section

    func makeTransactionHistoryRow() -> UITableViewCell {
        makeIconRow(
            systemName: "list.bullet.rectangle",
            iconColor: AppColors.info500,
            title: "История транзакций",
            accessory: .disclosureIndicator
        )
    }

    func makeBalanceRow() -> UITableViewCell {
        let cell = makeIconRow(
            systemName: "dollarsign.circle",
            iconColor: AppColors.money500,
            title: "Баланс",
            accessory: .none
        )

        let balanceAmount = UILabel()
        balanceAmount.text = "₽\(Int(BalanceService.shared.balance))"
        balanceAmount.font = AppTypography.moneyMd
        balanceAmount.textColor = AppColors.money500
        balanceAmount.translatesAutoresizingMaskIntoConstraints = false
        balanceAmount.setContentHuggingPriority(.required, for: .horizontal)
        cell.contentView.addSubview(balanceAmount)

        NSLayoutConstraint.activate([
            balanceAmount.trailingAnchor.constraint(
                equalTo: cell.contentView.trailingAnchor,
                constant: -AppSpacing.lg
            ),
            balanceAmount.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])

        // Track the latest label instance so the balance observer can
        // refresh it. When the cell is recycled the weak ref nils out
        // automatically, so the observer becomes a no-op until the row
        // is rebuilt — at which point this assignment captures the new label.
        self.balanceAmountLabel = balanceAmount

        cell.selectionStyle = .none
        return cell
    }

    // MARK: Info section

    func makeInfoRow(at indexPath: IndexPath) -> UITableViewCell {
        let title = indexPath.row == 0 ? "Политика конфиденциальности" : "Пользовательское соглашение"
        return makeIconRow(
            systemName: "doc.text",
            iconColor: UIColor.systemGray,
            title: title,
            accessory: .disclosureIndicator
        )
    }

    // MARK: Contact section

    func makeContactRow() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .secondarySystemBackground

        let icon = makeSettingsIcon(systemName: "envelope", backgroundColor: AppColors.warn500)
        let titleLabel = UILabel()
        titleLabel.text = "Связаться с нами"
        titleLabel.font = AppTypography.bodyLg
        titleLabel.textColor = AppColors.fg1

        let detailLabel = UILabel()
        detailLabel.text = "support@alarmcash.app"
        detailLabel.font = AppTypography.meta
        detailLabel.textColor = AppColors.fg3

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [icon, textStack])
        stack.axis = .horizontal
        stack.spacing = AppSpacing.md
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: cell.contentView.leadingAnchor,
                constant: AppSpacing.lg
            ),
            stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: cell.contentView.trailingAnchor,
                constant: -AppSpacing.lg
            )
        ])

        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - Cell factory helpers

    func makeIconRow(
        systemName: String,
        iconColor: UIColor,
        title: String,
        accessory: UITableViewCell.AccessoryType
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .secondarySystemBackground

        let icon = makeSettingsIcon(systemName: systemName, backgroundColor: iconColor)
        let label = UILabel()
        label.text = title
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = AppSpacing.md
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: AppSpacing.lg),
            stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])

        cell.accessoryType = accessory
        return cell
    }

    /// Creates a rounded-rect icon with an SF Symbol, similar to iOS Settings style.
    func makeSettingsIcon(systemName: String, backgroundColor: UIColor) -> UIView {
        let size: CGFloat = 30
        let container = UIView()
        container.backgroundColor = backgroundColor
        container.layer.cornerRadius = 7
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView()
        imageView.image = UIImage(systemName: systemName)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
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
