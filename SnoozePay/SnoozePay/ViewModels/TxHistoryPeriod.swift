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

    /// Header chip: "январь 2026" / "ноя 2025 — янв 2026".
    var chipCaption: String {
        isSingleMonth ? start.fullCaption : "\(start.shortCaption) — \(end.shortCaption)"
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

/// Three-column aggregate for the summary card — Списано / Пополнения /
/// Откладываний (issue #234 item 3). Computed over the *visible* list so
/// the card always reconciles with what the user sees below it.
struct TxHistorySummary: Equatable {
    /// Absolute sum of charges, ₽.
    let spent: Decimal
    /// Sum of paid top-ups, ₽. Bonuses (`.promotion`) are deliberately
    /// excluded — they appear in the list but not in this aggregate
    /// (issue #234 item 4).
    let topups: Decimal
    /// Number of snooze charges.
    let snoozeCount: Int

    static func compute(from transactions: [Transaction]) -> TxHistorySummary {
        var spent = Decimal(0)
        var topups = Decimal(0)
        var snoozes = 0
        for transaction in transactions {
            switch transaction.type {
            case .charge:
                spent += Decimal(abs(transaction.amount))
                snoozes += 1
            case .topup:
                topups += Decimal(abs(transaction.amount))
            case .promotion:
                continue // bonus — list-only, never aggregated
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
