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

    /// Price of one snooze as the balance hints should quote it, in the
    /// currency of `context` (#1151). See the type docs for why this is the
    /// upper median over enabled alarms.
    ///
    /// Each alarm's first-snooze price is resolved in `context` the way its
    /// row pill is (`SnoozePriceResolver.base`): outside roubles a legacy
    /// amount of 50 is the scale's `low` tier ($0.99), not «50 dollars».
    /// `nil` when `context` is `.unavailable` or the price cannot be
    /// resolved — the hints then show no count instead of inventing one.
    static func currentPrice(
        alarms: [Alarm],
        defaults: AlarmDefaults = .shared,
        context: SnoozePriceContext
    ) -> Double? {
        guard case .scale = context else { return nil }
        let prices = alarms
            .filter(\.enabled)
            .compactMap { price(of: $0.price, in: context) }
            .filter { $0 > 0 }
            .sorted()
        guard !prices.isEmpty else { return price(of: .amount(defaults.penaltyAmount), in: context) }
        // Integer division lands on the middle element for an odd count and on
        // the upper of the two middles for an even one.
        return prices[prices.count / 2]
    }

    /// Number of snoozes the balance currently buys. Floored — neither hint
    /// advertises a fractional snooze — and 0 when the user is out of money,
    /// so the zero-balance / low-balance chrome can still fire. Display counts
    /// beyond the integer range saturate at `Int.max`. `nil` when no price
    /// resolves in `context` (see `currentPrice`).
    static func affordableCount(
        balance: Double,
        alarms: [Alarm],
        defaults: AlarmDefaults = .shared,
        context: SnoozePriceContext
    ) -> Int? {
        guard let price = currentPrice(alarms: alarms, defaults: defaults, context: context) else { return nil }
        guard price > 0, balance > 0, balance.isFinite else { return 0 }
        let count = flooredQuotient(balance, price, in: context.currency)
        // Double(Int.max) rounds up on 64-bit targets. Require a strict bound
        // before conversion; this also caps an overflowing positive quotient.
        guard count < Double(Int.max) else { return Int.max }
        return Int(count)
    }

    /// The shared hint copy: "Хватит на ~5 откладываний". Identical on both
    /// screens by construction — the wallet no longer appends "при текущей
    /// цене", a claim it could not back while the price was hardcoded and one
    /// that adds nothing now that the number is derived from real alarms.
    ///
    /// Ordinary counts use the whole-phrase catalogue plural variation (#598).
    /// Above Double's consecutive integer range, a second whole-phrase template
    /// takes an exact integer-formatted number and an integer-selected noun
    /// (#1059). Both arguments are positional so translations retain control
    /// over the sentence's word order.
    ///
    /// `nil` — no hint line — when no price resolves in `context` (#1151).
    static func hint(
        balance: Double,
        alarms: [Alarm],
        defaults: AlarmDefaults = .shared,
        context: SnoozePriceContext
    ) -> String? {
        guard let count = affordableCount(
            balance: balance, alarms: alarms, defaults: defaults, context: context
        ) else { return nil }
        guard count > 9_007_199_254_740_991 else {
            return Localized.format("common.snooze_affordability", count)
        }
        let number = IntegerFormatStyle<Int>(locale: AppLocale.display).format(count)
        return Localized.format("common.snooze_affordability_large", number, snoozeWord(for: count))
    }

    // MARK: - Private

    /// One alarm's first-snooze price in `context`, as a `Double`.
    ///
    /// A rouble amount is `SnoozePriceResolver`'s "the amount itself", taken
    /// as the stored `Double` so rouble counts — including the #1059 extremes
    /// such as `leastNonzeroMagnitude`, which have no `Decimal` form — stay
    /// exactly what they were. Everything else goes through the resolver.
    private static func price(of price: SnoozePrice, in context: SnoozePriceContext) -> Double? {
        if case .amount(let amount) = price, case .scale(let scale) = context, scale.currency == .rub {
            return amount
        }
        return SnoozePriceResolver.base(price, in: context).flatMap { MoneyDecimal.double($0.amount) }
    }

    /// `floor(balance / price)`. Roubles divide as `Double`, as before #1151.
    /// Elsewhere both are minor-unit amounts and a binary quotient can land
    /// just under an exact multiple (0.3 / 0.1 = 2.999…), so the division and
    /// the floor run in `Decimal` on the balance rounded to the currency's
    /// minor unit — the figure the card shows. Unrepresentable values keep
    /// the `Double` path.
    private static func flooredQuotient(_ balance: Double, _ price: Double, in currency: Currency) -> Double {
        let binary = floor(balance / price)
        guard currency != .rub else { return binary }
        var exact = MoneyDecimal.exact(balance)
        let divisor = MoneyDecimal.exact(price)
        guard !exact.isNaN, !divisor.isNaN, divisor > 0 else { return binary }
        var shown = Decimal(), floored = Decimal()
        NSDecimalRound(&shown, &exact, currency.minorUnitDigits, .plain)
        var quotient = shown / divisor
        NSDecimalRound(&floored, &quotient, 0, .down)
        return MoneyDecimal.double(floored) ?? binary
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
