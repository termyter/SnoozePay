import Foundation

/// One calendar month (`year` + 1-based `month`). The TxHistory period
/// picker (issue #234, artboards 21/21a/21b) selects whole months, so a
/// dedicated value type keeps comparisons / range math away from `Date`
/// pitfalls (DST, time zones, partial days).
struct YearMonth: Equatable, Hashable, Comparable {
    let year: Int
    /// 1...12 (January = 1).
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
    }

    /// Linear month index — months become comparable / subtractable across
    /// year boundaries (mirrors `idx()` in `SPMore3.jsx` L214).
    var linearIndex: Int { year * 12 + (month - 1) }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        lhs.linearIndex < rhs.linearIndex
    }

    // MARK: - Month names

    /// Lowercase nominative names, read from the calendar rather than from
    /// `Localizable.xcstrings` — the same call ``WeekdayNames`` makes and for
    /// the same reason (#569): a month name is data every locale ships with
    /// CLDR, not copy a translator should retype.
    ///
    /// The substitution is exact, which is why it is safe: `ru_RU`'s
    /// `standaloneMonthSymbols` is «январь … декабрь» character for character.
    /// Nominative *because* they are standalone symbols — the genitive
    /// («12 января») lives in `monthSymbols` and is what a `d MMMM` pattern
    /// picks up, so deriving these does not disturb the declension of dates
    /// rendered elsewhere. Russian only capitalizes month names at sentence
    /// start, so tokens stay lowercase and call sites capitalize.
    ///
    /// Stored rather than computed: these come from the system and cannot go
    /// missing, unlike catalogue copy (``Plural``).
    static let fullNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.display
        guard let symbols = formatter.standaloneMonthSymbols, symbols.count == 12 else { return [] }
        return symbols
    }()

    /// Abbreviated names — **copy**, unlike ``fullNames``. `ru_RU`'s
    /// `shortStandaloneMonthSymbols` is «янв., февр., март, апр., май, июнь,
    /// июль, авг., сент., окт., нояб., дек.»: trailing periods, four months
    /// not abbreviated at all and widths from three to five characters, where
    /// the design's month grid (artboard 21b) is a fixed set of three-letter
    /// tokens. So these stay in the catalogue, and
    /// `WalletHistoryLocalizationTests` pins the mismatch — a future CLDR
    /// revision that closes it should surface as one named failure, not as a
    /// silent invitation to re-derive them.
    static var shortNames: [String] { (1...12).map { shortName(ofMonth: $0) } }

    /// Abbreviated name of `month` (1-based), straight from the catalogue —
    /// avoids building all twelve to read one.
    static func shortName(ofMonth month: Int) -> String {
        Localized.text(String(format: "wallet.month.short_%02d", month))
    }

    /// "январь 2026" — chip / summary caption for a single month.
    var fullCaption: String { "\(Self.fullNames[month - 1]) \(year)" }
    /// "янв 2026" — compact range-chip caption.
    var shortCaption: String { "\(Self.shortName(ofMonth: month)) \(year)" }
    /// "Январь 2026" — picker-sheet selected-range row.
    var capitalizedCaption: String {
        "\(Self.fullNames[month - 1].capitalized(with: AppLocale.display)) \(year)"
    }
    /// "Янв" — month-grid cell label.
    var gridLabel: String {
        Self.shortName(ofMonth: month).capitalized(with: AppLocale.display)
    }
    /// "Янв 2026" — capitalized compact caption for the (sentence-start)
    /// header chip when a range is selected.
    var capitalizedShortCaption: String {
        "\(Self.shortName(ofMonth: month).capitalized(with: AppLocale.display)) \(year)"
    }
}

/// Selected reporting period for the transaction-history screen — either a
/// single month or an inclusive month range. Stored normalized
/// (`start <= end`) regardless of tap order in the picker.
struct TxHistoryPeriod: Equatable {
    let start: YearMonth
    let end: YearMonth

    init(start: YearMonth, end: YearMonth) {
        if start <= end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }

