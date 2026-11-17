import Foundation
import os

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
    /// `Product.price` artefact (1.9899999…) never becomes a charge amount.
    /// Tiers that stop being a valid scale once rounded count as no cached
    /// scale: `.unavailable` for a stored currency (1), the rouble scale for a
    /// pristine wallet (3). Both are logged once per currency and scale.
    ///
    /// ⚠️ Calls `walletIsPristine`, which takes `queue.sync`: never read this from
    /// inside the serial queue.
    var priceContext: SnoozePriceContext {
        if let stored = storedWalletCurrency {
            guard stored != .rub else { return .scale(.rouble) }
            return roundedCachedScale(for: stored, otherwise: "unavailable")
                .map(SnoozePriceContext.scale) ?? .unavailable(stored)
        }
        guard walletIsPristine else { return .scale(.rouble) }
        guard let storefront = priceScaleStore.lastStorefrontCurrency,
              let scale = roundedCachedScale(for: storefront, otherwise: "rouble fallback") else {
            return .scale(.rouble)
        }
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

    /// The cached scale of `currency` rounded to its minor unit, or `nil`.
    /// `outcome` names what the caller does with `nil`, for the log line.
    ///
    /// `priceContext` is read on every render, so both log lines fire once per
    /// currency and cached scale per process.
    private func roundedCachedScale(for currency: Currency, otherwise outcome: String) -> SnoozePriceScale? {
        guard let cached = priceScaleStore.scale(for: currency) else { return nil }
        if currency == .rub { return cached }
        let digits = currency.minorUnitDigits
        let tiers = cached.tiers.map { tier -> Decimal in
            var value = tier, rounded = Decimal()
            NSDecimalRound(&rounded, &value, digits, .plain)
            return rounded
        }
        guard tiers != cached.tiers else { return cached }
        let code = currency.code
        let before = cached.tiers.map(\.description).joined(separator: "/")
        let after = tiers.map(\.description).joined(separator: "/")
        guard let scale = SnoozePriceScale(currency: currency, tiers: tiers) else {
            if PriceContextLogOnce.first("invalid|\(code)|\(before)|\(outcome)") {
                AppLogger.emit(
                    .balance, .error,
                    "price scale \(code) \(before) rounds to \(after), not a valid scale — \(outcome)"
                )
            }
            return nil
        }
        if PriceContextLogOnce.first("rounded|\(code)|\(before)") {
            AppLogger.emit(.balance, .default, "price scale \(code) \(before) rounded to minor unit: \(after)")
        }
        return scale
    }
}

extension Currency {

    /// Fraction digits of this currency in Foundation's (CLDR) currency data —
    /// the precision `MoneyFormatter` shows (USD 2, JPY 0, KWD 3).
    ///
    /// Not ISO 4217 minor units: CLDR gives 0 to several currencies ISO lists
    /// with 2 or 3 (HUF, IDR, ISK, PKR, RSD, LBP, IQD), so a charge never carries
    /// digits the screen does not show. A well-formed code Foundation does not
    /// list gets the formatter's default, 2, logged once per code.
    nonisolated var minorUnitDigits: Int {
        if let cached = Self.digitsByCode.withLock({ $0[code] }) { return cached }
        let digits = Self.formatterDigits(for: code)
        Self.digitsByCode.withLock { $0[code] = digits }
        return digits
    }

    /// Per code, because every non-rouble balance read asks inside the
    /// service queue and a `NumberFormatter` is not cheap to build (#1163).
    nonisolated private static let digitsByCode = OSAllocatedUnfairLock(initialState: [String: Int]())

    nonisolated private static func formatterDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let digits = formatter.maximumFractionDigits
        if !knownCodes.contains(code), PriceContextLogOnce.first("unknownCode|\(code)") {
            AppLogger.emit(.balance, .default, "currency \(code) unknown to Foundation — \(digits) digits assumed")
        }
        return digits
    }

    nonisolated private static let knownCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))
}

/// Process-wide "first time?" for lines that would otherwise repeat on every
/// read of `priceContext`.
private nonisolated enum PriceContextLogOnce {
    private static let seen = OSAllocatedUnfairLock(initialState: Set<String>())

    static func first(_ key: String) -> Bool {
        seen.withLock { $0.insert(key).inserted }
    }
}
