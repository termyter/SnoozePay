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
    ///
    /// `alarmLookup` resolves a charge's owning alarm so its context
    /// ("Будни · 07:00") can prefix the timestamp; production passes
    /// a `try?`-collapsed `AlarmRepository.shared.fetchChecked(id:)`. The default
    /// no-op lookup keeps existing tests (and any context-free call site) bare.
    static func items(
        from transactions: [Transaction],
        now: Date = Date(),
        calendar: Calendar = .current,
        alarmLookup: (UUID) -> Alarm? = { _ in nil }
    ) -> [WalletTransactionPreviewItem] {
        transactions
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maxItems)
            .map { item(for: $0, now: now, calendar: calendar, alarmLookup: alarmLookup) }
    }

    static func item(
        for transaction: Transaction,
        now: Date = Date(),
        calendar: Calendar = .current,
        alarmLookup: (UUID) -> Alarm? = { _ in nil }
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
            // Unified with the history screen — honest copy (the only
            // promotion source today is the referral bonus) + the same gift
            // glyph (issue #282).
            title = "Бонус за друга"
            icon = "gift"
            isDebit = false
        case .refund:
            // Penalty returned because the snooze never armed (#358) — the
            // "undo" glyph reads as a reversal, not as fresh money in.
            title = "Возврат за откладывание"
            icon = "arrow.uturn.backward"
            isDebit = false
        case .unknown:
            // Row written by a newer build than this one (see
            // `TransactionType.unknown`). Render something neutral rather than
            // hiding it — the ledger row exists and the user should see it.
            title = "Операция"
            icon = "questionmark"
            isDebit = false
        }
        let absolute = Decimal(abs(transaction.amount))
        // An unrecognised row has no known direction — show the bare amount
        // rather than asserting a "+" the ledger never promised.
        let sign = transaction.type.isUnrecognized ? "" : (isDebit ? "−" : "+")
        let timestamp = timestampText(for: transaction.createdAt, now: now, calendar: calendar)
        // Charges prepend the resolvable alarm context, mirroring the
        // history screen; orphaned/edited-away alarms degrade to bare time.
        let subtitle: String
        if transaction.type == .charge,
           let context = TransactionAlarmContext.caption(
               for: transaction.alarmID, calendar: calendar, lookup: alarmLookup
           ) {
            subtitle = "\(context) · \(timestamp)"
        } else {
            subtitle = timestamp
        }
        return WalletTransactionPreviewItem(
            title: title,
            timestampText: subtitle,
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
