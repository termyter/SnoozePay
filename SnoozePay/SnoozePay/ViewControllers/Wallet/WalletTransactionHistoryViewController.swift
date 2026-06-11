import UIKit

/// Transaction history screen — V3 design `TxHistory` in
/// `docs/design/v2-handoff/components/SPMore3.jsx` (artboards 21/21a/21b,
/// issue #234).
///
/// Top-down: centered period chip (current month by default; tap opens
/// `PeriodPickerSheetViewController` for single-month or month-range
/// selection) → summary card with Списано / Пополнения / Откладываний
/// computed over the visible list (bonuses excluded from Пополнения) →
/// day-grouped transaction list filtered to the selected period. Headers
/// read "Сегодня" / "Вчера" / "12 января". The whole page scrolls as one
/// surface — no nested scrolling.
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
    private var period: TxHistoryPeriod = .currentMonth()

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
        let visible = period.filter(all)
        groups = Self.group(transactions: visible)

        let chipRow = makePeriodChipRow()
        stack.addArrangedSubview(chipRow)
        stack.setCustomSpacing(AppSpacing.sp4, after: chipRow)
        stack.addArrangedSubview(makeSummaryCard(summary: TxHistorySummary.compute(from: visible)))

        if groups.isEmpty {
            stack.addArrangedSubview(makeEmptyCard(hasAnyTransactions: !all.isEmpty))
            return
        }

        for group in groups {
            let header = makeGroupHeader(text: group.title)
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(AppSpacing.sp2, after: header)
            stack.addArrangedSubview(makeCard(for: group.entries))
        }
    }

    // MARK: - Period chip (artboard 21)

    private func makePeriodChipRow() -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(
            period.chipCaption,
            attributes: AttributeContainer([
                .font: AppFonts.sans(.semibold, 15),
                .foregroundColor: AppColors.fg1
            ])
        )
        configuration.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = AppSpacing.sp2
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: AppSpacing.sp4, bottom: 10, trailing: AppSpacing.sp3
        )
        configuration.baseForegroundColor = AppColors.fg1

        let chip = UIButton(configuration: configuration)
        chip.backgroundColor = AppColors.whiteOverlay06
        chip.layer.cornerRadius = AppRadius.lg
        chip.layer.masksToBounds = true
        chip.accessibilityLabel = "Период: \(period.chipCaption)"
        chip.addTarget(self, action: #selector(periodChipTapped), for: .touchUpInside)
        chip.translatesAutoresizingMaskIntoConstraints = false

        // Centered inside a full-width row so the stack keeps its margins.
        let row = UIView()
        row.addSubview(chip)
        NSLayoutConstraint.activate([
            chip.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            chip.topAnchor.constraint(equalTo: row.topAnchor),
            chip.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        return row
    }

    @objc private func periodChipTapped() {
        let all = TransactionRepository.shared.fetchAll()
        let currentYear = YearMonth(date: Date()).year
        let earliestYear = all.map { YearMonth(date: $0.createdAt).year }.min() ?? currentYear
        let years = Array(min(earliestYear, currentYear)...currentYear)
        let sheet = PeriodPickerSheetViewController(selected: period, years: years) { [weak self] picked in
            guard let self else { return }
            self.period = picked ?? .currentMonth()
            self.reload()
        }
        present(sheet, animated: true)
    }

    // MARK: - Summary card (artboard 21)

    private func makeSummaryCard(summary: TxHistorySummary) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)

        let caption = UILabel()
        caption.attributedText = NSAttributedString(
            string: "За \(period.summaryCaption)".uppercased(with: Locale(identifier: "ru_RU")),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )

        let spent = makeSummaryColumn(
            title: "Списано",
            value: MoneyFormatter.attributed(
                summary.spent, digitsFont: AppTypography.moneyMd, prefix: "−", color: AppColors.pain400
            ),
            alignment: .left
        )
        let topups = makeSummaryColumn(
            title: "Пополнения",
            value: MoneyFormatter.attributed(
                summary.topups, digitsFont: AppTypography.moneyMd, prefix: "+", color: AppColors.money400
            ),
            alignment: .left
        )
        let snoozes = makeSummaryColumn(
            title: "Откладываний",
            value: NSAttributedString(
                string: "\(summary.snoozeCount)",
                attributes: [.font: AppTypography.moneyMd, .foregroundColor: AppColors.fg1]
            ),
            alignment: .right
        )

        let columns = UIStackView(arrangedSubviews: [spent, topups, snoozes])
        columns.axis = .horizontal
        columns.distribution = .equalSpacing
        columns.alignment = .lastBaseline

        let content = UIStackView(arrangedSubviews: [caption, columns])
        content.axis = .vertical
        content.spacing = AppSpacing.sp2
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])
        return card
    }

    private func makeSummaryColumn(
        title: String,
        value: NSAttributedString,
        alignment: NSTextAlignment
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AppTypography.meta
        titleLabel.textColor = AppColors.fg3
        titleLabel.textAlignment = alignment

        let valueLabel = UILabel()
        valueLabel.attributedText = value
        valueLabel.textAlignment = alignment

        let column = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        column.axis = .vertical
        column.spacing = AppSpacing.sp1
        column.alignment = alignment == .right ? .trailing : .leading
        return column
    }

    private func makeEmptyCard(hasAnyTransactions: Bool = false) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp6, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = hasAnyTransactions
            ? "За выбранный период операций нет."
            : "Здесь появятся пополнения, списания и бонусы."
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
            return "Пополнение баланса"
        case .charge:
            return "Поспать ещё"
        case .promotion:
            // `.promotion` is currently minted only by the referral 7-day
            // hold reward (`ReferralService`), hence the specific copy
            // (issue #234 item 4 — "Возврат" → "Бонус").
            return "Бонус: продержались 7 дней"
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
            glyph = "checkmark"
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
            label.attributedText = MoneyFormatter.attributed(
                Decimal(absAmount), digitsFont: AppTypography.moneySm, prefix: "+"
            )
            label.textColor = AppColors.money400
        case .charge:
            label.attributedText = MoneyFormatter.attributed(
                Decimal(absAmount), digitsFont: AppTypography.moneySm, prefix: "−"
            )
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
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        // "12 января" — full genitive month, sentence case (artboard 21b).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}
