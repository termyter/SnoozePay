import XCTest
@testable import SnoozePay

/// Guards every `en` entry of `Localizable.xcstrings` against the `ru` one it
/// translates: same printf specifiers, no Cyrillic, not empty (#888, part of
/// #602). Since the final slice (#894) it also requires that every `ru` key
/// has an `en` entry at all.
///
/// # Why this exists
///
/// Every other copy test reads through ``Localized``, which resolves one
/// language — ``AppLocale/display``, hardcoded `ru_RU` until #603. So a
/// *translation* that grows a second `%@`, drops the `%lld`, or turns it into a
/// `%@` is invisible to all of them; `Localized.attributed` names that gap in
/// its own doc comment. Nothing else catches it either: the catalogue is JSON,
/// the compiler never sees a value, and the break surfaces only on a device set
/// to English — as a crash in `String(format:)` or a sentence with its amount
/// missing. The English slices of #602 land in parallel, and no user sees any of
/// them before #603, so a broken specifier could sit on `main` for weeks.
///
/// # What is compared
///
/// The **compiled** tables, not the catalogue: `Localizable.xcstrings` is not
/// copied into the app, and the tables are what the runtime actually reads.
/// Specifiers are compared as a multiset of *types* — `%1$@` and `%@` are both
/// `@` — because English may reorder positional arguments but must consume
/// exactly the same ones. `%%` is a literal percent sign, not an argument.
///
/// Two artefacts of `xcstringstool` shape the reading. Both are observed, not
/// documented: first with Xcode 27 locally, then confirmed on CI's Xcode 26.5
/// (run 36112283565).
///
/// - The `en` table carries an entry whose value **is its own key** for every
///   untranslated key whose `ru` value has a specifier, and for every plural
///   variation. Such an entry means "no `en` yet", not a translation: the
///   parity sweeps skip it, and the completeness sweep counts it as missing —
///   a real value never equals a dotted key.
/// - A `Variations → Plural` entry compiles into `.stringsdict`, not
///   `.strings`, and the runtime prefers the `.stringsdict` entry. Its
///   arguments are fixed by `NSStringLocalizedFormatKey`, with each
///   `%#@variable@` standing for one argument of the variable's
///   `NSStringFormatValueTypeKey`; that is what gets compared.
///
/// The tests are layered like `LocalizableCatalogTests`: first the extraction
/// helpers are proved on literals — a helper that returned `[]` for everything
/// would pass every sweep below — then the `en` table is shown to exist and to
/// hold something to compare, then the sweeps run.
///
/// # Completeness
///
/// Every key of the `ru` table (`.strings` and `.stringsdict`) needs a real
/// `en` entry — a key echo does not count. There is exactly one exemption
/// rule, ``completenessExemptionPattern``: `plural.<noun>.few`. English has no
/// «few» form, and `PluralForms` falls back from `few` to `many` when the entry
/// is absent, so the glossary on #602 forbids an `en` for it. No key is
/// exempted by name today. A key that genuinely must stay untranslated would
/// be listed next to the pattern, by name, with its reason.
///
/// # What it deliberately does not check
///
/// - **Specifiers inside individual plural forms.** English `one` may
///   legitimately omit the number («One day»), so forms are checked only for
///   Cyrillic and emptiness.
/// - **Length.** Whether a caps caption still fits is an on-device question for
///   #603, not a string comparison.
final class LocalizationParityTests: XCTestCase {

    // MARK: - Layer 0: the helpers catch, not only pass

    func testSpecifierTypesDropPositionsAndLiteralPercent() throws {
        XCTAssertEqual(try Self.specifierTypes(in: "%1$lld-е: %2$@"), ["@", "lld"])
        XCTAssertEqual(try Self.specifierTypes(in: "%lld%% · плавно"), ["lld"])
        XCTAssertEqual(try Self.specifierTypes(in: "100%%"), [])
        XCTAssertEqual(try Self.specifierTypes(in: "Подъём"), [])
        XCTAssertEqual(
            try Self.specifierTypes(in: "%2$@ after snooze %1$lld"),
            try Self.specifierTypes(in: "%1$lld-е: %2$@"),
            "Reordering positional arguments is allowed and must compare equal."
        )
    }

