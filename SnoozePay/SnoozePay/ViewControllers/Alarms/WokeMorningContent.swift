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
struct WokeMorningContent {

    /// Two visual / copy scenarios driven purely by the snooze count.
    enum Variant: Equatable {
        /// Got up on the first ring — no money moved.
        case clean
        /// Snoozed `N` times before getting up — `N ₽` charged.
        case recovered
    }

    /// Always "Доброе утро" — the eyebrow doesn't vary by scenario.
    static let eyebrow = "Доброе утро"

    let snoozes: Int
    let charged: Int

    /// - Parameters:
    ///   - snoozes: Times the user snoozed this wake (>= 0).
    ///   - charged: Roubles charged across those snoozes (rounded to whole ₽
    ///     for display, matching the JSX `${charged} ₽`).
    init(snoozes: Int, charged: Int) {
        self.snoozes = max(0, snoozes)
        self.charged = max(0, charged)
    }

    var variant: Variant { snoozes == 0 ? .clean : .recovered }

    var headline: String {
        switch variant {
        case .clean:
            return "Встал с первого раза"
        case .recovered:
            return "Удержались после \(snoozes) \(Self.snoozeWord(for: snoozes))"
        }
    }

    var subtitle: String {
        switch variant {
        case .clean:
            return "Баланс в полной сохранности. Так держать."
        case .recovered:
            return "Сегодня списано \(charged) ₽. Завтра попробуем не списать ничего."
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
