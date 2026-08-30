import Foundation
import os

/// The one place that renders a **calendar date** — a day, a month, a weekday
/// — for a human to read.
///
/// Sibling of `WallClockFormatter` (#628, PR #651 — the two may land in
/// either order), which does the same job for the time of day; the defect is
/// a different one. There it was the *hour cycle*,
/// here it is the *order and form of the fields*. Four call sites wrote the
/// pattern out by hand — `"d MMMM"` for the wallet's day header, `"EEE · d MMM"`
/// for the firing screen — and a literal `dateFormat` freezes day-before-month
/// for every reader. That order is a property of the locale, not of the app:
/// `ru_RU` writes «12 января», `en_US` writes "January 12", `hu_HU` writes
/// "január 12.", `ja_JP` writes 1月12日 — same fields, three different orders
/// and two different sets of punctuation.
///
/// The pattern therefore comes from a *skeleton* — "a day and a month, however
/// this locale puts them" — and ICU resolves the order, the separator and the
/// trailing dots. Today ``AppLocale/display`` is pinned `ru_RU`, where the
/// skeletons resolve to exactly the patterns that were hardcoded, so **nothing
/// on screen moves**; the day #569 flips `display` to `.autoupdatingCurrent`,
/// every date in the app follows without being touched again.
///
/// ⚠️ **`MMM` and `LLL` are not the same month.** `MMM`/`MMMM` is the
/// *formatting* form — the one that belongs next to a day number, and in
/// Russian that means the genitive: «12 января». `LLL`/`LLLL` is the
/// *standalone* form, the nominative «январь», and it is what a lone month
/// caption needs. Getting it backwards is invisible in English and wrong in
/// Russian, which is how it was worth calling out in #599 and again here.
/// The skeletons below do the right thing on both counts, and ICU is the one
/// that picks: a `"MMMM"` template with nothing else in it resolves to `LLLL`
/// (verified — «январь»), while the literal pattern `"MMMM"` renders «января».
/// That asymmetry is exactly why lone month captions go through
/// `YearMonth.fullNames` (`standaloneMonthSymbols`) and not through a
/// hand-written pattern; `WalletHistoryLocalizationTests` pins it.
///
/// ⚠️ **Durations and machine formats do not come here.** Anything that
/// *parses* a fixed string keeps `en_US_POSIX` and its literal pattern — see
/// the note in `AppLocale`.
enum CalendarDateFormatter {

    /// Which fields the caller wants. Not "which pattern" — the pattern is the
    /// locale's business.
    enum Style {
        /// «12 января» / "January 12" / "12. Januar" — day + full month.
        case dayMonth
        /// «12 янв.» / "Jan 12" / "12. Jan." — day + abbreviated month.
        case dayMonthShort
        /// «Пт» / "Fri" — abbreviated weekday on its own.
        ///
        /// Resolves to `ccc`, the *standalone* weekday, because that is what a
        /// weekday detached from its date is. In `ru_RU` the standalone and
        /// formatting symbols are identical («Пн»…«Вс», verified), so the
        /// firing screen renders what it rendered before.
        case weekdayShort

        /// The ICU skeleton — field content only, no order and no punctuation.
        var skeleton: String {
            switch self {
            case .dayMonth: return "dMMMM"
            case .dayMonthShort: return "dMMM"
            case .weekdayShort: return "E"
            }
        }
    }

    // MARK: - Formatting

