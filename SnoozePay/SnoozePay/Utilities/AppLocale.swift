import Foundation

/// The one place that decides which locale user-facing formatters run in.
///
/// Before #569 twelve formatters each built their own
/// `Locale(identifier: "ru_RU")`, so "show dates and numbers in the user's
/// language" was a twelve-file change and nobody could tell which of the
/// hardcoded locales were deliberate. Now the decision lives here: switching
/// the app to the device locale is editing `display` and nothing else.
///
/// ⚠️ **`en_US_POSIX` is a different thing and does not belong here.**
/// `AlarmsListViewModel`, `TimePickerCell` and
/// `AlarmFiringViewController+ViewLifecycle` pin POSIX because they *parse*
/// fixed-format strings ("HH:mm"), where a user locale would produce a
/// different — and occasionally unparseable — result. Those three stay as they
/// are; they are not display locales and must not be routed through `display`.
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
