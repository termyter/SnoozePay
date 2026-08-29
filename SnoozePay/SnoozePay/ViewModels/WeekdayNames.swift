import Foundation

/// Monday-first weekday names for ``AppLocale/display``, read from the
/// calendar rather than from `Localizable.xcstrings`.
///
/// # Why these are not catalogue strings (#569)
///
/// The seven hand-written `["Пн", "Вт", …]` arrays this replaces looked like
/// copy, but a weekday name is calendar data: every locale ships its own set
/// with CLDR, and a translator asked to supply them would be retyping a table
/// the system already has. The same reasoning the epic applies to date
/// *formats* — locale-dependent behaviour, not text to translate — applies to
/// the symbols those formats are built from.
///
/// The substitution is exact for Russian, which is the point: Foundation's
/// `ru_RU` standalone symbols are `["Вс", "Пн", …]` and
/// `["воскресенье", "понедельник", …]`, matching the design copy character for
/// character once rotated Monday-first. Nothing on screen moves; English
/// arrives for free.
///
/// Copy that *contains* a weekday («Будни · Пн–Пт») stays in the catalogue as
/// one whole string — assembling it from these would freeze Russian word order
/// (`Localized`'s second substitution rule).
enum WeekdayNames {

    /// Abbreviated names, Monday-first: `Пн Вт Ср Чт Пт Сб Вс`.
    ///
    /// Standalone (rather than format) symbols, because these label a column
    /// header or a chip and are never part of a date phrase — the distinction
    /// matters in languages that decline, and Russian is one of them.
    ///
    /// Stored rather than computed: a `DateFormatter` costs about a
    /// millisecond to build and `weekdayStats` reads this once per bar.
    /// Catalogue copy stays computed for the opposite reason (``Plural``) — a
    /// missing key must not hide behind whichever test ran first — but these
    /// come from the system and cannot go missing.
    static let short: [String] = mondayFirst(\.shortStandaloneWeekdaySymbols)

    /// Full lowercase names, Monday-first: `понедельник … воскресенье`.
    /// Lowercase is what the locale hands back; call sites that start a
    /// sentence with one capitalize it themselves.
    static let full: [String] = mondayFirst(\.standaloneWeekdaySymbols)

    /// One symbol array from ``AppLocale/display``, rotated Monday-first.
    private static func mondayFirst(_ symbols: KeyPath<DateFormatter, [String]?>) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.display
        // Foundation hands these back Sunday-first (index 0 = Sunday); the
        // whole app is Monday-first, so Sunday moves to the back.
        guard let sundayFirst = formatter[keyPath: symbols], sundayFirst.count == 7 else {
            return []
        }
        return Array(sundayFirst.dropFirst()) + [sundayFirst[0]]
    }
}
