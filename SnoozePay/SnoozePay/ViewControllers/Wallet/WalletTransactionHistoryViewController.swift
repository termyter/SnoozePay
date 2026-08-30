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
/// read «Сегодня» / «Вчера» / «12 января». The whole page scrolls as one
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
    private var typeFilter: TxHistoryTypeFilter = .all

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg0
        title = Localized.text("wallet.history.title")
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

        // Checked read so a corrupt ledger renders a distinct error banner
        // instead of the friendly «нет операций» empty-state, which would let
        // the user assume their history was wiped (#419) — matches the honest
        // load-failure treatment in `StatisticsViewModel`.
        let load = WalletLedgerLoad.load(from: TransactionRepository.shared)
        guard !load.didFail else {
            populateLoadErrorState()
            return
        }
        let all = load.transactions
        // Period narrows by date; the summary card aggregates this whole
        // period set so its totals stay stable as the user toggles chips.
        let periodVisible = period.filter(all)
        // The list then composes the type chip on top of the period set.
        let listVisible = typeFilter.filter(periodVisible)
        groups = Self.group(transactions: listVisible)

        let chipRow = makePeriodChipRow()
        stack.addArrangedSubview(chipRow)
        stack.setCustomSpacing(AppSpacing.sp4, after: chipRow)
        // Pairing of charge↔refund is resolved against the FULL ledger, not the
        // period slice — the two rows can straddle a month boundary (#358).
        stack.addArrangedSubview(makeSummaryCard(
            summary: TxHistorySummary.compute(from: periodVisible, ledger: all)
        ))

        // Soft notice (NOT the corrupt-ledger banner): rows this build can't
        // classify are skipped by every aggregate, so the totals above are
        // understated relative to the real balance. Say so instead of letting
        // the numbers quietly lie (#358).
        if all.contains(where: { $0.type.isUnrecognized }) {
            let notice = makeUnrecognizedRowsNotice()
            stack.setCustomSpacing(AppSpacing.sp4, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 1])
            stack.addArrangedSubview(notice)
        }

        let filterRow = makeTypeFilterRow()
        stack.setCustomSpacing(AppSpacing.sp4, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 1])
        stack.addArrangedSubview(filterRow)
        stack.setCustomSpacing(AppSpacing.sp3, after: filterRow)

        if groups.isEmpty {
            stack.addArrangedSubview(makeEmptyCard(
                hasAnyTransactions: !all.isEmpty,
                periodHasTransactions: !periodVisible.isEmpty
            ))
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
        // Was a magic `10` top/bottom, which put the chip at 40pt — under the
        // 44pt HIG minimum for a tap target. `sp3` is the token on the 4px
        // grid nearest that value and lands the chip on exactly 44pt.
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sp3, leading: AppSpacing.sp4,
            bottom: AppSpacing.sp3, trailing: AppSpacing.sp3
        )
        configuration.baseForegroundColor = AppColors.fg1

        let chip = UIButton(configuration: configuration)
        chip.backgroundColor = AppColors.whiteOverlay06
        chip.layer.cornerRadius = AppRadius.lg
        chip.layer.masksToBounds = true
        chip.accessibilityLabel = Localized.format("wallet.history.period.accessibility", period.chipCaption)
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
        // Tolerate a decode failure here (the year range just narrows to the
        // current year) — the load-error banner from `reload()` already tells
        // the user the ledger is unreadable (#419).
        let all = WalletLedgerLoad.load(from: TransactionRepository.shared).transactions
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
            string: summaryCapsCaption(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )

        let spent = makeSummaryColumn(
            title: Localized.text("wallet.history.summary.spent"),
            value: MoneyFormatter.attributed(
                summary.spent, digitsFont: AppTypography.moneyMd, prefix: "−",
                color: WalletAmountTint.ink(for: .outgoing)
            ),
            alignment: .left
        )
        let topups = makeSummaryColumn(
            title: Localized.text("wallet.history.summary.topups"),
            value: MoneyFormatter.attributed(
                summary.topups, digitsFont: AppTypography.moneyMd, prefix: "+",
                color: WalletAmountTint.ink(for: .incoming)
            ),
            alignment: .left
        )
        let snoozes = makeSummaryColumn(
            title: Localized.text("wallet.history.summary.snoozes"),
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
            // Same inset as the wallet preview card, and for the same reason
            // — see `WalletViewController+Layout.makeTxPreviewCard`, where the
            // measurement and the canon divergence are written down. The two
            // screens render the same rows, so they have to agree or «Все
            // операции» visibly shifts the list sideways (#677).
            container.leadingAnchor.constraint(
                equalTo: card.leadingAnchor, constant: AppSpacing.sp5
            ),
            container.trailingAnchor.constraint(
                equalTo: card.trailingAnchor, constant: -AppSpacing.sp5
            ),
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
        // Charge rows carry the owning alarm's context as the subtitle —
        // «Будни · 07:00» — falling back to the bare time when the alarm was
        // deleted/edited away (issue #282, SPScreensV2.jsx L467).
        let subtitle = Self.subtitle(for: transaction)
        let leading = Self.makeIcon(for: transaction)
        let trailing = Self.makeAmountLabel(for: transaction)
        return SPRow(
            title: title,
            subtitle: subtitle,
            leading: leading,
            trailing: trailing,
            // Two lines, not one: «Возврат за откладывание» needs 210pt of
            // run and the widest supported phone can spare 210pt only at a
            // zero card inset. Measured — see `WalletRowInsetTests` (#677).
            titleLines: 2,
            divider: divider
        )
    }

    // MARK: - Cell content helpers

    static func title(for transaction: Transaction) -> String {
        switch transaction.type {
        case .topup:
            return Localized.text("wallet.tx.topup")
        case .charge:
            return Localized.text("wallet.tx.charge")
        case .promotion:
            // `.promotion` was minted only by the referral bonus
            // (`ReferralService`); since #676 hid that entry point nothing
            // mints it in a release build, so this branch renders history on
            // installs that already have such a row. In DEBUG it is still
            // reached: `UITourLauncher.seedTransactions()` writes one
            // under `-uitour-seed`, which is what puts this row in
            // screen audits. There is no 7-day hold today, so
            // the copy must not claim one (issue #282 — honest, unified copy
            // shared with the wallet preview).
            return Localized.text("wallet.tx.promotion")
        case .refund:
            // Penalty returned because the snooze never armed (issue #358) —
            // same copy as the wallet preview row.
            return Localized.text("wallet.tx.refund")
        case .unknown:
            // Written by a newer build (see `TransactionType.unknown`).
            return Localized.text("wallet.tx.unknown")
        }
    }

    /// Subtitle for a row: charges append the owning alarm's repeat/time
    /// context when resolvable; everything else (and orphaned charges) show
    /// the transaction time only. Static + repository-injectable so the
    /// composition is unit-tested in `subtitle(for:time:lookup:)`.
    static func subtitle(for transaction: Transaction) -> String {
        subtitle(
            for: transaction,
            time: timeString(for: transaction.createdAt),
            // Checked read collapsed with `try?` (#271): the caption is
            // decoration, so an unreadable alarm store degrades to the charge
            // time exactly like a deleted alarm does. `try?` keeps that
            // fallback while routing new code at the checked fetcher.
            lookup: { try? AlarmRepository.shared.fetchChecked(id: $0) }
        )
    }

    static func subtitle(
        for transaction: Transaction,
        time: String,
        calendar: Calendar = .current,
        lookup: (UUID) -> Alarm?
    ) -> String {
        guard transaction.type == .charge else { return time }
        // Prefer the owning alarm's context («Будни · 07:00») — it tells the
        // user *which* alarm this snooze charge came from, which the bare
        // charge time can't. Rows are already grouped under a day header, so
        // the per-row time is redundant once context is available. When the
        // alarm was deleted/edited away the context resolves to nil and we
        // keep the charge time so the row still says *something* (issue #282).
        return TransactionAlarmContext.caption(
            for: transaction.alarmID, calendar: calendar, lookup: lookup
        ) ?? time
    }

    /// SF Symbol for a row's leading tile. Glyph carries the meaning that the
    /// tint only reinforces — the row stays readable with colour removed.
    static func glyphName(for type: TransactionType) -> String {
        switch type {
        case .topup: return "plus"
        // Unified with the wallet preview — gift glyph, not a checkmark
        // (issue #282, single promotion-row rendering).
        case .promotion: return "gift"
        // Money back, but not income — the undo glyph keeps it visually
        // distinct from a real top-up (issue #358).
        case .refund: return "arrow.uturn.backward"
        case .charge: return "flame"
        case .unknown: return "questionmark"
        }
    }

    private static func makeIcon(for transaction: Transaction) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        // Tint + wash come from the shared `WalletAmountTint` so this screen
        // and the wallet preview card can never drift apart in either theme.
        let direction = WalletLedgerDirection(transaction.type)
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = WalletAmountTint.iconWash(for: direction)
        view.layer.cornerRadius = AppRadius.sm
        view.layer.masksToBounds = true
        let imageView = UIImageView(image: UIImage(systemName: glyphName(for: transaction.type)))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = WalletAmountTint.ink(for: direction)
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        container.addSubview(view)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: tileSide),
            container.heightAnchor.constraint(equalToConstant: tileSide),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: glyphSide),
            imageView.heightAnchor.constraint(equalToConstant: glyphSide)
        ])
        return container
    }

    /// 36×36 leading tile with an 18pt glyph — `SPMore3.jsx:83`.
    private static let tileSide: CGFloat = 36
    private static let glyphSide: CGFloat = 18

    static func makeAmountLabel(for transaction: Transaction) -> UILabel {
        let label = UILabel()
        // Row sums use money-md (700 20px mono) per design, not 14pt moneySm
        // (#321; full history SPMore3.jsx:178, role "Row sums" SPDesignSystem.jsx:254).
        label.font = AppTypography.moneyMd
        label.translatesAutoresizingMaskIntoConstraints = false
        let direction = WalletLedgerDirection(transaction.type)
        // The sign — not the colour — is what makes a credit distinguishable
        // from a debit: in light the two tints measure 5.27:1 and 5.22:1 on
        // the card, i.e. the same luminance, so a red-green colour-blind
        // reader has only "+" / "−" to go on. `.unclassified` carries no sign
        // because this build genuinely doesn't know the direction.
        label.attributedText = MoneyFormatter.attributed(
            Decimal(Int(abs(transaction.amount))),
            digitsFont: AppTypography.moneyMd,
            prefix: direction.signPrefix ?? ""
        )
        label.textColor = WalletAmountTint.ink(for: direction)
        return label
    }

    private static func timeString(for date: Date) -> String {
        WallClockFormatter.string(from: date, style: .padded)
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
        if calendar.isDateInToday(date) { return Localized.text("wallet.history.day.today") }
        if calendar.isDateInYesterday(date) { return Localized.text("wallet.history.day.yesterday") }
        // «12 января» — full genitive month, sentence case (artboard 21b).
        // The genitive comes from the *formatting* month form the day+month
        // skeleton picks; a standalone caption («январь 2026») needs the other
        // one and gets it from `YearMonth.fullNames` (#654).
        return CalendarDateFormatter.string(from: date, style: .dayMonth, calendar: calendar)
    }
}

