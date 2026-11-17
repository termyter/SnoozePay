import Foundation

/// The snooze-price context of this wallet (#1109, #1130): which scale a snooze
/// price resolves in, and which currency money is shown in.
///
/// Display and price only. `walletCurrency`, ledger stamping, `acceptsPurchase`
/// and the freeze are untouched: nothing here writes, and nothing is frozen
/// before a purchase.
extension BalanceService {

    /// Resolved synchronously from UserDefaults; never waits on StoreKit, so the
    /// charging path may read it.
    ///
    /// 1. Stored wallet currency: RUB → the constant rouble scale; any other →
    ///    its cached scale, else `.unavailable` — never another currency's scale
    ///    and never a guessed number.
    /// 2. No stored currency, wallet not pristine (a legacy rouble wallet with
    ///    history) → rouble scale.
    /// 3. Pristine wallet → the cached scale of the last-seen storefront; none
    ///    → rouble scale (the behaviour before #1109).
    ///
    /// Cached tiers are rounded to the currency's minor unit first, so a
    /// `Product.price` artefact (1.9899999…) never becomes a charge amount; tiers
    /// that stop being a valid scale once rounded are `.unavailable`.
    ///
    /// ⚠️ Calls `walletIsPristine`, which takes `queue.sync`: never read this from
    /// inside the serial queue.
    var priceContext: SnoozePriceContext {
        if let stored = storedWalletCurrency {
            guard stored != .rub else { return .scale(.rouble) }
            return roundedCachedScale(for: stored).map(SnoozePriceContext.scale) ?? .unavailable(stored)
        }
        guard walletIsPristine else { return .scale(.rouble) }
        guard let storefront = priceScaleStore.lastStorefrontCurrency,
              let scale = roundedCachedScale(for: storefront) else { return .scale(.rouble) }
        return .scale(scale)
    }

    /// The currency amounts are shown in: `priceContext.currency`. For a
    /// pristine wallet that is the storefront's, while `walletCurrency` stays
    /// roubles until the first purchase freezes it.
    var displayCurrency: Currency { priceContext.currency }

    /// The context AlarmKit snooze labels are quoted in (#1138), or `nil` for
    /// today's unpriced label.
    ///
    /// Same as `priceContext`, except for a pristine wallet whose storefront
    /// scale is not cached (no catalogue loaded yet, or the cached one is
    /// unreadable): `priceContext` falls back to roubles there, but a label is
    /// baked into an alert that may still be ringing when the first purchase
    /// freezes another currency, so it stays unpriced rather than quoting ₽.
    /// A refresh on `snoozePriceScaleChangedNotification` re-bakes it.
    ///
    /// ⚠️ Takes `queue.sync` like `priceContext`: never read it from the queue.
    var alarmQuoteContext: SnoozePriceContext? {
        let context = priceContext
        guard storedWalletCurrency == nil, walletIsPristine else { return context }
        guard let storefront = priceScaleStore.lastStorefrontCurrency,
              case .scale(let scale) = context, scale.currency == storefront else { return nil }
        return context
    }

    private func roundedCachedScale(for currency: Currency) -> SnoozePriceScale? {
        guard let cached = priceScaleStore.scale(for: currency) else { return nil }
        if currency == .rub { return cached }
        let digits = currency.minorUnitDigits
        let tiers = cached.tiers.map { tier -> Decimal in
            var value = tier, rounded = Decimal()
            NSDecimalRound(&rounded, &value, digits, .plain)
            return rounded
        }
        return SnoozePriceScale(currency: currency, tiers: tiers)
    }
}

extension Currency {

    /// ISO 4217 minor-unit digits (USD 2, JPY 0, KWD 3), from Foundation's
    /// currency data — the same precision `MoneyFormatter` shows.
    nonisolated var minorUnitDigits: Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
}