    func testSpecifierTypesCatchAnExtraOrRetypedArgument() throws {
        XCTAssertNotEqual(
            try Self.specifierTypes(in: "%@ · скоро"),
            try Self.specifierTypes(in: "%@ · soon, %@"),
            "A translation that grows a second %@ must not compare equal."
        )
        XCTAssertNotEqual(
            try Self.specifierTypes(in: "%lld мин"),
            try Self.specifierTypes(in: "%@ min"),
            "An Int argument read as an object must not compare equal."
        )
        XCTAssertNotEqual(
            try Self.specifierTypes(in: "%lld мин"),
            try Self.specifierTypes(in: "%d min"),
            "%d reads 32 bits of a 64-bit Int; it is a different type."
        )
        XCTAssertNotEqual(
            try Self.specifierTypes(in: "%lld%% off"),
            try Self.specifierTypes(in: "%lld% off"),
            "String(format:) reads an unescaped «% o» as an %o conversion, so it must show up."
        )
    }

    func testPluralSignatureResolvesEachVariableToItsValueType() throws {
        let entry: [String: Any] = [
            "NSStringLocalizedFormatKey": "%1$#@days@ · %2$@",
            "days": [
                "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                "NSStringFormatValueTypeKey": "lld",
                "one": "%lld день",
                "other": "%lld дней"
            ]
        ]
        XCTAssertEqual(try Self.pluralSpecifierTypes(entry), ["@", "lld"])
        XCTAssertEqual(
            Set(Self.pluralTexts(entry)),
            ["%1$#@days@ · %2$@", "%lld день", "%lld дней"],
            "Every form is copy; the NSString… bookkeeping values are not."
        )

        var retyped = entry
        retyped["days"] = ["NSStringFormatValueTypeKey": "@", "other": "%@ days"]
        XCTAssertNotEqual(try Self.pluralSpecifierTypes(retyped), try Self.pluralSpecifierTypes(entry))

        XCTAssertNil(
            try Self.pluralSpecifierTypes(["NSStringLocalizedFormatKey": "%#@missing@"]),
            "A variable with no declared type must not quietly read as no argument."
        )
    }

    func testCyrillicDetectorSeesAHomoglyphButNotTheRoubleSign() {
        XCTAssertFalse(Self.containsCyrillic("Minimum 1 ₽"))
        XCTAssertFalse(Self.containsCyrillic("Name · e.g. Weekdays"))
        // The «е» below is U+0435, which renders exactly like Latin «e».
        XCTAssertTrue(Self.containsCyrillic("Snooze f\u{0435}e"))
    }

    func testCompletenessCountsAKeyEchoAsMissingAndExemptsOnlyPluralFew() {
        let missing = Self.untranslatedKeys(
            [
                "tab.wallet",               // translated
                "tab.alarms",               // no en entry at all
                "alarm_failure.body",       // key echo: xcstringstool's «no en yet»
                "example.days_count",       // translated plural, lives in .stringsdict
                "plural.days.few",          // the exemption
                "plural.snoozes_after.few", // the exemption, noun with an underscore
                "plural.days.many",         // echoed; only .few is exempt
                "alarms.few",               // not a plural.<noun> entry
                "plural.few"                // no noun segment
            ],
            strings: [
                "tab.wallet": "Wallet",
                "alarm_failure.body": "alarm_failure.body",
                "plural.days.many": "plural.days.many"
            ],
            pluralKeys: ["example.days_count"]
        )
        XCTAssertEqual(
            missing,
            ["alarm_failure.body", "alarms.few", "plural.days.many", "plural.few", "tab.alarms"],
            "A key echo is xcstringstool's placeholder for a missing en, not a translation."
        )
        XCTAssertFalse(Self.isExemptFromCompleteness("plural.days.few.caps"))
        XCTAssertTrue(Self.isExemptFromCompleteness("plural.mornings.few"))
    }

    // MARK: - Layer 1: there is an English table with something in it

    /// Without this, every sweep below would pass over an empty set: a catalogue
    /// that lost its `en` entries, or a build that stopped compiling them, reads
    /// exactly like a perfect translation.
    func testEnglishTableShipsAndHoldsTranslations() throws {
        let english = try XCTUnwrap(
            Self.table("en"),
            "en.lproj/Localizable.strings is not in the app bundle. Bundle.main.localizations = "
                + "\(Bundle.main.localizations)"
        )
        let translations = try english.translations()
        XCTAssertFalse(translations.isEmpty, "en.lproj holds no translated entry, only key echoes.")
        XCTAssertTrue(
            translations.contains { $0.specifiers?.isEmpty == false },
            "No translated en entry carries a specifier, so the parity sweep compares nothing."
        )
        XCTAssertNotNil(Self.table("ru"), "ru.lproj/Localizable.strings is not in the app bundle.")
    }

