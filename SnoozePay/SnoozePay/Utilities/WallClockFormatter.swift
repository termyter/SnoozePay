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
        guard let date = utcCalendar.date(from: components) else {
            // Unreachable: `clamped` is pinned to 0…1439 above. Kept loud
            // anyway — the arithmetic `clockText` this replaces could NOT
            // return an empty string, and quietly gaining that ability is
            // how a blank stat card ships.
            AppLogger.ui.fault("WallClockFormatter: minute offset \(clamped, privacy: .public) built no date")
            assertionFailure("minute offset \(clamped) built no date")
            return ""
        }
        return string(from: date, style: style, locale: locale, calendar: utcCalendar)
    }

    // MARK: - Private

    private static let minutesPerDay = 24 * 60

    /// Fixed calendar for the minutes-since-midnight path, so an offset means
    /// the same wall clock regardless of the device's zone or DST.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // NOT `?? .current`: falling back to the device zone would silently
        // change what a minutes-since-midnight offset MEANS — it would start
        // depending on the reader's zone and could shift the rendered hour
        // across a DST boundary. GMT is always constructible; if it ever is
        // not, that is a broken Foundation, not a case to paper over.
        guard let gmt = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("GMT is not constructible — Foundation is broken")
        }
        calendar.timeZone = gmt
        return calendar
    }()

    /// Building a `DateFormatter` costs ~1ms, and two of the call sites are hot
    /// — the firing screen re-renders once a second, the alarms list once per
    /// cell — so the default-locale pair is built once. Anything with an
    /// injected locale or calendar (tests, calendar-carrying view models) is
    /// built on demand.
    ///
    /// ⚠️ **The cache must be invalidated, or it reopens #628 through the back
    /// door.** `setLocalizedDateFormatFromTemplate` resolves the skeleton ONCE
    /// and writes a literal pattern into `dateFormat`; from then on the
    /// formatter never consults the locale again. And the guard below cannot
    /// notice, because `Locale.autoupdatingCurrent == Locale.autoupdatingCurrent`
    /// is `true` — verified, not assumed. So on the day #569/#603 points
    /// `AppLocale.display` at `.autoupdatingCurrent`, a reader toggling
    /// «24-Hour Time» in Settings would keep seeing the old cycle on five of
    /// the seven call sites until the app was restarted: exactly the bug this
    /// file exists to fix, with a delay.
    ///
    /// Hence the observer. It is cheap (one notification, fired on a setting
    /// nobody flips in a loop) and it is the difference between a fix that
    /// lands and one that only looks like it did.
    private static let cache = FormatterCache()

    private static func cachedFormatter(style: HourStyle, locale: Locale, calendar: Calendar?) -> DateFormatter {
        guard calendar == nil, locale == AppLocale.display else {
            return makeFormatter(style: style, locale: locale, calendar: calendar)
        }
        return cache.formatter(for: style)
    }

    /// Holds the two default-locale formatters and drops them when the
    /// reader's regional settings change.
    ///
    /// A class rather than statics because it needs a lifetime: an observer to
    /// register and state to clear. Locked because the alarms list builds cells
    /// off the main queue in tests and `DateFormatter` is only safe for
    /// concurrent *reads* — rebuilding one while another thread reads it is not.
    private final class FormatterCache {

        private var padded: DateFormatter?
        private var compact: DateFormatter?
        private let lock = NSLock()

        init() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(localeChanged),
                name: NSLocale.currentLocaleDidChangeNotification,
                object: nil
            )
        }

        func formatter(for style: HourStyle) -> DateFormatter {
            lock.lock()
            defer { lock.unlock() }
            switch style {
            case .padded:
                if let padded { return padded }
                let made = makeFormatter(style: .padded, locale: AppLocale.display, calendar: nil)
                padded = made
                return made
            case .compact:
                if let compact { return compact }
                let made = makeFormatter(style: .compact, locale: AppLocale.display, calendar: nil)
                compact = made
                return made
            }
        }

        /// Exposed for the test that proves invalidation actually rebuilds —
        /// without it the cached branch is untestable and a regression there
        /// passes green.
        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            padded = nil
            compact = nil
        }

        @objc private func localeChanged() {
            invalidate()
        }
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
        // A formatter whose `dateFormat` never resolved renders the EMPTY
        // STRING, not a wrong time — verified against Foundation. Blank
        // clocks on every screen with no log line is the worst way to find
        // out, so say it out loud and trap in DEBUG. There is no sane
        // fallback pattern to substitute: guessing one would re-freeze the
        // hour cycle this whole file exists to unfreeze.
        guard let pattern = formatter.dateFormat, !pattern.isEmpty else {
            AppLogger.ui.fault(
                """
                WallClockFormatter: `jm` unresolved for \
                \(locale.identifier, privacy: .public) — clocks would render empty
                """
            )
            assertionFailure("`jm` did not resolve for locale \(locale.identifier)")
            return formatter
        }
        formatter.dateFormat = applying(style, to: pattern)
        return formatter
    }

    /// Re-applies the hour width to a locale-resolved pattern.
    ///
    /// Returns the pattern untouched in two cases, neither of them an error —
    /// the width is a design preference, not a correctness requirement:
    ///
    /// - **A quoted literal.** `'` fences text that must not be read as
    ///   fields, and rewriting inside it would corrupt the pattern. Not
    ///   hypothetical, contrary to what this comment asserted before anyone
    ///   checked: `oc` resolves `jm` to `HH'h'mm`, `nds` to `'Kl'. H.mm`,
    ///   `dsb` to `'zeg'. H:mm`, `hsb` to `H:mm 'hodź'.`.
    /// - **A 12-hour pattern** (`h`/`K`), left exactly as the locale wrote it,
    ///   because "07:04 AM" is not English anyone writes.
    ///
    /// `k`/`kk` — the 1–24 cycle, which `ru_RU` produces under an explicit
    /// `hourCycle=h24` override — is handled alongside `H`/`HH`: same field,
    /// different numbering, and artboard 06 wants the same width from both.
    ///
    /// Verified by running all 951 `Locale.availableIdentifiers` plus forced
    /// h11/h12/h23/h24 overrides through this function: no 12-hour pattern is
    /// altered, no `a` moved or dropped, no quote broken.
    private static func applying(_ style: HourStyle, to pattern: String) -> String {
        guard !pattern.contains("'") else { return pattern }
        for hour in ["H", "k"] where pattern.contains(hour) {
            let doubled = hour + hour
            let compact = pattern.replacingOccurrences(of: doubled, with: hour)
            return style == .padded
                ? compact.replacingOccurrences(of: hour, with: doubled)
                : compact
        }
        return pattern
    }

    #if DEBUG
    /// Identity of the cached formatter, so a test can prove a locale change
    /// actually rebuilds it. Without this the cached branch — the only one
    /// that runs in production on the hot paths — is unobservable, and a
    /// regression there passes green.
    static func cachedFormatterIdentityForTesting(style: HourStyle) -> ObjectIdentifier {
        ObjectIdentifier(cache.formatter(for: style))
    }

    /// Drop the cached pair, as the locale-change notification does.
    static func invalidateCacheForTesting() {
        cache.invalidate()
    }
    #endif
}
