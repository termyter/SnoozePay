import Foundation

/// Pure copy/variant logic for the WokeMorning summary screen (#228).
///
/// Factored out of `WokeMorningViewController` so the variant selection,
/// declension, and rendered strings are unit-testable without spinning up
/// UIKit. The view controller owns only layout / animation; every word the
/// user reads is decided here.
///
/// Spec — `docs/design/v2-handoff/components/SPWokeMorning.jsx`:
///   • `snoozes == 0` → `clean`: «Встал с первого раза» /
///     «Баланс в полной сохранности. Так держать.»
///   • `snoozes  > 0` → `recovered`: «Удержались после N откладываний» /
///     «Сегодня списано N ₽. Завтра попробуем не списать ничего.»
///   • some attempt was reversed → `partiallyReversed`: billed count + sum,
///     plus a line explaining the refunded attempts, so the two numbers add up
///     under the doubling rule the user can see on the firing screen (#400).
///   • ledger unreadable → `chargesUnavailable`: no count, no sum (#400).
struct WokeMorningContent {

    /// Visual / copy scenarios. The first three are driven by what the ledger
    /// says was billed; the last by the ledger being unreadable.
    enum Variant: Equatable {
        /// Got up on the first ring — no money moved.
        case clean
        /// Snoozed `N` times before getting up, every one of them billed —
        /// `N ₽` charged.
        case recovered
        /// The user made more snooze attempts than the ledger billed: at least
        /// one was charged and then refunded because the scheduler rejected the
        /// trigger. Stating only the billed pair would be individually true but
        /// arithmetically impossible against the doubling ladder (1 snooze that
        /// cost 100 ₽ on a 50 ₽ alarm), so the copy names the reversal.
        case partiallyReversed
        /// The transaction ledger couldn't be read, so neither the count nor
        /// the sum can be stated. The copy says so instead of printing a number
        /// nobody verified — and never claims the balance is untouched (#400).
        case chargesUnavailable
    }

    /// Always «Доброе утро» — the eyebrow doesn't vary by scenario.
    ///
    /// Computed rather than stored: a `static let` would resolve the catalogue
    /// at first access and hold that value for the process, hiding a missing
    /// key behind whichever test happened to run first.
    static var eyebrow: String { Localized.text("woke_morning.eyebrow") }

    /// Snoozes the ledger actually billed. `nil` when the ledger is unreadable
    /// — deliberately optional so a consumer can't mistake «we don't know» for
    /// a confident zero.
    let snoozes: Int?
    /// Roubles billed this wake, whole ₽. `nil` when the ledger is unreadable.
    let charged: Int?
    /// Snooze attempts that were charged and then refunded. `nil` when the
    /// ledger is unreadable.
    let reversedSnoozes: Int?
    let variant: Variant

    /// - Parameters:
    ///   - snoozes: Times the user was BILLED for a snooze this wake (>= 0) —
    ///     reversed (refunded) snoozes excluded, see
    ///     `AlarmFiringViewModel.billedSnoozeCount`.
    ///   - charged: Roubles charged across those snoozes (rounded to whole ₽
    ///     for display, matching the JSX `${charged} ₽`).
    ///   - attempts: Times the user tapped «Поспать ещё» and was charged,
    ///     including attempts later refunded. Defaults to `snoozes` (nothing
    ///     was reversed). Anything above `snoozes` selects `.partiallyReversed`.
    init(snoozes: Int, charged: Int, attempts: Int? = nil) {
        let billed = max(0, snoozes)
        let tries = max(billed, attempts ?? billed)
        self.snoozes = billed
        self.charged = max(0, charged)
        self.reversedSnoozes = tries - billed
        if tries > billed {
            self.variant = .partiallyReversed
        } else {
            self.variant = billed == 0 ? .clean : .recovered
        }
    }

    /// Fallback used when the ledger can't be read (#400).
    ///
    /// Carries no numbers at all — not even a zero. In particular it does NOT
    /// fall back to `.clean` when the in-memory attempt count is `0`: that
    /// counter is reset on the AlarmKit path (the firing screen tears down
    /// after each snooze and the next ring builds a fresh view model with
    /// `snoozeCount: 0`), so «no attempts this session» is NOT evidence that
    /// nothing was charged this morning. Claiming «баланс в полной
    /// сохранности» off an unreadable ledger would be the same nil-collapse
    /// this variant exists to prevent.
    static let chargesUnavailable = WokeMorningContent()

    private init() {
        self.snoozes = nil
        self.charged = nil
        self.reversedSnoozes = nil
        self.variant = .chargesUnavailable
    }

    var headline: String {
        switch variant {
        case .clean:
            return Localized.text("woke_morning.headline.clean")
        case .recovered, .partiallyReversed:
            let billed = snoozes ?? 0
            guard billed > 0 else { return Localized.text("woke_morning.headline.unchanged") }
            // Count + declined noun in one entry, so the catalogue owns the
            // order: Russian needs the numeral first, English does not.
            return Localized.format(
                "woke_morning.headline.recovered", billed, Self.snoozeWord(for: billed)
            )
        case .chargesUnavailable:
            return Localized.text("woke_morning.headline.unavailable")
        }
    }

    var subtitle: String {
        switch variant {
        case .clean:
            return Localized.text("woke_morning.subtitle.clean")
        case .recovered:
            return Localized.format("woke_morning.subtitle.recovered", charged ?? 0)
        case .partiallyReversed:
            // Both branches are whole two-sentence entries rather than a
            // lead-in plus the shared «не состоявшихся откладываний» tail: the
            // reversal is what the second sentence explains, and a language
            // that wants it first can only say so if it owns both.
            let reversed = reversedSnoozes ?? 0
            guard let charged, charged > 0 else {
                return Localized.format("woke_morning.subtitle.reversed_none", reversed)
            }
            return Localized.format("woke_morning.subtitle.reversed_charged", charged, reversed)
        case .chargesUnavailable:
            return Localized.text("woke_morning.subtitle.unavailable")
        }
    }

    /// Genitive of «откладывание» governed by the numeral after «после N …».
    ///
    /// Unlike the nominative forms in `PluralForms.snoozes`, the preposition
    /// «после» forces the genitive throughout, so 2–4 collapses onto the many
    /// form («после 1 откладывания», «после 2 откладываний»). That is what
    /// `PluralForms.snoozesAfter` encodes — the rule is shared, the words are
    /// not.
    static func snoozeWord(for count: Int) -> String {
        Plural.word(count, .snoozesAfter)
    }
}
