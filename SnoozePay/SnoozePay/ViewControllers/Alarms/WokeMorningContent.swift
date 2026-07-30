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
///   • ledger unreadable → "chargesUnavailable": no count, no sum (#400).
struct WokeMorningContent {

    /// Visual / copy scenarios. The first two are driven by the billed snooze
    /// count; the third by the ledger being unreadable.
    enum Variant: Equatable {
        /// Got up on the first ring — no money moved.
        case clean
        /// Snoozed `N` times before getting up — `N ₽` charged.
        case recovered
        /// The user snoozed, but the transaction ledger couldn't be read, so
        /// neither the count nor the sum can be stated. The copy says so
        /// instead of printing a number nobody verified (#400).
        case chargesUnavailable
    }

    /// Always "Доброе утро" — the eyebrow doesn't vary by scenario.
    static let eyebrow = "Доброе утро"

    let snoozes: Int
    let charged: Int
    let variant: Variant

    /// - Parameters:
    ///   - snoozes: Times the user was BILLED for a snooze this wake (>= 0) —
    ///     reversed (refunded) snoozes excluded, see
    ///     `AlarmFiringViewModel.billedSnoozeCount`.
    ///   - charged: Roubles charged across those snoozes (rounded to whole ₽
    ///     for display, matching the JSX `${charged} ₽`).
    init(snoozes: Int, charged: Int) {
        let clampedSnoozes = max(0, snoozes)
        self.snoozes = clampedSnoozes
        self.charged = max(0, charged)
        self.variant = clampedSnoozes == 0 ? .clean : .recovered
    }

    /// Fallback used when the ledger can't be read (#400).
    ///
    /// `attempts` is the in-memory snooze count — enough to know the user
    /// *did* snooze, but not what survived refunds, so it is never printed.
    /// Zero attempts still reads as `.clean`: a snooze only bumps the counter
    /// after its charge lands, so "no attempts" is a fact we hold independently
    /// of the ledger — nothing was taken.
    init(chargesUnavailableAfter attempts: Int) {
        let clampedAttempts = max(0, attempts)
        self.snoozes = clampedAttempts
        self.charged = 0
        self.variant = clampedAttempts == 0 ? .clean : .chargesUnavailable
    }

    var headline: String {
        switch variant {
        case .clean:
            return "Встал с первого раза"
        case .recovered:
            return "Удержались после \(snoozes) \(Self.snoozeWord(for: snoozes))"
        case .chargesUnavailable:
            return "Вы всё-таки встали"
        }
    }

    var subtitle: String {
        switch variant {
        case .clean:
            return "Баланс в полной сохранности. Так держать."
        case .recovered:
            return "Сегодня списано \(charged) ₽. Завтра попробуем не списать ничего."
        case .chargesUnavailable:
            return "Не удалось прочитать историю списаний — точная сумма в разделе «Статистика»."
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
