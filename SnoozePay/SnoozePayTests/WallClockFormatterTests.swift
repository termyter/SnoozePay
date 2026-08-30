import XCTest
@testable import SnoozePay

/// Unit tests for ``WallClockFormatter`` and the wake-time clock that feeds it
/// (#628).
///
/// Every case pins the locale explicitly. A test that reads the runner's locale
/// cannot tell a fix from a regression here — the CI runner is 24-hour, so the
/// broken hardcoded `HH:mm` and the correct locale-driven pattern produce the
/// same string on it, and the bug would sail through green.
///
/// The 12-hour locale is deliberately **`ru_RU` with an hour-cycle override**
/// rather than `en_US`: the point of the issue is that am/pm is a *regional*
/// setting, not a language one, and a Russian-speaking user who turns off
/// «24-часовой формат» in iOS Settings is exactly the reader who was broken.
/// `en_US` is covered too, as the ordinary case.
final class WallClockFormatterTests: XCTestCase {

    // MARK: - Locales under test

    private let ru24 = Locale(identifier: "ru_RU")
    private let en12 = Locale(identifier: "en_US")

    /// `ru_RU` forced to a 12-hour clock, the way iOS Settings does it.
    private var ru12: Locale {
        var components = Locale.Components(identifier: "ru_RU")
        components.hourCycle = .oneToTwelve
        return Locale(components: components)
    }