    init(month: YearMonth) {
        self.init(start: month, end: month)
    }

    static func currentMonth(now: Date = Date(), calendar: Calendar = .current) -> TxHistoryPeriod {
        TxHistoryPeriod(month: YearMonth(date: now, calendar: calendar))
    }

    var isSingleMonth: Bool { start == end }

    /// Months between `start` and `end` inclusive (≥ 1).
    var monthCount: Int { end.linearIndex - start.linearIndex + 1 }

    func contains(_ month: YearMonth) -> Bool {
        (start.linearIndex...end.linearIndex).contains(month.linearIndex)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        contains(YearMonth(date: date, calendar: calendar))
    }

    /// Transactions inside the period, preserving input order.
    func filter(_ transactions: [Transaction], calendar: Calendar = .current) -> [Transaction] {
        transactions.filter { contains($0.createdAt, calendar: calendar) }
    }

    // MARK: - Captions (artboard 21)

    /// Header chip, capitalized as a sentence start: "Январь 2026" /
    /// "Ноя 2025 — Янв 2026" (issue #282 — Russian capitalizes month names
    /// at sentence start, and the chip is a standalone caption).
    var chipCaption: String {
        isSingleMonth
            ? start.capitalizedCaption
            : "\(start.capitalizedShortCaption) — \(end.capitalizedShortCaption)"
    }

    /// Summary-card caption (rendered uppercase by the caps style):
    /// "январь 2026" / "ноябрь 2025 — январь 2026".
    var summaryCaption: String {
        isSingleMonth ? start.fullCaption : "\(start.fullCaption) — \(end.fullCaption)"
    }

    /// Picker-sheet selected-range row: "Январь 2026" /
    /// "Ноябрь 2025 — Январь 2026".
    var pickerCaption: String {
        isSingleMonth
            ? start.capitalizedCaption
            : "\(start.capitalizedCaption) — \(end.capitalizedCaption)"
    }

    /// "3 мес." — month counter next to the picker caption. One key, not a
    /// plural set: the Russian abbreviation does not decline (1 / 3 / 5 мес.),
    /// and a language that does decline it can add its own variations to this
    /// entry without a call-site change.
    var monthCountText: String { Localized.format("wallet.period.month_count", monthCount) }
}

/// Transaction-type filter for the chip row under the summary card
/// (issue #282, `SPMore3.jsx` L142-152). Composes *after* the period
/// filter — period narrows by date, this narrows by direction.
enum TxHistoryTypeFilter: CaseIterable {
    /// «Все» — no type restriction.
    case all
    /// «Списания» — debits only (`.charge`).
    case charges
    /// «Поступления» — credits: paid top-ups, bonuses *and* penalty
    /// reversals (`.topup` + `.promotion` + `.refund`). All three add money to
    /// the balance, so the user-facing "поступления" bucket groups them.
    case credits

    /// Chip label.
    var title: String {
        switch self {
        case .all: return Localized.text("wallet.history.filter.all")
        case .charges: return Localized.text("wallet.history.filter.charges")
        case .credits: return Localized.text("wallet.history.filter.credits")
        }
    }

    /// Whether a transaction passes this filter.
    func matches(_ transaction: Transaction) -> Bool {
        switch self {
        case .all:
            return true
        case .charges:
            return transaction.type == .charge
        case .credits:
            switch transaction.type {
            case .topup, .promotion, .refund:
                return true
            // An unrecognised row (ledger written by a newer build, see
            // `TransactionType.unknown`) has no known direction — it stays in
            // «Все» rather than being claimed by either bucket.
            case .charge, .unknown:
                return false
            }
        }
    }

    /// Filtered list, preserving input order.
    func filter(_ transactions: [Transaction]) -> [Transaction] {
        transactions.filter(matches)
    }
}