    /// Renders `date` with the fields of `style`, ordered by `locale`.
    ///
    /// Pass `calendar` when the caller has one — it also supplies the time
    /// zone, which decides *which day* an instant falls on and is therefore
    /// not optional detail for a date. Without one the formatter uses the
    /// current calendar, as the hand-rolled formatters it replaces did.
    static func string(
        from date: Date,
        style: Style,
        locale: Locale = AppLocale.display,
        calendar: Calendar? = nil
    ) -> String {
        let rendered = makeFormatter(
            style: style, locale: locale, calendar: calendar
        ).string(from: date)
        // Checked on the RESULT, not on `dateFormat`. The pattern is a proxy
        // for the symptom, and the proxy is loose in both directions: a
        // locale with no CLDR data (`root`, `""`) resolves `dMMMM` to a
        // perfectly non-empty `MMMM d` and then renders the raw ICU
        // placeholder «M01 12», which a pattern check waves through. Watching
        // what actually leaves the function is the only check that matches
        // what a reader would see.
        //
        // No `assertionFailure`: `testNoStyleRendersEmptyForAnyPlausibleLocale`
        // sweeps every locale on the runner precisely to find this, and a trap
        // here would SIGTRAP the test host — the 1034-test suite would report a
        // nameless crash instead of naming the locale that broke.
        if rendered.isEmpty {
            AppLogger.ui.fault(
                """
                CalendarDateFormatter: \(style.skeleton, privacy: .public) rendered \
                nothing for \(locale.identifier, privacy: .public)
                """
            )
        }
        return rendered
    }

    /// «Пт · 27 апр.» — the firing screen's top-bar date (artboard,
    /// `SPScreensV2.jsx` L64).
    ///
    /// The two halves are resolved separately and joined by hand, and that is
    /// a deliberate trade rather than an oversight:
    ///
    /// - The `« · »` separator and the weekday-first order are **design**, not
    ///   language. The locale's own combined skeleton (`EEEdMMM`) would supply
    ///   its own punctuation — `ru_RU` resolves it to `ccc, d MMM`, i.e. a
    ///   comma — and the middle dot the artboard specifies would be gone.
    /// - What the locale *does* still decide is everything inside each half:
    ///   day-before-month or month-before-day, the abbreviation, the trailing
    ///   dot. That is the bug this file exists to fix, and it is fixed here.
    ///
    /// The cost is that locales putting the weekday last (`hu_HU`:
    /// "ápr. 27., H") read slightly foreign. That is a known deviation, worth
    /// revisiting when #569 actually ships a second language — not worth
    /// dropping a specified design element for today.
    static func weekdayAndDayMonthShort(
        from date: Date,
        separator: String = " · ",
        locale: Locale = AppLocale.display,
        calendar: Calendar? = nil
    ) -> String {
        let weekday = string(from: date, style: .weekdayShort, locale: locale, calendar: calendar)
        let dayMonth = string(from: date, style: .dayMonthShort, locale: locale, calendar: calendar)
        return weekday + separator + dayMonth
    }

    // MARK: - Private

    /// Built per call, on purpose.
    ///
    /// `DateFormatter` construction costs ~1ms and the sibling
    /// `WallClockFormatter` caches for that reason — but its call sites tick
    /// once a second. These do not: one string per firing screen, one per day
    /// group of the transaction history. A cache here would buy microseconds
    /// and cost the thing that matters — `setLocalizedDateFormatFromTemplate`
    /// resolves the skeleton ONCE and writes a literal pattern into
    /// `dateFormat`, so a cached formatter latches the locale it was born with
    /// and keeps rendering the old field order after the reader changes their
    /// region. Not caching cannot get that wrong.
    private static func makeFormatter(style: Style, locale: Locale, calendar: Calendar?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        if let calendar {
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
        }
        // The locale has to be set first: the template resolves against
        // whatever is on the formatter at the moment of the call.
        formatter.setLocalizedDateFormatFromTemplate(style.skeleton)
        // No fallback pattern, and no `.medium` either. `.medium` looked
        // defensible — it is the locale's own ordering, not a guessed literal —
        // but it answers a different question than the caller asked: `E` means
        // «weekday», and `.medium` returns the full date. The firing screen,
        // which joins the two halves by hand, would have rendered
        // «27 АПР. 2026 Г. · 27 АПР.» — plausible, duplicated and wrong, with
        // the weekday simply gone. `WallClockFormatter` faced this exact choice
        // and refused a fallback for the same reason: a quiet plausible lie is
        // worse than a loud blank, which is what gets a ticket filed.
        //
        // The reader-visible check therefore lives in `string(from:…)`, on the
        // rendered string rather than on the pattern.
        return formatter
    }
}
