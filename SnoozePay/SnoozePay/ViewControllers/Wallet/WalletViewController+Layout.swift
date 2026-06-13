import UIKit

/// Layout helpers extracted from `WalletViewController` so the VC file
/// stays under the 400-line lint cap. These builders return preconfigured
/// views; the VC wires them into its scroll-view content stack.
extension WalletViewController {

    /// Page-title header: h1 «Кошелёк» + small money "Пополнить" pill +
    /// 1pt bottom hairline. Mirrors the `SPAlarmsListHeader` title-row
    /// recipe so both tabs read identically.
    func makePageHeader(target: Any, action: Selector) -> UIView {
        let header = UIView()
        header.backgroundColor = AppColors.bg0

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.attributedText = NSAttributedString(
            string: "Кошелёк",
            attributes: [
                .font: AppTypography.h1,
                .kern: -32 * 0.01,  // matches `letterSpacing: -.02em`
                .foregroundColor: AppColors.fg1
            ]
        )

        let topUpButton = SPButton(
            title: "Пополнить",
            variant: .money,
            size: .sm,
            icon: UIImage(systemName: "plus")
        )
        topUpButton.translatesAutoresizingMaskIntoConstraints = false
        topUpButton.addTarget(target, action: action, for: .touchUpInside)

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = AppColors.whiteOverlay06

        header.addSubview(title)
        header.addSubview(topUpButton)
        header.addSubview(hairline)

        let inset = AppSpacing.screenInset
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: AppSpacing.sp2),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: inset),
            title.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -AppSpacing.sp4),
            title.trailingAnchor.constraint(
                lessThanOrEqualTo: topUpButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            topUpButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            topUpButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -inset),

            hairline.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1)
        ])
        return header
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

    /// Caps "ИСТОРИЯ ОПЕРАЦИЙ" + trailing "Все операции →" link above the
    /// transaction-preview card.
    func makeTxPreviewHeader(target: Any, action: Selector) -> UIView {
        let title = UILabel()
        title.attributedText = NSAttributedString(
            string: "ИСТОРИЯ ОПЕРАЦИЙ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg2
            ]
        )

        let link = UIButton(type: .system)
        link.setTitle("Все операции →", for: .normal)
        link.titleLabel?.font = AppTypography.buttonSm
        link.setTitleColor(AppColors.money400, for: .normal)
        link.addTarget(target, action: action, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, link])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.distribution = .equalSpacing
        return stack
    }

    /// Card with up to three `SPRow`s built from preview items, or an
    /// empty-state caption when the ledger has no entries yet.
    func makeTxPreviewCard(items: [WalletTransactionPreviewItem]) -> UIView {
        guard !items.isEmpty else { return makeTxPreviewEmptyCard() }

        let card = SPCard(tone: .surface, padding: AppSpacing.sp1, cornerRadius: AppRadius.md)
        let container = UIStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        card.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor)
        ])
        for (index, item) in items.enumerated() {
            let row = SPRow(
                title: item.title,
                subtitle: item.timestampText,
                leading: makeTxIcon(systemName: item.iconSystemName, isDebit: item.isDebit),
                trailing: makeTxAmountLabel(text: item.amountText, isDebit: item.isDebit),
                divider: index < items.count - 1
            )
            container.addArrangedSubview(row)
        }
        return card
    }

    private func makeTxPreviewEmptyCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.md)
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.body
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Здесь появятся пополнения, списания и бонусы."
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor)
        ])
        return card
    }

    /// 36×36 rounded icon tile — red flame tint for charges, green tint
    /// for credits. Matches `WalletTransactionHistoryViewController` rows.
    private func makeTxIcon(systemName: String, isDebit: Bool) -> UIView {
        let tint = isDebit ? AppColors.pain400 : AppColors.money400
        let tile = UIView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.backgroundColor = tint.withAlphaComponent(0.14)
        tile.layer.cornerRadius = AppRadius.sm
        tile.layer.masksToBounds = true

        let imageView = UIImageView(image: UIImage(systemName: systemName))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = tint
        imageView.contentMode = .scaleAspectFit
        tile.addSubview(imageView)

        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 36),
            tile.heightAnchor.constraint(equalToConstant: 36),
            imageView.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18)
        ])
        return tile
    }

    private func makeTxAmountLabel(text: String, isDebit: Bool) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // Row sums use money-md (700 20px mono) per design — 14pt moneySm read
        // as a secondary caption (#321; SPScreensV2.jsx:543, SPMore3.jsx:178).
        label.font = AppTypography.moneyMd
        label.textColor = isDebit ? AppColors.pain400 : AppColors.money400
        label.text = text
        return label
    }

    /// Footer caption "Покупка не возвращается · списывается только при
    /// откладывании" — one-way stake framing per screen 19 canon (#322).
    /// The word «штрафы» is dropped here too for a unified soft tone (#278).
    func makeFooterCaption() -> UILabel {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg4
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Покупка не возвращается · списывается только при откладывании"
        return label
    }
}
