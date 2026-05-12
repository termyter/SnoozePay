import UIKit

/// Layout helpers extracted from `WalletViewController` so the VC file
/// stays under the 400-line lint cap. These builders return preconfigured
/// views; the VC wires them into its scroll-view content stack.
extension WalletViewController {

    /// Build the caps + meta row above the preset grid.
    func makePresetsHeader() -> UIView {
        let title = UILabel()
        title.attributedText = NSAttributedString(
            string: "ПОЛОЖИТЬ ПОД РАСПИСКУ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg2
            ]
        )
        title.translatesAutoresizingMaskIntoConstraints = false

        let trailing = UILabel()
        trailing.attributedText = NSAttributedString(
            string: "Apple Pay",
            attributes: [
                .font: AppTypography.meta,
                .foregroundColor: AppColors.fg3
            ]
        )
        trailing.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, trailing])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.distribution = .equalSpacing
        return stack
    }

    /// Build the 3-column × 2-row preset grid. The view controller stores
    /// the resulting `SPAmountPreset` instances in `presetButtons` for
    /// selection-state updates.
    func makePresetGrid(
        targets: inout [SPAmountPreset],
        action: @escaping (Int) -> Void
    ) -> UIView {
        let presets = WalletPresets.presets
        var rows: [UIStackView] = []
        var allButtons: [SPAmountPreset] = []
        let columnsPerRow = 3
        for rowStart in stride(from: 0, to: presets.count, by: columnsPerRow) {
            let rowEnd = min(rowStart + columnsPerRow, presets.count)
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            for index in rowStart..<rowEnd {
                let preset = presets[index]
                let button = SPAmountPreset(
                    value: preset.value,
                    label: preset.label,
                    selected: preset.isDefault,
                    popular: preset.popular,
                    onTap: { action(index) }
                )
                allButtons.append(button)
                row.addArrangedSubview(button)
            }
            rows.append(row)
        }
        targets.append(contentsOf: allButtons)
        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.spacing = 10
        return column
    }

    /// Header for the weekly chart section.
    func makeWeeklyChartHeader() -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "ПОСЛЕДНИЕ 7 ДНЕЙ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg2
            ]
        )
        return label
    }

    /// Inline "Все операции →" link rendered below the preset grid.
    func makeTransactionsLink(target: Any, action: Selector) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Все операции →", for: .normal)
        button.titleLabel?.font = AppTypography.body
        button.tintColor = AppColors.fg2
        button.contentHorizontalAlignment = .leading
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }

    /// Tail-section card linking to the payment-methods screen.
    func makePaymentMethodsRow(target: NSObject, action: Selector) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp1, cornerRadius: AppRadius.md)
        let icon = UIImageView(image: UIImage(systemName: "creditcard"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AppColors.fg2
        icon.contentMode = .scaleAspectFit
        let leadingHolder = UIView()
        leadingHolder.translatesAutoresizingMaskIntoConstraints = false
        leadingHolder.addSubview(icon)
        NSLayoutConstraint.activate([
            leadingHolder.widthAnchor.constraint(equalToConstant: 24),
            leadingHolder.heightAnchor.constraint(equalToConstant: 24),
            icon.centerXAnchor.constraint(equalTo: leadingHolder.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: leadingHolder.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20)
        ])
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = AppColors.fg3
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
        let row = SPRow(
            title: "Способы оплаты",
            subtitle: "Apple Pay по умолчанию",
            leading: leadingHolder,
            trailing: chevron,
            divider: false,
            onTap: { [weak target] in
                guard let target = target else { return }
                _ = target.perform(action)
            }
        )
        let stack = UIStackView(arrangedSubviews: [row])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor)
        ])
        return card
    }

    /// Footer caption "Покупка не возвращается · штрафы списываются с баланса".
    func makeFooterCaption() -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg4
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Покупка не возвращается · штрафы списываются с баланса"
        return label
    }
}
