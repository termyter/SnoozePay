import Foundation

/// Resolves the alarm-context suffix shown on charge rows — e.g.
/// "Будни · 07:00" — from a transaction's persisted `alarmID`
/// (issue #282, `SPScreensV2.jsx` L467).
///
/// A charge stores `alarmID` as the alarm's `UUID().uuidString`
/// (`BalanceService.charge`). The owning alarm may have been edited or
/// deleted since the charge was minted, so resolution is best-effort: a
/// missing / malformed id, or an alarm the repository no longer knows,
/// degrades to `nil` and the caller falls back to the bare "Поспать ещё"
/// title. Pure value type so the lookup can be stubbed in tests without
/// touching `AlarmRepository` / `UserDefaults`.
enum TransactionAlarmContext {

    /// "Будни · 07:00" — repeat-day summary + fire time, joined with the
    /// app's middot separator. `nil` when the alarm can't be resolved.
    ///
    /// - Parameters:
    ///   - alarmID: the transaction's persisted alarm id (UUID string).
    ///   - lookup: resolves a `UUID` to an `Alarm`, or `nil` if unknown.
    ///     Production passes a `try?`-collapsed `AlarmRepository.shared.fetchChecked(id:)`.
    static func caption(
        for alarmID: String?,
        calendar: Calendar = .current,
        lookup: (UUID) -> Alarm?
    ) -> String? {
        guard
            let alarmID,
            let uuid = UUID(uuidString: alarmID),
            let alarm = lookup(uuid)
        else {
            return nil
        }
        return caption(for: alarm, calendar: calendar)
    }

    /// "Будни · 07:00" for a concrete alarm.
    static func caption(for alarm: Alarm, calendar: Calendar = .current) -> String {
        "\(alarm.repeatDaysDescription) · \(timeString(for: alarm.time, calendar: calendar))"
    }

    private static func timeString(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.display
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