    // MARK: - Layer 2: every English entry against its Russian one

    func testEveryEnglishEntryConsumesTheRussianArguments() throws {
        let english = try XCTUnwrap(Self.table("en"))
        let russian = try XCTUnwrap(Self.table("ru"))
        var broken: [String] = []
        for entry in try english.translations() {
            guard let source = try russian.entry(for: entry.key) else {
                broken.append("\(entry.key): has en but no ru")
                continue
            }
            guard let ruTypes = source.specifiers, let enTypes = entry.specifiers else {
                broken.append("\(entry.key): a plural variable declares no value type")
                continue
            }
            if ruTypes != enTypes {
                broken.append("\(entry.key): ru \(ruTypes) ≠ en \(enTypes)")
            }
        }
        XCTAssertTrue(
            broken.isEmpty,
            "en must consume the same arguments as ru (types, any order):\n"
                + broken.sorted().joined(separator: "\n")
        )
    }

    func testNoEnglishEntryContainsCyrillic() throws {
        let english = try XCTUnwrap(Self.table("en"))
        let offenders = try english.translations()
            .filter { $0.texts.contains(where: Self.containsCyrillic) }
            .map(\.key)
            .sorted()
        XCTAssertTrue(offenders.isEmpty, "Cyrillic in en: \(offenders)")
    }

    func testNoEnglishEntryIsEmpty() throws {
        let english = try XCTUnwrap(Self.table("en"))
        let offenders = try english.translations()
            .filter { entry in
                entry.texts.isEmpty
                    || entry.texts.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            .map(\.key)
            .sorted()
        XCTAssertTrue(offenders.isEmpty, "Empty en values: \(offenders)")
    }

    // MARK: - Layer 3: no Russian key without English

    func testEveryRussianKeyHasAnEnglishTranslation() throws {
        let english = try XCTUnwrap(Self.table("en"))
        let russian = try XCTUnwrap(Self.table("ru"))
        XCTAssertFalse(russian.keys.isEmpty, "The ru table is empty, so there is nothing to require en for.")
        let missing = Self.untranslatedKeys(
            russian.keys,
            strings: english.strings,
            pluralKeys: Set(english.plurals.keys)
        )
        XCTAssertTrue(
            missing.isEmpty,
            "\(missing.count) ru keys have no en translation (a key echo counts as none; "
                + "only plural.<noun>.few is exempt):\n" + missing.joined(separator: "\n")
        )
    }
}

// MARK: - Reading the compiled tables

private extension LocalizationParityTests {

    /// One key of one compiled table, reduced to what the sweeps compare.
    struct Entry {
        let key: String
        /// Sorted argument types; `nil` when a plural variable declares none.
        let specifiers: [String]?
        /// Every string a user can see: the flat value, or the format key and
        /// every plural form.
        let texts: [String]
    }

    struct Table {
        let strings: [String: String]
        let plurals: [String: [String: Any]]

        /// Every key the table answers, from either file.
        var keys: Set<String> { Set(strings.keys).union(plurals.keys) }

        /// The entry the runtime would read for `key`: `.stringsdict` first.
        func entry(for key: String) throws -> Entry? {
            if let plural = plurals[key] {
                return Entry(
                    key: key,
                    specifiers: try LocalizationParityTests.pluralSpecifierTypes(plural),
                    texts: LocalizationParityTests.pluralTexts(plural)
                )
            }
            guard let value = strings[key] else { return nil }
            return Entry(key: key, specifiers: try LocalizationParityTests.specifierTypes(in: value), texts: [value])
        }

        /// Entries that are real translations — not the key echoes
        /// `xcstringstool` writes for untranslated keys (see the type's doc).
        func translations() throws -> [Entry] {
            try Set(strings.keys).union(plurals.keys)
                .filter { plurals[$0] != nil || strings[$0] != $0 }
                .compactMap { try entry(for: $0) }
        }
    }

    static func table(_ language: String) -> Table? {
        let folder = "\(language).lproj"
        guard
            let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: folder),
            let strings = NSDictionary(contentsOf: url) as? [String: String]
        else { return nil }
        let pluralURL = Bundle.main.url(forResource: "Localizable", withExtension: "stringsdict", subdirectory: folder)
        let plurals = pluralURL.flatMap { NSDictionary(contentsOf: $0) as? [String: [String: Any]] } ?? [:]
        return Table(strings: strings, plurals: plurals)
    }

