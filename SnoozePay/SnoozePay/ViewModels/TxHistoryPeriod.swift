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

    // MARK: - Russian month names

    /// Lowercase nominative names — Russian only capitalizes month names at
    /// sentence start, so tokens stay lowercase and call sites capitalize.
    static let fullNames = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
    ]
    static let shortNames = [
        "янв", "фев", "мар", "апр", "май", "июн",
        "июл", "авг", "сен", "окт", "ноя", "дек"
    ]

    /// "январь 2026" — chip / summary caption for a single month.
    var fullCaption: String { "\(Self.fullNames[month - 1]) \(year)" }
    /// "янв 2026" — compact range-chip caption.
    var shortCaption: String { "\(Self.shortNames[month - 1]) \(year)" }
    /// "Январь 2026" — picker-sheet selected-range row.
    var capitalizedCaption: String {
        "\(Self.fullNames[month - 1].capitalized(with: Locale(identifier: "ru_RU"))) \(year)"
    }
    /// "Янв" — month-grid cell label.
    var gridLabel: String {
        Self.shortNames[month - 1].capitalized(with: Locale(identifier: "ru_RU"))
    }
    /// "Янв 2026" — capitalized compact caption for the (sentence-start)
    /// header chip when a range is selected.
    var capitalizedShortCaption: String {
        "\(Self.shortNames[month - 1].capitalized(with: Locale(identifier: "ru_RU"))) \(year)"
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

    /// "3 мес." — month counter next to the picker caption.
    var monthCountText: String { "\(monthCount) мес." }
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
        case .all: return "Все"
        case .charges: return "Списания"
        case .credits: return "Поступления"
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
    /// (`.refund`) are deliberately excluded — they appear in the list but not
    /// in this aggregate (issue #234 item 4; issue #358 for refunds, which are
    /// returned money, never income).
    let topups: Decimal
    /// Number of snooze charges the user actually paid for — a charge whose
    /// snooze never armed was refunded and per design "doesn't count", so it
    /// is excluded here just like in streak / Statistics (#133).
    let snoozeCount: Int

    static func compute(from transactions: [Transaction]) -> TxHistorySummary {
        var spent = Decimal(0)
        var topups = Decimal(0)
        var snoozes = 0
        // A reversed charge and its `.refund` must drop out together. Counting
        // the charge while skipping the refund (which is NOT a top-up since
        // #358) would leave the card claiming the user spent money that came
        // straight back. `realCharges` is the same helper streak / Statistics
        // use, so the three surfaces can't drift on what "a snooze" means.
        let realCharges = Set(TransactionRepository.realCharges(from: transactions).map(\.id))
        for transaction in transactions {
            switch transaction.type {
            case .charge:
                guard realCharges.contains(transaction.id) else { continue }
                spent += Decimal(abs(transaction.amount))
                snoozes += 1
            case .topup:
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
