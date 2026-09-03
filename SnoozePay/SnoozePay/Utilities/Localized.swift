import Foundation
import os

/// Reads user-facing copy out of `Resources/Localizable.xcstrings`.
///
/// # Why not plain `String(localized:)`
///
/// `knownRegions` in `project.pbxproj` is `(en, Base)` and `developmentRegion`
/// is `en`, so the built app *declares* English while shipping Russian
/// (#596, PM's file). On a device whose preferred language is anything but
/// Russian, `Bundle.main` therefore negotiates its way to `Base.lproj` — which
/// holds two storyboards and no copy — and every `String(localized:)` quietly
/// returns the key. This type sidesteps the negotiation by opening the
/// `ru.lproj` bundle for ``AppLocale/display`` directly.
///
/// When #596 lands, ``bundle`` collapses to `.main` and call sites can move to
/// `String(localized:)` verbatim; that is the only reason this indirection
/// exists, and it is why call sites pass bare keys and nothing else.
///
/// # Key naming convention
///
/// Migrating the 1107 literals of #569 is four issues (#598-#601) running in
/// parallel, so the convention has to be written down rather than inferred
/// from whoever committed first.
///
///     <domain>.<element>[.<qualifier>]
///
/// - Lowercase ASCII, `snake_case` inside a segment, `.` between segments,
///   two or three segments.
/// - `<domain>` is the screen or shared area the string belongs to:
///   `alarms`, `create_alarm`, `firing`, `woke_morning`, `statistics`,
///   `streak`, `referral`, `wallet`, `deposit`, `settings`, `onboarding`,
///   plus `common` and `plural` (see below).
/// - `common.*` is only for copy that appears on **two or more** screens
///   («Отмена», «Готово»). One screen means one domain, even if the word is
///   short.
///
/// Worked examples for the cases that otherwise get four different answers:
///
/// | kind | key | ru |
/// |---|---|---|
/// | section header | `statistics.section.streak` | «Серия» |
/// | button | `deposit.button.top_up` | «Пополнить» |
/// | error | `wallet.error.purchase_failed` | «Не удалось завершить покупку» |
/// | substitution | `statistics.saved_total` | «Сэкономлено %@ за %lld дн.» |
/// | plural noun | `plural.days.one` / `.few` / `.many` | «день» / «дня» / «дней» |
///
/// Two rules about substitutions, both of which cost a re-translation if
/// broken:
///
/// 1. Use positional specifiers (`%1$@`, `%2$lld`) as soon as there is more
///    than one, because a translator may need to reorder them.
/// 2. Never assemble a sentence from two keys. Word order is a property of the
///    language, not of the layout, and a concatenation freezes Russian order
///    into every future translation.
///
/// # Plurals
///
/// Nouns that follow a count live under `plural.<noun>.<category>` and are read
/// through ``PluralForms/init(catalogKey:)``. They are three separate top-level
/// keys rather than one entry with `Variations → Plural` because
/// `xcstringstool` refuses the latter for a value that does not contain the
/// number itself:
///
/// > error: Plural variation requires referencing the number in the string.
/// > To maintain grammatical correctness for strings that do not reference the
/// > number of items, use separate top-level strings for one and greater than
/// > one.
///
/// The call sites render `"\(count) \(word)"` and so own the number, leaving
/// the catalogue with a bare noun. `example.days_count` in the catalogue is the
/// shape to migrate *to* when a call site is rewritten to own the whole phrase
/// — at which point the language's own CLDR rule applies and ``Plural`` is no
/// longer in the loop.
///
/// # Editing the catalogue from several branches
///
/// `Localizable.xcstrings` is one JSON file with keys sorted alphabetically,
/// and #598-#601 all write to it. A conflict there is almost always two agents
/// adding different keys next to each other: resolve by **keeping both
/// entries**, never by taking one side wholesale.
enum Localized {

    /// The bundle that actually holds the compiled catalogue.
    ///
    /// Falls back to `.main` so that a missing `ru.lproj` surfaces as keys on
    /// screen and a red `LocalizableCatalogTests`, rather than a crash.
    static let bundle: Bundle = {
        guard
            let code = AppLocale.display.language.languageCode?.identifier,
            let path = Bundle.main.path(forResource: code, ofType: "lproj"),
            let localized = Bundle(path: path)
        else { return .main }
        return localized
    }()

    /// The copy for `key`, or `key` itself when the catalogue has no entry.
    ///
    /// Echoing the key is deliberate: it is loud on screen and trivial to
    /// assert on, whereas a Russian fallback baked into Swift would hide the
    /// miss forever. `LocalizableCatalogTests` is what turns it into a failure.
    static func text(_ key: String) -> String {
        optionalText(key) ?? key
    }

    /// The copy for `key`, or `nil` when the catalogue has no entry.
    ///
    /// Used for genuinely optional forms — a two-form language omits
    /// `plural.*.few` and expects the many form to stand in.
    static func optionalText(_ key: String) -> String? {
        // `localizedString(forKey:value:)` hands back `value` on a miss, so a
        // sentinel no copy can contain distinguishes "absent" from "present and
        // equal to the key".
        let sentinel = "\u{FFFF}"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
        return value == sentinel ? nil : value
    }