    /// `en_US` forced to a 24-hour clock — the mirror case, proving the width
    /// rule below applies to whichever locale happens to be on 24 hours rather
    /// than to Russian specifically.
    private var en24: Locale {
        var components = Locale.Components(identifier: "en_US")
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    // MARK: - 24-hour reading

    func testTwentyFourHourLocaleKeepsTheHourWidthOfTheDesign() {
        XCTAssertEqual(padded(hour: 7, minute: 4, locale: ru24), "07:04")
        XCTAssertEqual(compact(hour: 7, minute: 4, locale: ru24), "7:04")
        XCTAssertEqual(padded(hour: 19, minute: 5, locale: ru24), "19:05")
        XCTAssertEqual(compact(hour: 19, minute: 5, locale: ru24), "19:05")
    }

    /// The width rule follows the hour cycle, not the language: `en_US` on a
    /// 24-hour setting renders like `ru_RU`, padding and all.
    func testWidthRuleFollowsTheCycleNotTheLanguage() {
        XCTAssertEqual(padded(hour: 7, minute: 4, locale: en24), "07:04")
        XCTAssertEqual(compact(hour: 7, minute: 4, locale: en24), "7:04")
    }

    /// The shipping locale renders byte for byte what the hardcoded `HH:mm` /
    /// `String(format: "%d:%02d", …)` did. #628 changes who *decides* the
    /// format, and deliberately changes nothing about today's output.
    func testShippingLocaleOutputIsUnchangedByTheFix() {
        XCTAssertEqual(padded(hour: 0, minute: 0, locale: ru24), "00:00")
        XCTAssertEqual(compact(hour: 0, minute: 0, locale: ru24), "0:00")
        XCTAssertEqual(padded(hour: 23, minute: 59, locale: ru24), "23:59")
        XCTAssertEqual(compact(hour: 23, minute: 59, locale: ru24), "23:59")
    }

    // MARK: - 12-hour reading

    func testTwelveHourLocaleRendersMeridiem() {
        XCTAssertEqual(normalised(padded(hour: 19, minute: 5, locale: en12)), "7:05 PM")
        XCTAssertEqual(normalised(padded(hour: 7, minute: 4, locale: en12)), "7:04 AM")
        XCTAssertEqual(normalised(padded(hour: 0, minute: 0, locale: en12)), "12:00 AM")
        XCTAssertEqual(normalised(padded(hour: 23, minute: 59, locale: en12)), "11:59 PM")
    }

    /// The regression the issue is actually about: a Russian interface on a
    /// 12-hour region. Before the fix this rendered "19:05".
    func testRussianLocaleOnTwelveHourRegionRendersMeridiem() {
        XCTAssertEqual(normalised(padded(hour: 19, minute: 5, locale: ru12)), "7:05 PM")
        XCTAssertEqual(normalised(compact(hour: 7, minute: 4, locale: ru12)), "7:04 AM")
    }

    /// Hour width is a 24-hour-only choice. "07:04 AM" is not a form English
    /// writes, so on a 12-hour locale both styles defer to the locale and come
    /// out identical.
    func testHourWidthIsIgnoredOnTwelveHourLocales() {
        XCTAssertEqual(
            padded(hour: 7, minute: 4, locale: en12),
            compact(hour: 7, minute: 4, locale: en12)
        )
        XCTAssertEqual(
            padded(hour: 7, minute: 4, locale: ru12),
            compact(hour: 7, minute: 4, locale: ru12)
        )
    }

    /// The meridiem separator is U+202F (narrow no-break space), not U+0020 —
    /// asserting against a plain " PM" would fail on a correct string. The
    /// other tests normalise it away; this one pins the fact so the normaliser
    /// is not mistaken for decoration.
    func testMeridiemSeparatorIsNotAPlainSpace() {
        let text = padded(hour: 19, minute: 5, locale: en12)
        XCTAssertFalse(text.contains(" PM"), "expected a non-breaking separator, got \(scalars(text))")
        XCTAssertTrue(text.hasSuffix("PM"), scalars(text))
        let separator = text.unicodeScalars.first { CharacterSet.whitespaces.contains($0) }
        XCTAssertNotNil(separator, scalars(text))
        XCTAssertNotEqual(separator?.value, 0x20, scalars(text))
    }

    // MARK: - Minutes since midnight

    func testMinutesSinceMidnightFollowsTheReadersHourCycle() {
        XCTAssertEqual(
            WallClockFormatter.string(minutesSinceMidnight: 19 * 60 + 5, style: .compact, locale: ru24),
            "19:05"
        )
        XCTAssertEqual(
            normalised(WallClockFormatter.string(
                minutesSinceMidnight: 19 * 60 + 5, style: .compact, locale: ru12
            )),
            "7:05 PM"
        )
    }

    /// Out-of-range offsets are clamped into the day rather than wrapping. The
    /// arithmetic version rendered 1500 as "25:00"; a bare `DateFormatter`
    /// would wrap it to the next day's "1:00", which reads as a plausible but
    /// wrong time.
    func testMinutesSinceMidnightClampsInsteadOfWrapping() {
        XCTAssertEqual(
            WallClockFormatter.string(minutesSinceMidnight: 25 * 60, style: .compact, locale: ru24),
            "23:59"
        )
        XCTAssertEqual(
            WallClockFormatter.string(minutesSinceMidnight: -30, style: .compact, locale: ru24),
            "0:00"
        )
    }

    // MARK: - The statistics wake-time clock (the reported call site)

    func testClockTextFollowsTheReadersHourCycle() {
        XCTAssertEqual(StatisticsViewModel.clockText(minutes: 7 * 60 + 4, locale: ru24), "7:04")
        XCTAssertEqual(StatisticsViewModel.clockText(minutes: 19 * 60 + 5, locale: ru24), "19:05")
        XCTAssertEqual(
            normalised(StatisticsViewModel.clockText(minutes: 19 * 60 + 5, locale: ru12)),
            "7:05 PM"
        )
        XCTAssertEqual(
            normalised(StatisticsViewModel.clockText(minutes: 7 * 60 + 4, locale: en12)),
            "7:04 AM"
        )
    }

    /// The default argument still resolves through ``AppLocale/display``, so
    /// the card reads the same as before the change until #569 flips `display`.
    func testClockTextDefaultsToTheAppDisplayLocale() {
        XCTAssertEqual(
            StatisticsViewModel.clockText(minutes: 7 * 60 + 4),
            StatisticsViewModel.clockText(minutes: 7 * 60 + 4, locale: AppLocale.display)
        )
    }

    // MARK: - Helpers

    private func padded(hour: Int, minute: Int, locale: Locale) -> String {
        render(hour: hour, minute: minute, style: .padded, locale: locale)
    }

    private func compact(hour: Int, minute: Int, locale: Locale) -> String {
        render(hour: hour, minute: minute, style: .compact, locale: locale)
    }

    // MARK: - The cached branch

    /// Every other test in this file injects a locale AND a calendar, which
    /// routes it past the cache into `makeFormatter`. That means the two
    /// cached formatters — the ONLY ones production uses on the hot paths (the
    /// alarms list once per cell, the firing screen once a second) — were
    /// executed by no test at all, and a regression in them would pass green.
    /// These three cases exist to close that hole, not to re-check formatting.

    func testDefaultLocalePath_rendersThroughTheCache() {
        // No locale, no calendar → the cached branch. Asserted on the shape
        // rather than an exact string, because the value depends on the
        // runner's zone; the point is that the cached formatter produces a
        // real clock and not the empty string a failed resolve would give.
        let rendered = WallClockFormatter.string(from: Date(), style: .padded)
        XCTAssertFalse(rendered.isEmpty,
                       "The cached formatter must not render an empty clock")
        XCTAssertTrue(rendered.contains(":") || rendered.contains("."),
                      "Expected a wall clock with a separator, got «\(rendered)»")
    }

    func testInvalidate_rebuildsTheCachedFormatter() {
        let before = WallClockFormatter.cachedFormatterIdentityForTesting(style: .padded)
        XCTAssertEqual(before,
                       WallClockFormatter.cachedFormatterIdentityForTesting(style: .padded),
                       "Without an invalidation the cache must return the same instance")

        WallClockFormatter.invalidateCacheForTesting()

        XCTAssertNotEqual(before,
                          WallClockFormatter.cachedFormatterIdentityForTesting(style: .padded),
                          "After invalidation the formatter must be rebuilt")
    }

    /// The one that guards the actual bug. `setLocalizedDateFormatFromTemplate`
    /// resolves `jm` ONCE and writes a literal pattern; the formatter never
    /// consults the locale again. And the cache guard cannot notice a change,
    /// because `Locale.autoupdatingCurrent == Locale.autoupdatingCurrent` is
    /// `true`. So without this notification hook, the day #569/#603 points
    /// `AppLocale.display` at `.autoupdatingCurrent`, a reader toggling
    /// «24-Hour Time» would keep seeing the old cycle until an app restart —
    /// #628 reopened through the cache.
    func testLocaleChangeNotification_rebuildsTheCachedFormatter() {
        let before = WallClockFormatter.cachedFormatterIdentityForTesting(style: .compact)

        NotificationCenter.default.post(
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )

        // The observer runs synchronously on the posting thread, so no wait is
        // needed — and adding one would hide a broken observer behind a sleep.
        XCTAssertNotEqual(before,
                          WallClockFormatter.cachedFormatterIdentityForTesting(style: .compact),
                          "A locale change must drop the frozen pattern (#628 via the cache)")
    }

    /// The instant is built in UTC and the formatter is handed the *same* UTC
    /// calendar, so the rendered hour is the one written at the call site no
    /// matter which zone the runner sits in.
    private func render(
        hour: Int,
        minute: Int,
        style: WallClockFormatter.HourStyle,
        locale: Locale
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: 2026, month: 1, day: 27, hour: hour, minute: minute)
        let date = calendar.date(from: components)!
        return WallClockFormatter.string(from: date, style: style, locale: locale, calendar: calendar)
    }

    /// Collapses every Unicode space — `DateFormatter` emits U+202F before the
    /// meridiem, and ICU has changed which space it picks between OS releases.
    /// Comparing normalised text asserts the reading without pinning a
    /// codepoint Apple is free to swap.
    private func normalised(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.whitespaces.contains($0) ? " " : $0
        }))
    }

    private func scalars(_ text: String) -> String {
        text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }
}
