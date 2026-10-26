import Foundation

/// The one place that decides which locale user-facing formatters run in.
///
/// Before #569 twelve formatters each built their own
/// `Locale(identifier: "ru_RU")`, so "show dates and numbers in the user's
/// language" was a twelve-file change and nobody could tell which of the
/// hardcoded locales were deliberate. Regional formatting now follows the
/// user; text and noun rules follow the supported app language separately.
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
    /// This retains regional preferences such as the hour cycle even when the
    /// app has a different language override. Wallet currency is separate.
    static let display = Locale.autoupdatingCurrent

    /// Noun rules follow the app's negotiated text language, not its region.
    /// iOS includes the per-app language override in preferredLocalizations.
    /// A language change takes effect on the next normal process launch.
    static let text = textLocale(for: Bundle.main.preferredLocalizations)

    /// Shared negotiation path for production and explicit language scenarios.
    /// Append the development language after ALL preferences: [de, ru] must
    /// choose ru, while an unsupported-only preference falls back to en.
    static func textLocale(for preferences: [String], in bundle: Bundle = .main) -> Locale {
        let fallback = bundle.developmentLocalization ?? "en"
        let supported = bundle.localizations.filter { $0 != "Base" }
        let language = Bundle.preferredLocalizations(
            from: supported, forPreferences: preferences + [fallback]
        ).first ?? fallback
        return Locale(identifier: language)
    }

    /// String-format plural variations need the text language, while numeric
    /// substitutions retain the user's region and explicit locale preferences.
    /// Passing display alone would apply Russian plural rules to English copy
    /// under an EN app override on a Russian-region device (21 "minute").
    static func textFormattingLocale(
        textLocale: Locale = AppLocale.text, regionalLocale: Locale = AppLocale.display
    ) -> Locale {
        var components = Locale.Components(locale: regionalLocale)
        components.languageComponents.languageCode = textLocale.language.languageCode
        components.languageComponents.script = textLocale.language.script
        return Locale(components: components)
    }
}
