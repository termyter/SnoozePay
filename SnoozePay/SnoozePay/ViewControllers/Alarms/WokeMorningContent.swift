import Foundation

/// Pure copy/variant logic for the WokeMorning summary screen (#228).
///
/// Factored out of `WokeMorningViewController` so the variant selection,
/// declension, and rendered strings are unit-testable without spinning up
/// UIKit. The view controller owns only layout / animation; every word the
/// user reads is decided here.
///
/// Spec — `docs/design/v2-handoff/components/SPWokeMorning.jsx`:
///   • `snoozes == 0` → "clean": "Встал с первого раза" /
///     "Баланс в полной сохранности. Так держать."
///   • `snoozes  > 0` → "recovered": "Удержались после N откладываний" /
///     "Сегодня списано N ₽. Завтра попробуем не списать ничего."
///   • some attempt was reversed → "partiallyReversed": billed count + sum,
///     plus a line explaining the refunded attempts, so the two numbers add up
///     under the doubling rule the user can see on the firing screen (#400).
///   • ledger unreadable → "chargesUnavailable": no count, no sum (#400).
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

    /// Always "Доброе утро" — the eyebrow doesn't vary by scenario.
    static let eyebrow = "Доброе утро"

    /// Snoozes the ledger actually billed. `nil` when the ledger is unreadable
    /// — deliberately optional so a consumer can't mistake "we don't know" for
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
    /// `snoozeCount: 0`), so "no attempts this session" is NOT evidence that
    /// nothing was charged this morning. Claiming "баланс в полной
    /// сохранности" off an unreadable ledger would be the same nil-collapse
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
            return "Встал с первого раза"
        case .recovered, .partiallyReversed:
            let billed = snoozes ?? 0
            guard billed > 0 else { return "Баланс не изменился" }
            return "Удержались после \(billed) \(Self.snoozeWord(for: billed))"
        case .chargesUnavailable:
            return "Вы встали"
        }
    }

    var subtitle: String {
        switch variant {
        case .clean:
            return "Баланс в полной сохранности. Так держать."
        case .recovered:
            return "Сегодня списано \(charged ?? 0) ₽. Завтра попробуем не списать ничего."
        case .partiallyReversed:
            // Numeral-after-colon so the sentence needs no extra declension
            // rule for «откладывание» in the nominative.
            let reversed = reversedSnoozes ?? 0
            let tail = "Не состоявшихся откладываний: \(reversed) — деньги за них вернули."
            guard let charged, charged > 0 else {
                return "Списаний не осталось. \(tail)"
            }
            return "Сегодня списано \(charged) ₽. \(tail)"
        case .chargesUnavailable:
            return "Историю списаний прочитать не удалось, поэтому сумму за это утро "
                 + "мы не показываем. Текущий баланс — на главном экране."
        }
    }

    /// Genitive of «откладывание» governed by the numeral after «после N …».
    ///
    /// Unlike the nominative 2–4 rule used in `StreakModalViewController
    /// .dayWord` (день/дня/дней), the preposition «после» forces the genitive
    /// throughout, so the only split is singular-vs-rest:
    ///   • `N % 10 == 1 && N % 100 != 11` → "откладывания"
    ///     ("после 1 откладывания", "после 21 откладывания")
    ///   • otherwise → "откладываний"
    ///     ("после 2 откладываний", "после 5 откладываний", "после 11 …")
    static func snoozeWord(for count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod10 == 1 && mod100 != 11 {
            return "откладывания"
        }
        return "откладываний"
    }
}