// MARK: - Type filter chips (issue #282, SPMore3.jsx L142-152)

extension WalletTransactionHistoryViewController {

    /// «ЗА ЯНВАРЬ 2026» — caps caption of the summary card. The uppercasing
    /// stays here rather than in the catalogue so the stored copy keeps its
    /// sentence case (and its «Ё») for languages that do not shout.
    func summaryCapsCaption() -> String {
        Localized.format("wallet.history.summary.caps", period.summaryCaption)
            .uppercased(with: AppLocale.display)
    }

    func makeTypeFilterRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = AppSpacing.sp2
        row.alignment = .center
        for filter in TxHistoryTypeFilter.allCases {
            row.addArrangedSubview(makeFilterChip(for: filter))
        }
        // Trailing spacer so chips left-align (the row otherwise stretches).
        // Its hugging must sit BELOW the chips' (which is `.required` in
        // `makeFilterChip`), not merely at `.defaultLow` — that tied with the
        // buttons' own default 250 and the stack resolved the tie by index,
        // stretching the first chip instead of the spacer (#519).
        let spacer = UIView()
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    private func makeFilterChip(for filter: TxHistoryTypeFilter) -> UIButton {
        let selected = filter == typeFilter
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(
            filter.title,
            attributes: AttributeContainer([
                .font: AppFonts.sans(.semibold, 14),
                .foregroundColor: selected ? AppColors.bg0 : AppColors.fg2
            ])
        )
        // Canon is `padding: "8px 14px"` (`SPMore3.jsx:59`); the code had
        // drifted to a magic 7/12. `sp2` is 8 exactly; 14 has no token of its
        // own, so it is written as the grid step it actually is.
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: AppSpacing.sp2, leading: AppSpacing.sp3 + 2,
            bottom: AppSpacing.sp2, trailing: AppSpacing.sp3 + 2
        )
        // A pill must never break its own shape: the default line-break mode of
        // a configuration button word-wraps, and a single long word («Поступления»)
        // then splits mid-word into «Поступлени» / «я» inside the capsule (#519).
        // Truncating keeps the capsule intact — and the priorities below mean it
        // stays a fallback that shouldn't trigger at the shipped font size.
        configuration.titleLineBreakMode = .byTruncatingTail
        let chip = UIButton(configuration: configuration)
        // The chip owns its width: it hugs its title and refuses to be squeezed,
        // so the row's slack lands in the trailing spacer.
        chip.setContentHuggingPriority(.required, for: .horizontal)
        // 999, not `.required` — if three chips genuinely can't fit (a very
        // narrow screen), yield gracefully instead of breaking a constraint.
        chip.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
        // Pin the label to the 14pt design size. Configuration buttons opt into
        // Dynamic Type by default, and a scaled title is what pushes this row
        // past the screen width; same opt-out `SPButton` already makes.
        chip.titleLabel?.adjustsFontForContentSizeCategory = false
        chip.backgroundColor = selected ? AppColors.fg1 : AppColors.whiteOverlay06
        chip.layer.cornerRadius = AppRadius.lg
        chip.layer.masksToBounds = true
        chip.accessibilityLabel = filter.title
        chip.accessibilityTraits = selected ? [.button, .selected] : .button
        chip.tag = TxHistoryTypeFilter.allCases.firstIndex(of: filter) ?? 0
        chip.addTarget(self, action: #selector(typeFilterChipTapped(_:)), for: .touchUpInside)
        return chip
    }

