import UIKit

/// Transaction history screen — V2 design `TxHistory` in
/// `docs/design/v2-handoff/components/SPMore3.jsx` (L6-105).
///
/// Lists every recorded `Transaction` grouped by day. Headers read
/// "СЕГОДНЯ" / "ВЧЕРА" / "12 АПР" depending on relative date. Tap-through
/// is not implemented yet — the screen is read-only.
///
/// `Wallet`-prefixed because a legacy `TransactionHistoryViewController`
/// still lives under `Settings/` for the V1 surface; the two will merge
/// once the V1 tab structure is fully retired.
final class WalletTransactionHistoryViewController: UIViewController {

    // MARK: - Data

    private struct Group {
        let title: String
        let entries: [Transaction]
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var groups: [Group] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        title = "История"
        navigationItem.largeTitleDisplayMode = .never
        setupLayout()
        reload()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(transactionsChanged),
            name: BalanceService.balanceChangedNotification,
            object: nil
        )
    }

    @objc private func transactionsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.reload()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp5
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AppSpacing.sp4,
            leading: AppSpacing.screenInset,
            bottom: AppSpacing.sp7,
            trailing: AppSpacing.screenInset
        )
        stack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    // MARK: - Reload

    private func reload() {
        // Wipe previous content but keep `stack` itself.
        for sub in stack.arrangedSubviews {
            stack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let all = TransactionRepository.shared.fetchAll()
        groups = Self.group(transactions: all)

        if groups.isEmpty {
            stack.addArrangedSubview(makeEmptyCard())
            return
        }

        for group in groups {
            stack.addArrangedSubview(makeGroupHeader(text: group.title))
            stack.addArrangedSubview(makeCard(for: group.entries))
        }
    }

    private func makeEmptyCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp6, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "Здесь появятся пополнения, списания и возвраты."
        label.font = AppTypography.body
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        return card
    }

    private func makeGroupHeader(text: String) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        return label
    }

    private func makeCard(for entries: [Transaction]) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp1, cornerRadius: AppRadius.md)
        let container = UIStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 0
        card.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            container.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        for (idx, transaction) in entries.enumerated() {
            let isLast = idx == entries.count - 1
            container.addArrangedSubview(makeRow(for: transaction, divider: !isLast))
        }
        return card
    }

    private func makeRow(for transaction: Transaction, divider: Bool) -> SPRow {
        let title = Self.title(for: transaction)
        let subtitle = Self.timeString(for: transaction.createdAt)
        let leading = Self.makeIcon(for: transaction)
        let trailing = Self.makeAmountLabel(for: transaction)
        return SPRow(
            title: title,
            subtitle: subtitle,
            leading: leading,
            trailing: trailing,
            divider: divider
        )
    }

    // MARK: - Cell content helpers

    private static func title(for transaction: Transaction) -> String {
        switch transaction.type {
        case .topup:
            return "Пополнение Apple Pay"
        case .charge:
            return "Поспать ещё"
        case .promotion:
            return "Промо-зачисление"
        }
    }

    private static func makeIcon(for transaction: Transaction) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let tint: UIColor
        let fill: UIColor
        let glyph: String
        switch transaction.type {
        case .topup:
            tint = AppColors.money400
            fill = AppColors.money400.withAlphaComponent(0.14)
            glyph = "plus"
        case .promotion:
            tint = AppColors.money400
            fill = AppColors.money400.withAlphaComponent(0.14)
            glyph = "gift"
        case .charge:
            tint = AppColors.pain400
            fill = AppColors.pain400.withAlphaComponent(0.14)
            glyph = "flame"
        }
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = fill
        view.layer.cornerRadius = AppRadius.sm
        view.layer.masksToBounds = true
        let imageView = UIImageView(image: UIImage(systemName: glyph))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = tint
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        container.addSubview(view)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 36),
            container.heightAnchor.constraint(equalToConstant: 36),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18)
        ])
        return container
    }

    private static func makeAmountLabel(for transaction: Transaction) -> UILabel {
        let label = UILabel()
        label.font = AppTypography.moneySm
        label.translatesAutoresizingMaskIntoConstraints = false
        let absAmount = Int(abs(transaction.amount))
        switch transaction.type {
        case .topup, .promotion:
            label.text = "+\(absAmount) ₽"
            label.textColor = AppColors.money400
        case .charge:
            label.text = "−\(absAmount) ₽"
            label.textColor = AppColors.pain400
        }
        return label
    }

    private static func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Grouping

    private static func group(transactions: [Transaction]) -> [Group] {
        guard !transactions.isEmpty else { return [] }
        // Repository already returns newest-first sorted.
        let calendar = Calendar.current
        var buckets: [(key: Date, items: [Transaction])] = []
        for transaction in transactions {
            let key = calendar.startOfDay(for: transaction.createdAt)
            if let lastIndex = buckets.indices.last, buckets[lastIndex].key == key {
                buckets[lastIndex].items.append(transaction)
            } else {
                buckets.append((key: key, items: [transaction]))
            }
        }
        return buckets.map { bucket in
            Group(title: header(for: bucket.key), entries: bucket.items)
        }
    }

    private static func header(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "СЕГОДНЯ" }
        if calendar.isDateInYesterday(date) { return "ВЧЕРА" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).uppercased(with: Locale(identifier: "ru_RU"))
    }
}