/// Three-column aggregate for the summary card — Списано / Пополнения /
/// Откладываний (issue #234 item 3). Computed over the *visible* list so
/// the card always reconciles with what the user sees below it.
struct TxHistorySummary: Equatable {
    /// Absolute sum of charges, ₽.
    let spent: Decimal
    /// Sum of paid top-ups, ₽. Bonuses (`.promotion`) and penalty reversals
    /// are deliberately excluded — they appear in the list but not in this
    /// aggregate (issue #234 item 4; issue #358 for refunds, which are
    /// returned money, never income). "Reversal" covers both shapes: the
    /// current `.refund` row *and* the pre-#358 `.topup` row that carries a
    /// `refundsTransactionID`.
    let topups: Decimal
    /// Number of snooze charges the user actually paid for — a charge whose
    /// snooze never armed was refunded and per design "doesn't count", so it
    /// is excluded here just like in streak / Statistics (#133).
    let snoozeCount: Int

    /// - Parameters:
    ///   - transactions: the rows the card must reconcile with — the period
    ///     slice the user is looking at.
    ///   - ledger: the FULL ledger, used only to decide which charges were
    ///     reversed. A refund can land in a different period than its charge
    ///     (23:59 on the 31st, refunded at 00:00 on the 1st), and scoping the
    ///     pairing to the visible slice would then show a fully-reversed snooze
    ///     as real spend. Same convention `AlarmsListViewModel.weeklyDelta`
    ///     follows for its rolling window (#440).
    static func compute(from transactions: [Transaction], ledger: [Transaction]) -> TxHistorySummary {
        var spent = Decimal(0)
        var topups = Decimal(0)
        var snoozes = 0
        // A reversed charge and its refund must drop out together. Counting
        // the charge while skipping the refund (which is NOT a top-up since
        // #358) would leave the card claiming the user spent money that came
        // straight back. `realCharges` is the same helper streak / Statistics
        // use, so the three surfaces can't drift on what "a snooze" means.
        let realCharges = Set(TransactionRepository.realCharges(from: ledger).map(\.id))
        for transaction in transactions {
            switch transaction.type {
            case .charge:
                guard realCharges.contains(transaction.id) else { continue }
                spent += Decimal(abs(transaction.amount))
                snoozes += 1
            case .topup:
                // Pre-#358 ledgers recorded reversals as `.topup` + link. Now
                // that the charge side drops out, counting this side would
                // claim a top-up that never happened — the card would imply
                // +50 ₽ of movement against a balance that never moved.
                guard transaction.refundsTransactionID == nil else { continue }
                topups += Decimal(abs(transaction.amount))
            case .promotion, .refund, .unknown:
                continue // bonus / reversal / unrecognised — list-only
            }
        }
        return TxHistorySummary(spent: spent, topups: topups, snoozeCount: snoozes)
    }
}

/// Tap-selection state machine for `PeriodPickerSheetViewController`
/// (artboards 21a/21b): first tap anchors a single month, a second tap on a
/// different month extends it into a range, a third tap restarts with a new
/// anchor. Pure value type so the UX rules are unit-testable without UIKit.
struct TxHistoryPeriodSelection: Equatable {
    private(set) var anchor: YearMonth?
    private(set) var extent: YearMonth?

    init(period: TxHistoryPeriod? = nil) {
        anchor = period?.start
        extent = (period?.isSingleMonth == true) ? nil : period?.end
    }

    /// Current selection as a period; `nil` when nothing is selected
    /// (after "Сбросить").
    var period: TxHistoryPeriod? {
        guard let anchor else { return nil }
        guard let extent else { return TxHistoryPeriod(month: anchor) }
        return TxHistoryPeriod(start: anchor, end: extent)
    }

    mutating func tap(_ month: YearMonth) {
        switch (anchor, extent) {
        case (nil, _):
            anchor = month
            extent = nil
        case (let some?, nil):
            if some == month { return } // re-tap on the anchor keeps single
            extent = month
        case (_?, _?):
            anchor = month
            extent = nil
        }
    }

    mutating func reset() {
        anchor = nil
        extent = nil
    }
}
