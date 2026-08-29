import Foundation

/// The CLDR plural categories this app needs. Russian uses all three; a
/// two-form language such as English maps `few` onto the same string as
/// `many`, which is why `PluralForms` lets `few` default to `many`.
enum PluralCategory: Equatable {
    case one
    case few
    case many
}

/// The forms of one noun, as **data** rather than as a `switch` in code.
///
/// This is the half of #569 that makes English possible: call sites ask for
/// "the form for N", never for "the Russian form", so adding a language means
/// adding forms to `Localizable.xcstrings` without touching a single caller.
/// The literal initialiser below stays for tests and for forms that are built
/// rather than read.
struct PluralForms {
    let one: String
    let few: String
    let many: String

    /// - Parameters:
    ///   - one: form for 1, 21, 31 … ("день").
    ///   - few: form for 2-4, 22-24 … ("дня"). Defaults to `many` for
    ///     languages that do not distinguish it.
    ///   - many: form for 0, 5-20, 11-14 … ("дней").
    init(one: String, few: String? = nil, many: String) {
        self.one = one
        self.few = few ?? many
        self.many = many
    }

    func form(_ category: PluralCategory) -> String {
        switch category {
        case .one: return one
        case .few: return few
        case .many: return many
        }
    }
}

/// One implementation of the plural rule, replacing the seven copies that
/// #569 found (`StatisticsViewModel`, `StatisticsViewModel+Money`,
/// `StreakModalViewController`, `WokeMorningContent`, `AlarmsStreakBannerView`,
/// `DepositPresets`, `SnoozeAffordability`).
///
/// The copies were not identical: five ignored the sign of `count`, so a
/// negative number picked the wrong form, and two normalised it. The
/// normalising behaviour (`SnoozeAffordability`, #546) wins here — the count in
/// every call site is a magnitude ("N snoozes", "N days"), and a minus sign in
/// front of it is a bug in the caller, not a request for a different
/// declension.
enum Plural {

    /// The category `count` falls into for `locale`.
    ///
    /// Russian: `one` for n%10==1 except n%100==11; `few` for n%10 in 2…4
    /// except n%100 in 12…14; `many` otherwise (including 0). Any other
    /// language gets the two-form rule (`one` for 1, `many` for the rest),
    /// which is correct for English and the safe default elsewhere.
    static func category(for count: Int, locale: Locale = AppLocale.display) -> PluralCategory {
        let magnitude = abs(count)
        guard locale.language.languageCode?.identifier == "ru" else {
            return magnitude == 1 ? .one : .many
        }
        let mod10 = magnitude % 10
        let mod100 = magnitude % 100
        if mod10 == 1 && mod100 != 11 { return .one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return .few }
        return .many
    }

    /// The form of `forms` that goes after `count`.
    static func word(_ count: Int, _ forms: PluralForms, locale: Locale = AppLocale.display) -> String {
        forms.form(category(for: count, locale: locale))
    }
}

extension PluralForms {

    /// Reads the three forms of `catalogKey` out of `Localizable.xcstrings`.
    ///
    /// The catalogue stores them as three top-level keys — `<catalogKey>.one`,
    /// `.few`, `.many` — rather than one entry with `Variations → Plural`,
    /// because `xcstringstool` rejects a plural variation whose value does not
    /// contain the number, and these values are bare nouns; the count is
    /// rendered by the call site. ``Localized`` carries the tool's own wording.
    ///
    /// `.few` is looked up as optional so a two-form language can simply omit
    /// it and inherit `many`, which is the behaviour `init(one:few:many:)`
    /// already promises.
    init(catalogKey: String) {
        self.init(
            one: Localized.text("\(catalogKey).one"),
            few: Localized.optionalText("\(catalogKey).few"),
            many: Localized.text("\(catalogKey).many")
        )
    }
}

/// The nouns the UI pluralises.
///
/// The Russian words themselves are **not here** — they live in
/// `Resources/Localizable.xcstrings`, which is the half of #569 that lets
/// English arrive as a catalogue edit rather than a Swift edit. What remains in
/// code is the mapping from a call site to a catalogue key.
///
/// These are computed rather than `static let` on purpose: a stored property
/// would freeze the copy at first access, which is fine in the app but hides
/// catalogue misses behind whichever test ran first.
extension PluralForms {

    /// "1 день / 2 дня / 5 дней" — streak length.
    static var days: PluralForms { PluralForms(catalogKey: "plural.days") }

    /// "1 откладывание / 2 откладывания / 5 откладываний" — nominative, the
    /// form used when the numeral is the subject ("≈ 3 откладывания").
    static var snoozes: PluralForms { PluralForms(catalogKey: "plural.snoozes") }

    /// Genitive of the same noun, governed by «после»: "после 1 откладывания",
    /// "после 2 откладываний". The preposition forces the genitive throughout,
    /// so 2-4 collapses onto the many form — deliberately different from
    /// `snoozes`, not a copy that drifted. The catalogue spells `.few` out
    /// instead of omitting it, so that the collapse stays visible to whoever
    /// translates the file next.
    static var snoozesAfter: PluralForms { PluralForms(catalogKey: "plural.snoozes_after") }

    /// "1 утро / 2 утра / 5 утр" — mornings of collected wake-time history.
    static var mornings: PluralForms { PluralForms(catalogKey: "plural.mornings") }
}