    /// The copy for `key` with `arguments` substituted, formatted for
    /// ``AppLocale/display``.
    ///
    /// A separate name rather than an overload of ``text(_:)``: `text("k")`
    /// would match both, and the rule that picks the non-variadic one is not
    /// something a reader should have to recall to be sure which ran.
    ///
    /// Formatting is skipped entirely when there is nothing to substitute, so a
    /// stray `%` in ordinary copy cannot be mistaken for a specifier.
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let template = optionalText(key) ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: AppLocale.display, arguments: arguments)
    }

    /// `key`'s copy with its **first** `%@` replaced by `replacement`, each
    /// side keeping its own attributes.
    ///
    /// Exists so a sentence containing a differently-styled run — a mono
    /// pain-tinted amount, a tinted weekday name — can stay **one** catalogue
    /// entry. Without it a call site reaches for a prefix literal, an `append`
    /// and a suffix literal, which is rule 2 of ``format(_:_:)`` above broken
    /// by the layout: it freezes Russian word order into every future
    /// translation, and a language that puts the amount first can no longer be
    /// expressed at all.
    ///
    /// ``format(_:_:)`` cannot serve here — it returns a plain `String`, so the
    /// substituted run would arrive flattened to the surrounding font.
    ///
    /// One specifier, by construction: there is a single `replacement` to
    /// spend, so a template holding two `%@` renders the second one literally.
    /// The per-slice localization tests assert the *count* and not merely the
    /// presence, so a translation that grows a second specifier goes red
    /// instead of printing a stray `%@` on screen.
    ///
    /// # Not the only idiom for this, and deliberately so
    ///
    /// `SnoozeSliderCell.valueText(_:)` solves the same sentence-shaped
    /// problem from the other end: it renders the whole phrase through
    /// ``format(_:_:)``, then *locates* the substituted fragment with
    /// `range(of:)` and restyles it in place. That idiom is older than this
    /// one and is not superseded by it — the two are not interchangeable:
    ///
    ///   * locate-and-restyle lays one **uniform** attribute set over the
    ///     range it found. `alarm_off.body` substitutes
    ///     `MoneyFormatter.attributed(_:)`, whose attributes are internally
    ///     *non*-uniform — digits in mono, the narrow space refonted, the ₽
    ///     sign its own run — which a single `addAttributes` cannot express;
    ///   * searching rendered text can find the wrong occurrence. «3» in
    ///     «3 мин» is unambiguous; an amount that also appears in the
    ///     surrounding copy is not.
    ///
    /// Where the insertion *is* uniform and its rendered form unique, the
    /// slider's idiom is the cheaper one — it needs no second lookup. Whether
    /// the two should converge is #722, not a decision made here.
    ///
    /// # When the template has no specifier
    ///
    /// A missing or renamed entry, or a translation that dropped its `%@`,
    /// reaches ``appendingUnplaceable(template:attributes:replacement:)``:
    /// `replacement` is **appended** rather than dropped, because a sentence
    /// with the amount in an odd place is still readable whereas one silently
    /// missing its amount reads as fact and is wrong. That is a floor for the
    /// release build, not a fix — so the branch also logs and traps, the way
    /// ``AppHairline/width(for:)`` does on a degenerate scale. Without the
    /// trap, the only thing between a lost `%@` and
    ///
    ///     За эту неделю списано. Возможно, что-то пошло не так. Что хотите
    ///     сделать?−750 ₽
    ///
    /// is an assertion over the *Russian* copy — and the entire point of #569
    /// is that a second language is coming, whose broken template no `ru`
    /// assertion can see.
    static func attributed(
        _ key: String,
        attributes: [NSAttributedString.Key: Any],
        replacing replacement: NSAttributedString
    ) -> NSMutableAttributedString {
        let template = optionalText(key) ?? key
        guard let placeholder = template.range(of: "%@") else {
            AppLogger.ui.error(
                """
                Localized.attributed: key \(key, privacy: .public) resolved to a template with \
                no specifier — appending the substituted run to the end of the sentence.
                """
            )
            assertionFailure(
                """
                Localized.attributed("\(key)") got a template with no %@. Either the catalogue \
                entry is missing or renamed, or a translation dropped the specifier. Release \
                appends the run rather than losing it; fix the entry.
                """
            )
            return appendingUnplaceable(
                template: template,
                attributes: attributes,
                replacement: replacement
            )
        }
        let result = NSMutableAttributedString(string: template, attributes: attributes)
        result.replaceCharacters(in: NSRange(placeholder, in: template), with: replacement)
        return result
    }

    /// What ``attributed(_:attributes:replacing:)`` returns once it has logged
    /// and trapped on a template it cannot place the run into.
    ///
    /// Split out for the same reason `AppHairline.degenerateWidth` is a named
    /// member rather than an inline literal: the branch traps by design, so a
    /// test reaching it through ``attributed(_:attributes:replacing:)`` would
    /// abort the suite instead of measuring anything. Called directly it pins
    /// the one thing that still matters in a release build — the run is
    /// appended, never dropped.
    static func appendingUnplaceable(
        template: String,
        attributes: [NSAttributedString.Key: Any],
        replacement: NSAttributedString
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: template, attributes: attributes)
        result.append(replacement)
        return result
    }
}
