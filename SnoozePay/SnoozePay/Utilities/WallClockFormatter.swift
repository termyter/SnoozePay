import Foundation

/// The one place that renders a **time of day** for a human to read.
///
/// Before #628 seven call sites each froze the clock at 24 hours — four by
/// pinning `en_US_POSIX` and writing `HH:mm`, one (`clockText`) by assembling
/// the string arithmetically with `String(format: "%d:%02d", …)`. All of them
/// were deliberate at the time and all of them are wrong for the same reason:
/// whether a person reads "19:05" or "7:05 PM" is a property of their
/// *regional* settings, not of the app's language. A Russian-language user who
/// turns off «24-часовой формат» in iOS Settings gets 12-hour time everywhere
/// on the device except here.
///
/// The pattern now comes from the locale via the `j` skeleton — "hour in
/// whatever cycle this user reads" — so the decision lives with the user.
/// Today ``AppLocale/display`` is pinned `ru_RU`, which is a 24-hour locale, so
/// **output is byte-for-byte what it was**; the day #569 flips `display` to
/// `.autoupdatingCurrent`, every clock in the app follows without being touched
/// again.
///
/// ⚠️ **Durations are not wall clocks and must not come here.** The `mm:ss`
/// countdowns (`AlarmFiringViewModel.countdownText`,
/// `FiringTopUpBottomSheetViewController`) and the audio timecode
/// (`SoundPickerViewController.timecode`) legitimately build their strings by
/// hand: an elapsed span has no hour cycle and no AM/PM, and routing it through
/// a `DateFormatter` would turn "02:30 left" into "2:30 AM".
enum WallClockFormatter {

    /// How wide the hour reads — a *design* choice, not a locale one.
    ///
    /// The `j` skeleton decides the cycle but also normalises the width: ICU
    /// resolves both `jm` and `jjmm` to the locale's own short-time pattern
    /// (`HH:mm` under `ru_RU`), so it cannot express "24-hour, but unpadded".
    /// The app needs both — the alarms list and the statistics card show "7:30"
    /// per artboard 06 (#343), the firing screen and the wallet show "07:30" —
    /// so the width is re-applied after the locale has had its say.
    ///
    /// This only bites on a 24-hour locale. A 12-hour one is left exactly as
    /// the locale wrote it, because "07:04 AM" is not English anyone writes.
    enum HourStyle {
        /// "07:04" on a 24-hour locale.
        case padded
        /// "7:04" on a 24-hour locale.
        case compact
    }

    // MARK: - Formatting

    /// Wall-clock time of `date`.
    ///
    /// Pass `calendar` when the caller has one (it also supplies the time
    /// zone); otherwise the formatter uses the current one, as the hand-rolled
    /// formatters it replaces did.
    static func string(
        from date: Date,
        style: HourStyle,
        locale: Locale = AppLocale.display,
        calendar: Calendar? = nil
    ) -> String {
        cachedFormatter(style: style, locale: locale, calendar: calendar).string(from: date)
    }

    /// Wall-clock time of a minutes-since-midnight offset, for aggregations
    /// that never had a `Date` to begin with (a median wake minute, say).
    ///
    /// The offset is clamped into a single day. The arithmetic version this
    /// replaces rendered an out-of-range 1500 as "25:00"; a `DateFormatter`
    /// would silently wrap it to "01:00" of the next day, and neither is a
    /// reading anyone wants shipped — so the input is pinned to 23:59 instead.
    static func string(
        minutesSinceMidnight minutes: Int,
        style: HourStyle,
        locale: Locale = AppLocale.display
    ) -> String {
        let clamped = min(max(0, minutes), minutesPerDay - 1)
        let components = DateComponents(
            year: 2001, month: 1, day: 1,
            hour: clamped / 60, minute: clamped % 60
        )
        guard let date = utcCalendar.date(from: components) else { return "" }
        return string(from: date, style: style, locale: locale, calendar: utcCalendar)
    }

    // MARK: - Private

    private static let minutesPerDay = 24 * 60

    /// Fixed calendar for the minutes-since-midnight path, so an offset means
    /// the same wall clock regardless of the device's zone or DST.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// Building a `DateFormatter` costs ~1ms, and two of the call sites are hot
    /// — the firing screen re-renders once a second, the alarms list once per
    /// cell — so the default-locale pair is built once. Anything with an
    /// injected locale or calendar (tests, calendar-carrying view models) is
    /// built on demand; `DateFormatter.string(from:)` is thread-safe for reads.
    private static let displayPadded = makeFormatter(style: .padded, locale: AppLocale.display, calendar: nil)
    private static let displayCompact = makeFormatter(style: .compact, locale: AppLocale.display, calendar: nil)

    private static func cachedFormatter(style: HourStyle, locale: Locale, calendar: Calendar?) -> DateFormatter {
        guard calendar == nil, locale == AppLocale.display else {
            return makeFormatter(style: style, locale: locale, calendar: calendar)
        }
        return style == .padded ? displayPadded : displayCompact
    }

    private static func makeFormatter(style: HourStyle, locale: Locale, calendar: Calendar?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        if let calendar {
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
        }
        // `j` = "the hour field this locale's users actually read". The locale
        // has to be set first — `setLocalizedDateFormatFromTemplate` resolves
        // against whatever is on the formatter at the moment of the call.
        formatter.setLocalizedDateFormatFromTemplate("jm")
        if let pattern = formatter.dateFormat {
            formatter.dateFormat = applying(style, to: pattern)
        }
        return formatter
    }

    /// Re-applies the hour width to a locale-resolved pattern.
    ///
    /// A pattern carrying a quoted literal is returned untouched: `'` fences
    /// text that must not be read as fields, and no 24-hour short-time pattern
    /// in CLDR has one, so bailing out is cheaper than parsing quotes.
    private static func applying(_ style: HourStyle, to pattern: String) -> String {
        guard !pattern.contains("'"), pattern.contains("H") else { return pattern }
        let compact = pattern.replacingOccurrences(of: "HH", with: "H")
        return style == .padded ? compact.replacingOccurrences(of: "H", with: "HH") : compact
    }
}
