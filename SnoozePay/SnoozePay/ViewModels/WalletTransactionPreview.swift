import Foundation

/// Presentation model for one row in the Wallet tab's "История операций"
/// preview card (issue #233, artboard 18). Pure data — the view controller
/// maps it 1:1 onto an `SPRow`.
struct WalletTransactionPreviewItem: Equatable {
    let title: String
    /// Relative timestamp, e.g. "Сегодня · 07:09", "Вчера · 21:32",
    /// "12 апр. · 09:00".
    let timestampText: String
    /// Signed amount string, e.g. "−50 ₽" / "+500 ₽" (formatted via
    /// `Decimal.formattedRubles()` — never hand-rolled).
    let amountText: String
    /// `true` for charges (red flame), `false` for credits (green plus/gift).
    let isDebit: Bool
    /// SF Symbol name for the leading 36×36 icon tile.
    let iconSystemName: String
}

/// Builds the last-N-transactions preview shown on the Wallet tab.
/// Extracted from the controller so the ordering / formatting rules are
/// unit-testable without UIKit.
enum WalletTransactionPreview {

    /// The design shows exactly three rows before the "Все операции →" link.
    static let maxItems = 3

    /// Newest-first preview rows, capped at `maxItems`. Input order is not
    /// trusted — the repository returns newest-first today, but the preview
    /// re-sorts defensively so a future ordering change can't flip the card.
    static func items(
        from transactions: [Transaction],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WalletTransactionPreviewItem] {
        transactions
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maxItems)
            .map { item(for: $0, now: now, calendar: calendar) }
    }

    static func item(
        for transaction: Transaction,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WalletTransactionPreviewItem {
        let title: String
        let icon: String
        let isDebit: Bool
        switch transaction.type {
        case .charge:
            title = "Поспать ещё"
            icon = "flame"
            isDebit = true
        case .topup:
            title = "Пополнение баланса"
            icon = "plus"
            isDebit = false
        case .promotion:
            title = "Промо-зачисление"
            icon = "gift"
            isDebit = false
        }
        let absolute = Decimal(abs(transaction.amount))
        let sign = isDebit ? "−" : "+"
        return WalletTransactionPreviewItem(
            title: title,
            timestampText: timestampText(for: transaction.createdAt, now: now, calendar: calendar),
            amountText: "\(sign)\(absolute.formattedRubles())",
            isDebit: isDebit,
            iconSystemName: icon
        )
    }

    /// "Сегодня · HH:mm" / "Вчера · HH:mm" / "d MMM · HH:mm" relative to
    /// the injected `now` (so tests don't depend on the wall clock).
    static func timestampText(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ru_RU")
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return "Сегодня · \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Вчера · \(time)"
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "d MMM"
        return "\(dayFormatter.string(from: date)) · \(time)"
    }
}
