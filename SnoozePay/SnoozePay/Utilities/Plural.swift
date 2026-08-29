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
/// adding forms — here or, later, in the string catalogue — without touching a
/// single caller.
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

/// The nouns the UI pluralises. Russian copy lives here as data; when the
/// string catalogue lands (#569) these move into it unchanged in meaning.
extension PluralForms {

    /// "1 день / 2 дня / 5 дней" — streak length.
    static let days = PluralForms(one: "день", few: "дня", many: "дней")

    /// "1 откладывание / 2 откладывания / 5 откладываний" — nominative, the
    /// form used when the numeral is the subject ("≈ 3 откладывания").
    static let snoozes = PluralForms(
        one: "откладывание",
        few: "откладывания",
        many: "откладываний"
    )

    /// Genitive of the same noun, governed by «после»: "после 1 откладывания",
    /// "после 2 откладываний". The preposition forces the genitive throughout,
    /// so 2-4 collapses onto the many form — deliberately different from
    /// `snoozes`, not a copy that drifted.
    static let snoozesAfter = PluralForms(
        one: "откладывания",
        many: "откладываний"
    )

    /// "1 утро / 2 утра / 5 утр" — mornings of collected wake-time history.
    static let mornings = PluralForms(one: "утро", few: "утра", many: "утр")
}
