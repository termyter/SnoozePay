import Foundation

/// The currency situation a snooze price is resolved in (#1109).
///
/// - `scale` — the wallet's scale is known (constant in roubles, cached from the
///   storefront otherwise).
/// - `unavailable` — the currency is known but its scale is not (the catalogue never
///   loaded for it). Nothing can be charged: the caller takes the existing
///   "progression unavailable" path instead of guessing a number.
nonisolated enum SnoozePriceContext: Equatable, Sendable {
    case scale(SnoozePriceScale)
    case unavailable(Currency)

    var currency: Currency {
        switch self {
        case .scale(let scale): return scale.currency
        case .unavailable(let currency): return currency
        }
    }
}

/// Turns an alarm's `SnoozePrice` into the `Money` one snooze costs. Pure: no
/// UserDefaults, no StoreKit, safe off the main actor.
nonisolated enum SnoozePriceResolver {

    /// The progressive ladder stops at `base × 2^3` — the same 4-step rule as
    /// `Alarm.penalty(forSnoozeCount:)`.
    static let ceilingExponent = 3

    /// Price of the `snoozeCount`-th snooze (1-based), or `nil` when the context is
    /// `unavailable` or the price cannot be expressed in it.
    ///
    /// Base: a tier → its price in the scale; an amount in a rouble context → the
    /// amount itself, exactly today's number; an amount elsewhere → its legacy tier.
    /// Progressive: `base × 2^min(n − 1, 3)` in `Decimal`, so `0.99` climbs to
    /// `1.98 / 3.96 / 7.92` with no binary-float residue. A count ≤ 1 or a
    /// non-progressive alarm pays the base, matching `Alarm.penalty(forSnoozeCount:)`.
    static func resolve(
        _ price: SnoozePrice,
        snoozeCount: Int,
        isProgressive: Bool,
        in context: SnoozePriceContext
    ) -> Money? {
        guard let base = base(price, in: context) else { return nil }
        guard isProgressive, snoozeCount > 1 else { return base }
        let exponent = min(snoozeCount - 1, ceilingExponent)
        return base.multiplied(by: Decimal(1 << exponent))
    }

    /// Price of the first snooze — `resolve` without the progressive ladder.
    static func base(_ price: SnoozePrice, in context: SnoozePriceContext) -> Money? {
        guard case .scale(let scale) = context else { return nil }
        switch price {
        case .tier(let tier):
            return scale.price(for: tier)
        case .amount(let amount) where scale.currency == .rub:
            return Money(MoneyFormatter.decimalForDisplay(amount), currency: .rub)
        case .amount(let amount):
            guard let tier = SnoozePriceTier(legacyAmount: amount) else { return nil }
            return scale.price(for: tier)
        }
    }
}
