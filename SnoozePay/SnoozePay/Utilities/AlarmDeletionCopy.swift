import Foundation

/// Copy composer for the confirm-delete bottom sheet (#277).
///
/// The pre-#277 default body claimed «Деньги с баланса не вернутся. Это
/// безвозвратно.» — semantically wrong: deleting an alarm never touches the
/// balance. The design (`SPMore2.jsx` `ConfirmDelete()`) instead *reassures*
/// the user:
///
///   «Будни · Пн–Пт · 07:00. Баланс 840 ₽ останется на месте — он привязан
///    к аккаунту, а не к будильнику.»
///
/// Two pieces compose that line:
/// - `contextLine(repeatDays:repeatMode:time:)` — the alarm identity
///   («Будни · Пн–Пт · 07:00»), mirroring the caps-row phrasing of
///   `AlarmsListViewModel.weekdayPhrase` (private there). The day *names* come
///   from CLDR through `Weekday.localizedShortName`, not from the catalogue;
///   only the phrasing — the ranges and the three-segment one-shot line — is
///   copy, and it gets its own `alarms.delete.*` keys.
/// - `body(contextLine:balance:currency:)` — the reassurance sentence with the
///   live balance interpolated via `MoneyFormatter` (single money-string
///   source), in the wallet's display currency (#1151).
enum AlarmDeletionCopy {

    // MARK: - Body

    /// Full sheet subtitle. With a context line the result matches the
    /// artboard: «<context>. Баланс N ₽ останется на месте — …». Without one
    /// (e.g. generic call sites that have no alarm at hand) the reassurance
    /// sentence stands alone.
    ///
    /// `currency` is the wallet's `BalanceService.displayCurrency`, and it has
    /// no default so no caller falls back to roubles by omission (#1151): a
    /// stored-USD wallet holding $1.99 used to read «Баланс 1 ₽». Roubles keep
    /// the legacy whole-rouble formatter, so a rouble sheet reads as before.
    static func body(contextLine: String? = nil, balance: Double, currency: Currency) -> String {
        let amount = currency == .rub
            ? MoneyFormatter.string(balance)
            : MoneyFormatter.string(balance, currency: currency)
        let reassurance = Localized.format("alarms.delete.reassurance", amount)
        guard let contextLine, !contextLine.isEmpty else { return reassurance }
        return Localized.format("alarms.delete.body", contextLine, reassurance)
    }

    // MARK: - Context line

    /// «Будни · Пн–Пт · 07:00»-style alarm identity:
    /// - weekly weekdays  → `Будни · Пн–Пт · 07:00`
    /// - weekly weekend   → `Выходные · Сб–Вс · 07:00`
    /// - weekly all days  → `Каждый день · 07:00`
    /// - weekly subset    → `Вт, Чт · 07:00`
    /// - one-shot (`.never`) → `Единожды · Пн–Пт · 07:00` (compact day range,
    ///   no «Будни» expansion — three segments max)
    /// - no days selected → `Единожды · 07:00`
    static func contextLine(
        repeatDays: [Int],
        repeatMode: AlarmRepeatMode,
        time: Date,
        clockTime: TimeOfDay? = nil,
        calendar: Calendar? = nil
    ) -> String {
        let timeString: String
        if let clockTime {
            timeString = WallClockFormatter.string(
                minutesSinceMidnight: clockTime.hour * 60 + clockTime.minute, style: .padded
            )
        } else {
            timeString = WallClockFormatter.string(from: time, style: .padded, calendar: calendar)
        }
        let sorted = sanitizedSortedDays(repeatDays)
        guard !sorted.isEmpty else { return Localized.format("alarms.delete.once_at", timeString) }
        if repeatMode == .never {
            return Localized.format(
                "alarms.delete.once_on_at", compactDayPhrase(for: sorted), timeString
            )
        }
        return Localized.format("alarms.delete.schedule_at", weeklyDayPhrase(for: sorted), timeString)
    }

    // MARK: - Private

    /// Monday-first weekday indices, the legacy `repeatDays` convention. The
    /// names themselves come from `Weekday.localizedShortName` (CLDR), so this
    /// file no longer carries a second copy of the table.
    private static let weekdayIndices = 0...6
    private static let weekdaysSet = [0, 1, 2, 3, 4]
    private static let weekendSet = [5, 6]

    private static func sanitizedSortedDays(_ days: [Int]) -> [Int] {
        days.filter { weekdayIndices.contains($0) }.sorted()
    }

    /// Weekly phrasing per the artboard: named bucket plus the day range.
    private static func weeklyDayPhrase(for sorted: [Int]) -> String {
        if sorted == Array(weekdayIndices) { return Localized.text("alarms.days.every_day") }
        if sorted == weekdaysSet { return Localized.text("alarms.days.weekdays") }
        if sorted == weekendSet { return Localized.text("alarms.days.weekend_range") }
        return joinedDayNames(sorted)
    }

    /// Range-only phrasing for one-shot alarms, where «Единожды» already
    /// occupies the leading bucket slot.
    private static func compactDayPhrase(for sorted: [Int]) -> String {
        if sorted == Array(weekdayIndices) { return Localized.text("alarms.delete.range_all") }
        if sorted == weekdaysSet { return Localized.text("alarms.delete.range_weekdays") }
        if sorted == weekendSet { return Localized.text("alarms.delete.range_weekend") }
        return joinedDayNames(sorted)
    }

    private static func joinedDayNames(_ sorted: [Int]) -> String {
        sorted
            .compactMap { Weekday(legacyMondayFirstIndex: $0)?.localizedShortName }
            .joined(separator: ", ")
    }
}
