import Foundation

/// The one place that decides which locale user-facing formatters run in.
///
/// Before #569 twelve formatters each built their own
/// `Locale(identifier: "ru_RU")`, so "show dates and numbers in the user's
/// language" was a twelve-file change and nobody could tell which of the
/// hardcoded locales were deliberate. Now the decision lives here: switching
/// the app to the device locale is editing `display` and nothing else.
///
/// ⚠️ **`en_US_POSIX` is a different thing and does not belong here.** It is
/// for *parsing* or emitting fixed-format strings — a log line, a storage key,
/// an API timestamp — where a user locale would produce a different and
/// occasionally unparseable result. Nothing in the app does that today.
///
/// It is specifically **not** a way to force 24-hour time. `AlarmsListViewModel`,
/// `TimePickerCell` and `AlarmFiringViewController+ViewLifecycle` each pinned
/// POSIX for exactly that, and each thereby showed "19:00" to a reader whose
/// phone says "7:00 PM" everywhere else — am/pm is a *regional* setting, not a
/// language one. #628 routed all three through ``WallClockFormatter``, which
/// takes the hour cycle from the locale and the hour *width* from the design.
enum AppLocale {

    /// Locale for every formatter whose output a human reads: dates, month
    /// names, grouped numbers, `capitalized(with:)` / `uppercased(with:)`.
    ///
    /// Still Russian, because the app still ships Russian copy only — the
    /// English catalogue is the next step of #569. When it lands this becomes
    /// `.autoupdatingCurrent` and every call site follows without being
    /// touched.
    static let display = Locale(identifier: "ru_RU")
}
