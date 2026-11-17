import UIKit

/// Example amounts in explanatory copy — onboarding and the alarm-off sheet —
/// quoted in the wallet's price context (#1109).
///
/// These numbers were rouble literals («−50 ₽», «Положили 500 ₽»). Each one is a
/// multiple of a snooze tier, so outside roubles it becomes that multiple of the
/// tier in the context currency (no conversion): «≈ 5 snoozes at $0.99» stays
/// true of a $4.95 card. A rouble context keeps the literal through the legacy
/// whole-rouble formatter, byte-identical to the copy before. An unavailable
/// scale has no honest number, so the caller gets `nil` and words the line
/// without one.
enum ExampleMoneyCopy {

    /// `roubles` in a rouble context; `tier` × `multiple` of the scale in any
    /// other; `nil` when the scale is unavailable.
    static func money(
        roubles: Decimal, tier: SnoozePriceTier, times multiple: Decimal = 1, in context: SnoozePriceContext
    ) -> Money? {
        guard case .scale(let scale) = context else { return nil }
        if scale.currency == .rub { return Money(roubles, currency: .rub) }
        guard let base = scale.price(for: tier) else { return nil }
        return Money(base.amount * multiple, currency: base.currency)
    }

    /// Same as `money`, formatted; `nil` when the scale is unavailable.
    static func string(
        roubles: Decimal, tier: SnoozePriceTier, times multiple: Decimal = 1, in context: SnoozePriceContext
    ) -> String? {
        money(roubles: roubles, tier: tier, times: multiple, in: context).map { string($0) }
    }

    /// Roubles through the legacy formatter (today's exact bytes), any other
    /// currency through the currency-aware one.
    static func string(_ money: Money) -> String {
        money.currency == .rub
            ? MoneyFormatter.string(money.amount)
            : MoneyFormatter.string(money.amount, currency: money.currency)
    }

    /// Mono-digit form of `string(_:)`, with the same rouble/other split.
    static func attributed(
        _ money: Money, digitsFont: UIFont, prefix: String = "", color: UIColor? = nil
    ) -> NSAttributedString {
        money.currency == .rub
            ? MoneyFormatter.attributed(money.amount, digitsFont: digitsFont, prefix: prefix, color: color)
            : MoneyFormatter.attributed(
                money.amount, currency: money.currency, digitsFont: digitsFont, prefix: prefix, color: color
            )
    }
}