    // MARK: - Specifier extraction
    //
    // The pure helpers below are `nonisolated`: the target defaults to
    // `MainActor` isolation, and passing one as a function reference —
    // `contains(where: Self.containsCyrillic)` — into a synchronous
    // nonisolated closure otherwise warns on every build.

    /// A printf conversion as `String(format:)` reads it: optional position,
    /// flags, width, precision, then length modifier and conversion — the last
    /// two captured as the type. `%%` matches as well, so it is consumed as a
    /// pair and the letter after it is never mistaken for a conversion.
    nonisolated static let specifierPattern =
        #"%(?:%|(?:\d+\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?((?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]))"#

    /// `%#@variable@`, optionally positional, in a `.stringsdict` format key.
    nonisolated static let pluralVariablePattern = #"%(\d+\$)?#@([^@]+)@"#

    /// The argument types `text` consumes, positions stripped, sorted — so two
    /// values compare equal exactly when they consume the same arguments.
    nonisolated static func specifierTypes(in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: specifierPattern)
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .filter { $0.range(at: 1).location != NSNotFound }
            .map { nsText.substring(with: $0.range(at: 1)) }
            .sorted()
    }

    /// The argument types a `.stringsdict` entry consumes: its format key with
    /// every `%#@variable@` replaced by `%<value type>`. `nil` when a variable
    /// the format key names declares no type.
    nonisolated static func pluralSpecifierTypes(_ entry: [String: Any]) throws -> [String]? {
        guard let format = entry["NSStringLocalizedFormatKey"] as? String else { return nil }
        let regex = try NSRegularExpression(pattern: pluralVariablePattern)
        let resolved = NSMutableString(string: format)
        let matches = regex.matches(in: format, range: NSRange(location: 0, length: resolved.length))
        // Back to front, so each replacement leaves the earlier ranges valid.
        for match in matches.reversed() {
            let name = resolved.substring(with: match.range(at: 2))
            guard
                let variable = entry[name] as? [String: Any],
                let type = variable["NSStringFormatValueTypeKey"] as? String
            else { return nil }
            let position = match.range(at: 1).location == NSNotFound ? "" : resolved.substring(with: match.range(at: 1))
            resolved.replaceCharacters(in: match.range, with: "%\(position)\(type)")
        }
        return try specifierTypes(in: resolved as String)
    }

    /// The format key and every plural form of a `.stringsdict` entry — the
    /// `NSString…` bookkeeping values are not copy and are left out.
    nonisolated static func pluralTexts(_ entry: [String: Any]) -> [String] {
        var texts: [String] = []
        for (key, value) in entry {
            if key == "NSStringLocalizedFormatKey", let text = value as? String {
                texts.append(text)
            } else if let variable = value as? [String: Any] {
                texts += variable
                    .filter { !$0.key.hasPrefix("NSString") }
                    .compactMap { $0.value as? String }
            }
        }
        return texts
    }

    nonisolated static func containsCyrillic(_ text: String) -> Bool {
        text.range(of: #"\p{Script=Cyrillic}"#, options: .regularExpression) != nil
    }

    // MARK: - Completeness

    /// The one exemption from "every ru key has en", with its reason in the
    /// type's doc: `PluralForms` falls back from an absent `few` to `many`.
    nonisolated static let completenessExemptionPattern = #"^plural\.[^.]+\.few$"#

    nonisolated static func isExemptFromCompleteness(_ key: String) -> Bool {
        key.range(of: completenessExemptionPattern, options: .regularExpression) != nil
    }

    /// The keys of `sourceKeys` with no real `en` translation, sorted. A key
    /// counts as translated when it is a `.stringsdict` entry or a `.strings`
    /// value other than the key itself: `xcstringstool` writes that echo for
    /// untranslated keys that carry a specifier, so it means "missing" here.
    nonisolated static func untranslatedKeys(
        _ sourceKeys: Set<String>,
        strings: [String: String],
        pluralKeys: Set<String>
    ) -> [String] {
        sourceKeys
            .filter { !isExemptFromCompleteness($0) && !pluralKeys.contains($0) && (strings[$0] ?? $0) == $0 }
            .sorted()
    }
}
