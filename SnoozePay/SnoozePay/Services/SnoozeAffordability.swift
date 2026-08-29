import Foundation

/// Single source of truth for the "Хватит на ~N откладываний" hint (#546).
///
/// Two screens answer the same question — the alarms-list balance card
/// (`AlarmsListViewModel.balanceHint`) and the wallet balance card
/// (`WalletHints.affordHint`). Until #546 each computed it on its own and the
/// two disagreed: at 298 ₽ the list said "~1" (its "mode" over ALL alarms
/// degenerated to the most expensive one) while the wallet said "~5" (it
/// divided by a hardcoded 50 ₽ while promising "при текущей цене"). Both now
/// call in here, so a future tweak lands on both screens at once.
///
/// ## What "the current price" means
///
/// The **upper median penalty across ENABLED alarms**, falling back to
/// `AlarmDefaults.penaltyAmount` (the "Цена откладывания по умолчанию" the user
/// set in Settings) when no enabled alarm carries a positive penalty.
///
/// - *Enabled only* — a disabled alarm can never charge the user, so it must
///   not move the number. On the screenshot in #546 the answer "~1" was decided
///   by a switched-off 200 ₽ alarm.
/// - *Median, not mode* — the mode was chosen to shrug off outliers ("four
///   alarms at 50 ₽ + one at 200 ₽ should report ~50"), but with all-distinct
///   prices — the common case — every frequency is 1 and the mode collapses
///   into whatever the tie-break picks, i.e. the outlier itself. The median
///   keeps the outlier-resistance (`[50, 50, 50, 50, 200]` → 50) without the
///   degenerate case (`[50, 100, 200]` → 100, not 200).
/// - *Upper* median on an even count (`[50, 200]` → 200) — the hint would
///   rather under-promise than tell the user they can afford snoozes they
///   cannot. This preserves the intent of the tie-break rule it replaces.
/// - *`AlarmDefaults` as the fallback*, not a private `50` constant. It is the
///   price the user explicitly configured and the one a brand-new alarm will
///   cost, so it is the only honest answer when there is nothing else to
///   measure. It also removes the fourth copy of the number `50`.
enum SnoozeAffordability {

    /// Price of one snooze as the balance hints should quote it. See the type
    /// docs for why this is the upper median over enabled alarms.
    static func currentPrice(alarms: [Alarm], defaults: AlarmDefaults = .shared) -> Double {
        let prices = alarms
            .filter { $0.enabled && $0.penaltyAmount > 0 }
            .map { $0.penaltyAmount }
            .sorted()
        guard !prices.isEmpty else { return defaults.penaltyAmount }
        // Integer division lands on the middle element for an odd count and on
        // the upper of the two middles for an even one.
        return prices[prices.count / 2]
    }

    /// Number of snoozes the balance currently buys. Floored — neither hint
    /// advertises a fractional snooze — and 0 when the user is out of money,
    /// so the zero-balance / low-balance chrome can still fire.
    static func affordableCount(
        balance: Double,
        alarms: [Alarm],
        defaults: AlarmDefaults = .shared
    ) -> Int {
        let price = currentPrice(alarms: alarms, defaults: defaults)
        guard price > 0, balance > 0, balance.isFinite else { return 0 }
        return Int(floor(balance / price))
    }

    /// The shared hint copy: "Хватит на ~5 откладываний". Identical on both
    /// screens by construction — the wallet no longer appends "при текущей
    /// цене", a claim it could not back while the price was hardcoded and one
    /// that adds nothing now that the number is derived from real alarms.
    static func hint(
        balance: Double,
        alarms: [Alarm],
        defaults: AlarmDefaults = .shared
    ) -> String {
        let count = affordableCount(balance: balance, alarms: alarms, defaults: defaults)
        return "Хватит на ~\(count) \(snoozeWord(for: count))"
    }

    /// Pluralisation for "откладывание" in the nominative — `откладывание`
    /// (n=1, 21, 31…), `откладывания` (2-4, 22-24…), `откладываний`
    /// (everything else, including 0 and 5-20). Moved here from
    /// `AlarmsListViewModel` in #546, where it was private and therefore
    /// unreachable from the wallet — which is exactly how the wallet ended up
    /// able to render "~1 откладываний". The rule itself now lives in `Plural`
    /// (#569); this stays as the name the affordability copy calls.
    static func snoozeWord(for count: Int) -> String {
        Plural.word(count, .snoozes)
    }
}