    @objc fileprivate func typeFilterChipTapped(_ sender: UIButton) {
        let cases = TxHistoryTypeFilter.allCases
        guard cases.indices.contains(sender.tag) else { return }
        let picked = cases[sender.tag]
        guard picked != typeFilter else { return }
        typeFilter = picked
        reload()
    }

    func makeEmptyCard(
        hasAnyTransactions: Bool = false,
        periodHasTransactions: Bool = false
    ) -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp6, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        let message: String
        if !hasAnyTransactions {
            message = Localized.text("wallet.history.empty")
        } else if periodHasTransactions && typeFilter != .all {
            // Period has rows but the active type chip filtered them all out.
            message = Localized.text("wallet.history.empty_period_type")
        } else {
            message = Localized.text("wallet.history.empty_period")
        }
        label.text = message
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

    /// Builds the period chip + a distinct error card into `stack` when the
    /// ledger fails to decode (#419). Kept in this extension so the main type
    /// body stays under the SwiftLint cap.
    func populateLoadErrorState() {
        let chipRow = makePeriodChipRow()
        stack.addArrangedSubview(chipRow)
        stack.setCustomSpacing(AppSpacing.sp4, after: chipRow)
        stack.addArrangedSubview(makeLoadErrorCard())
    }

    /// Softer sibling of `makeLoadErrorCard`: the ledger DID load, but some
    /// rows carry a `type` this build can't classify (damage, or a newer
    /// build's ledger — see `TransactionType.unknown`). They're rendered in the
    /// list yet excluded from every total, so the card warns that the numbers
    /// above are incomplete rather than letting them silently understate the
    /// balance (#358). Warn-toned, not pain-toned — nothing is lost, and the
    /// wallet stays fully usable.
    func makeUnrecognizedRowsNotice() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp5, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = Localized.text("wallet.history.unrecognized_notice")
        label.font = AppTypography.meta
        label.textColor = AppColors.warn400
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

    /// Distinct card for a decode failure (#419) — the corrupt-ledger case
    /// must read as «не удалось загрузить», not the friendly empty-state, so
    /// the user doesn't recreate data over a recoverable blob. Tinted with the
    /// pain colour to set it apart from `makeEmptyCard`; mirrors how
    /// `StatisticsViewModel` surfaces its checked-load error.
    func makeLoadErrorCard() -> UIView {
        let card = SPCard(tone: .surface, padding: AppSpacing.sp6, cornerRadius: AppRadius.lg)
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = Localized.text("wallet.history.load_failed")
        label.font = AppTypography.body
        label.textColor = AppColors.pain400
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
}
