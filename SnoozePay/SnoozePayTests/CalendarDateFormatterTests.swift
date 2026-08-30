import XCTest
@testable import SnoozePay

/// Unit tests for `CalendarDateFormatter` — the skeleton-driven replacement
/// for the literal date patterns `"d MMMM"` and `"EEE · d MMM"` (#654).
///
/// Two things need pinning, and they pull in opposite directions:
///
/// 1. **Nothing moves today.** The app ships `ru_RU` only, so every assertion
///    on the current locale compares against the *observed* output of the
///    literal pattern that was replaced, built right here in the test. A
///    hand-typed «12 января» would prove the string is what someone believed
///    on a Tuesday; the baseline proves it is what the old code produced.
/// 2. **The order is no longer frozen.** A test on one locale cannot tell a
///    fix from a regression — `ru_RU` renders identically either way — so the
///    order assertions run on `en_US`, where the fields swap, and check the
///    *positions* of the fields rather than a spelled-out string.
final class CalendarDateFormatterTests: XCTestCase {

    /// Fixed calendar so a date literal means one instant regardless of where
    /// CI runs, and so the day boundary cannot drift under the assertions.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // Not `?? .current`: a fallback to the runner's zone would silently
        // change which day the instant belongs to, and the resulting failure
        // would read as «the formatter broke» rather than «the fixture did».
        // Same call `WallClockFormatter` makes, for the same reason.
        guard let gmt = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("GMT is not constructible — Foundation is broken")
        }
        calendar.timeZone = gmt
        return calendar
    }()

    private let russian = Locale(identifier: "ru_RU")
    private let american = Locale(identifier: "en_US")

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour)
        return try XCTUnwrap(calendar.date(from: components))
    }

    /// The formatter the production code used to build by hand — the baseline
    /// every "nothing moved" assertion is measured against.
    private func literal(_ pattern: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter
    }

    private func symbols(for locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter
    }

    // MARK: - The Russian rendering did not move

    func testDayMonthRendersWhatTheLiteralPatternRendered() throws {
        let day = try date(year: 2026, month: 1, day: 12)
        XCTAssertEqual(
            CalendarDateFormatter.string(from: day, style: .dayMonth, locale: russian, calendar: calendar),
            literal("d MMMM", locale: russian).string(from: day),
            "wallet day header changed shape under ru_RU"
        )
    }

    func testDayMonthShortRendersWhatTheLiteralPatternRendered() throws {
        let day = try date(year: 2026, month: 1, day: 12)
        XCTAssertEqual(
            CalendarDateFormatter.string(from: day, style: .dayMonthShort, locale: russian, calendar: calendar),
            literal("d MMM", locale: russian).string(from: day),
            "transaction timestamp changed shape under ru_RU"
        )
    }

    /// The firing screen's top bar. The weekday moved from the formatting form
    /// (`EEE`) to the standalone one (`ccc`, what the `E` skeleton resolves
    /// to), which is the linguistically right call for a weekday standing
    /// apart from its date — and a no-op in Russian, where the two symbol sets
    /// are identical. The second assertion says so out loud: if CLDR ever
    /// splits them, the equality above fails for a *reason*, not mysteriously.
    func testWeekdayAndDayMonthRendersWhatTheFiringScreenRendered() throws {
        let day = try date(year: 2026, month: 4, day: 27)
        XCTAssertEqual(
            CalendarDateFormatter.weekdayAndDayMonthShort(from: day, locale: russian, calendar: calendar),
            literal("EEE · d MMM", locale: russian).string(from: day),
            "firing top-bar date changed shape under ru_RU"
        )
        let russianSymbols = symbols(for: russian)
        XCTAssertEqual(
            russianSymbols.shortWeekdaySymbols,
            russianSymbols.shortStandaloneWeekdaySymbols,
            "ru_RU weekday forms diverged — the assertion above is now a real behaviour change"
        )
    }

    func testTheDesignSeparatorSurvivesTheLocalesOwnPunctuation() throws {
        let day = try date(year: 2026, month: 4, day: 27)
        let rendered = CalendarDateFormatter.weekdayAndDayMonthShort(from: day, locale: russian, calendar: calendar)
        XCTAssertTrue(rendered.contains(" · "), "artboard separator lost: \(rendered)")
        // The locale's own combined skeleton would have supplied a comma; the
        // whole point of composing the halves by hand is that it does not.
        XCTAssertFalse(rendered.contains(","), "locale punctuation leaked into the design separator: \(rendered)")
    }

    // MARK: - The field order now follows the locale

    /// `en_US` writes the month first. The literal pattern could not: it spelled
    /// day-before-month for everyone. Both halves are asserted — that the new
    /// output puts the month first, and that the pattern it replaced did not —
    /// because only the pair distinguishes a fix from a coincidence.
    func testDayMonthOrderIsTheLocalesUnderAmericanEnglish() throws {
        let day = try date(year: 2026, month: 1, day: 12)
        let monthName = try XCTUnwrap(symbols(for: american).monthSymbols.first)

        let localized = CalendarDateFormatter.string(
            from: day, style: .dayMonth, locale: american, calendar: calendar
        )
        let monthPosition = try XCTUnwrap(localized.range(of: monthName)?.lowerBound)
        let dayPosition = try XCTUnwrap(localized.range(of: "12")?.lowerBound)
        XCTAssertLessThan(monthPosition, dayPosition, "en_US reads month-first: \(localized)")

        let frozen = literal("d MMMM", locale: american).string(from: day)
        let frozenMonth = try XCTUnwrap(frozen.range(of: monthName)?.lowerBound)
        let frozenDay = try XCTUnwrap(frozen.range(of: "12")?.lowerBound)
        XCTAssertLessThan(frozenDay, frozenMonth, "the literal pattern was supposed to be day-first: \(frozen)")
    }

    /// The same date under the two locales, to make the point that the type is
    /// doing the reordering rather than one locale happening to agree with the
    /// old pattern.
    func testTheTwoLocalesDisagreeAboutTheOrder() throws {
        let day = try date(year: 2026, month: 1, day: 12)
        let inRussian = CalendarDateFormatter.string(from: day, style: .dayMonth, locale: russian, calendar: calendar)
        let inEnglish = CalendarDateFormatter.string(from: day, style: .dayMonth, locale: american, calendar: calendar)
        XCTAssertTrue(inRussian.hasPrefix("12"), "ru_RU reads day-first: \(inRussian)")
        XCTAssertFalse(inEnglish.hasPrefix("12"), "en_US does not read day-first: \(inEnglish)")
    }

    // MARK: - MMM (formatting) vs LLL (standalone)

    /// Russian declines the month: «12 января» next to a day number, «январь»
    /// on its own. `MMMM` gives the first, `LLLL` the second, and mixing them
    /// up is invisible in English.
    func testDayMonthUsesTheGenitiveMonthAndLoneCaptionsUseTheNominative() throws {
        let january = try date(year: 2026, month: 1, day: 12)
        let russianSymbols = symbols(for: russian)
        let formatting = try XCTUnwrap(russianSymbols.monthSymbols.first)          // «января»
        let standalone = try XCTUnwrap(russianSymbols.standaloneMonthSymbols.first) // «январь»
        XCTAssertNotEqual(
            formatting, standalone,
            "ru_RU stopped declining month names — the rest of this test proves nothing"
        )

        let rendered = CalendarDateFormatter.string(
            from: january, style: .dayMonth, locale: russian, calendar: calendar
        )
        XCTAssertTrue(rendered.contains(formatting), "a date needs the genitive month: \(rendered)")
        XCTAssertFalse(rendered.contains(standalone), "a date must not use the nominative: \(rendered)")

        // The other half of the same coin, and the reason lone month captions
        // are NOT built from a date pattern: a literal `MMMM` on its own still
        // renders the genitive, so «января 2026» is what a naive caption gets.
        XCTAssertEqual(literal("MMMM", locale: russian).string(from: january), formatting)
        XCTAssertTrue(
            YearMonth(year: 2026, month: 1).fullCaption.hasPrefix(standalone),
            "the period caption must stay nominative: \(YearMonth(year: 2026, month: 1).fullCaption)"
        )
    }

    // MARK: - The failure mode this type has to avoid

    /// A skeleton that does not resolve leaves `dateFormat` empty and the
    /// formatter renders the EMPTY STRING — a blank group header, not a wrong
    /// date. Every style is exercised across the locales the app could
    /// plausibly switch to under #569, including two that reorder the fields
    /// and two that append their own punctuation.
    func testNoStyleRendersEmptyForAnyPlausibleLocale() throws {
        let day = try date(year: 2026, month: 1, day: 12)
        let styles: [CalendarDateFormatter.Style] = [.dayMonth, .dayMonthShort, .weekdayShort]
        for identifier in ["ru_RU", "en_US", "en_GB", "de_DE", "hu_HU", "ja_JP"] {
            let locale = Locale(identifier: identifier)
            for style in styles {
                let rendered = CalendarDateFormatter.string(
                    from: day, style: style, locale: locale, calendar: calendar
                )
                XCTAssertFalse(
                    rendered.isEmpty,
                    "\(style.skeleton) rendered nothing for \(identifier)"
                )
            }
        }
    }

    /// The calendar argument carries the time zone, and the time zone decides
    /// which day an instant falls on — so dropping it is not a detail.
    func testInjectedCalendarDecidesWhichDayTheInstantBelongsTo() throws {
        let lateEvening = try date(year: 2026, month: 1, day: 12, hour: 23)
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 3 * 3600))

        let utcDay = CalendarDateFormatter.string(
            from: lateEvening, style: .dayMonth, locale: russian, calendar: calendar
        )
        let easternDay = CalendarDateFormatter.string(
            from: lateEvening, style: .dayMonth, locale: russian, calendar: eastern
        )
        XCTAssertTrue(utcDay.hasPrefix("12"), "UTC still reads 12 January: \(utcDay)")
        XCTAssertTrue(easternDay.hasPrefix("13"), "UTC+3 has rolled into 13 January: \(easternDay)")
    }
}
