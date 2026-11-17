import Foundation
import os

/// What the firing screen charges, checks and shows as the next snooze price
/// (#1109 step 6a, #1137).
///
/// Every amount comes from `SnoozePriceResolver` in `lockedPriceContext`, the
/// wallet's price context read once when this ring's model was created. A
/// catalogue reload or a storefront change mid-ring therefore cannot move the
/// price the user was shown: the ring charges exactly what it rendered.
///
/// - The locked price does not resolve (`.unavailable`, or a number the resolver
///   refuses) → the existing "progression unavailable" state: no charge, no
///   guessed number, logged once at lock time; Stop is unaffected.
/// - The price resolves in a currency the wallet does not hold but would still
///   accept (a pristine wallet on a foreign storefront) → cannot afford, so the
///   top-up path stays reachable. Never a debit of a number denominated in
///   another currency.
/// - The price is in a currency the wallet can no longer accept (it froze in
///   another one mid-ring) → "progression unavailable" too: no top-up could
///   ever make the locked price payable, so none is offered.
///
/// Rouble wallets resolve `.amount` to the amount itself and the ladder in
/// `Decimal`, so charges and sufficiency equal `alarm.penalty(forSnoozeCount:)`.
extension AlarmFiringViewModel {

    // MARK: - Lock

    /// Reads the context of `wallet` once, for the whole ring, and logs a lock
    /// that cannot be charged. `nil` when the wallet supplies no context.
    static func lockPriceContext(
        of wallet: AlarmFiringBalancing, alarm: Alarm, snoozeCount: Int
    ) -> SnoozePriceContext? {
        let alarmID = alarm.id
        guard let provider = wallet as? AlarmFiringPriceContextProviding else {
            AppLogger.ui.notice(
                "firing: wallet supplies no price context alarm=\(alarmID, privacy: .private) — legacy amounts"
            )
            return nil
        }
        let context = provider.priceContext
        let resolved = SnoozePriceResolver.resolve(
            alarm.price, snoozeCount: snoozeCount + 1, isProgressive: alarm.progressiveScale, in: context
        )
        if case .unavailable(let currency) = context {
            AppLogger.ui.error(
                """
                firing: price unavailable in \(currency.code, privacy: .public) \
                alarm=\(alarmID, privacy: .private), snooze refused, no charge
                """
            )
        } else if resolved.flatMap({ MoneyDecimal.double($0.amount) }) == nil {
            AppLogger.ui.error(
                """
                firing: price does not resolve in \(context.currency.code, privacy: .public) \
                alarm=\(alarmID, privacy: .private), snooze refused, no charge
                """
            )
        } else if context.currency != wallet.walletCurrency {
            let priceCode = context.currency.code, walletCode = wallet.walletCurrency.code
            AppLogger.ui.notice(
                """
                firing: price locked in \(priceCode, privacy: .public), wallet in \
                \(walletCode, privacy: .public) alarm=\(alarmID, privacy: .private) — cannot afford until top-up
                """
            )
        }
        return context
    }

    // MARK: - Price as Money

    /// Price of the `count`-th snooze (1-based) in the locked context, or `nil`
    /// when it does not resolve. A wallet without a context keeps today's
    /// amount in the wallet's currency.
    func price(forSnoozeCount count: Int) -> Money? {
        guard let context = lockedPriceContext else {
            let legacy = MoneyFormatter.decimalForDisplay(alarm.penalty(forSnoozeCount: count))
            return Money(legacy, currency: walletCurrency)
        }
        return SnoozePriceResolver.resolve(
            alarm.price, snoozeCount: count, isProgressive: alarm.progressiveScale, in: context
        )
    }

    /// The price the next snooze charges, for step 6b to format in its own
    /// currency. `nil` while progression is unavailable.
    var currentPrice: Money? {
        isProgressionAvailable ? price(forSnoozeCount: snoozeCount + 1) : nil
    }

    /// The amount the `count`-th snooze debits, or `nil` to refuse.
    ///
    /// The `Double` crosses to `chargeWithReceipt` through the decimal text
    /// (`MoneyDecimal.double`), as in `AlarmFiringCoordinator.snoozeCharge`.
    /// Without a context the legacy `alarm.penalty` passes through untouched.
    func chargeAmount(forSnoozeCount count: Int) -> Double? {
        guard lockedPriceContext != nil else { return alarm.penalty(forSnoozeCount: count) }
        return price(forSnoozeCount: count).flatMap { MoneyDecimal.double($0.amount) }
    }

    // MARK: - State the screen reads

    /// The session allows a paid continuation, the locked price resolves, and
    /// the wallet holds or can still adopt the price's currency.
    var isProgressionAvailable: Bool {
        isSessionProgressionAvailable && chargeAmount(forSnoozeCount: snoozeCount + 1) != nil
            && !isLockedPriceStranded
    }

    /// The locked price is in a currency the wallet neither holds nor accepts
    /// any more: it froze in another currency mid-ring (a purchase after the
    /// catalogue loaded). Topping up cannot fix that, so the ring refuses
    /// instead of steering the user into purchases. Logged once per ring.
    var isLockedPriceStranded: Bool {
        guard lockedPriceContext != nil, let price = price(forSnoozeCount: snoozeCount + 1),
              price.currency != walletCurrency,
              !balanceService.acceptsPurchase(in: price.currency) else { return false }
        if !didLogStrandedPrice {
            didLogStrandedPrice = true
            let priceCode = price.currency.code, walletCode = walletCurrency.code, alarmID = alarm.id
            AppLogger.ui.error(
                """
                firing: price locked in \(priceCode, privacy: .public), wallet frozen in \
                \(walletCode, privacy: .public) alarm=\(alarmID, privacy: .private) — snooze refused, no charge
                """
            )
        }
        return true
    }

    /// The currency `snooze()` tells the wallet the next charge is priced in, or
    /// `nil` to refuse (#1136). Never the wallet's own currency as a fallback:
    /// that would switch the wallet's in-queue check off. `canSnooze` normally
    /// refuses first; this is the guard for a price that still does not resolve.
    func nextChargeCurrency() -> Currency? {
        if let currency = price(forSnoozeCount: snoozeCount + 1)?.currency { return currency }
        let alarmID = alarm.id
        AppLogger.ui.error("firing: snooze price unresolved alarm=\(alarmID, privacy: .private) — no charge")
        return nil
    }

    /// The next snooze's charge; `.nan` while progression is unavailable.
    var currentPenalty: Double {
        guard isProgressionAvailable else { return .nan }
        return chargeAmount(forSnoozeCount: snoozeCount + 1) ?? .nan
    }

    /// The locked price is denominated in the currency the wallet holds now
    /// (read live: a top-up on this screen can freeze the wallet mid-ring).
    var isLockedPricePayable: Bool {
        guard lockedPriceContext != nil else { return true }
        return price(forSnoozeCount: snoozeCount + 1)?.currency == walletCurrency
    }

    var canSnooze: Bool {
        isProgressionAvailable && isLockedPricePayable && balanceService.canAfford(currentPenalty)
    }

    /// Amount charged by the MOST RECENT snooze — the rung the user just paid
    /// for, in the locked context (`snooze()` bumps `snoozeCount` first). Drives
    /// the fly-up «−N ₽». `0` before the first snooze.
    ///
    /// A receipt, not a charge: when the locked price does not resolve, nothing
    /// in this ring was charged at all, and the receipt of an earlier ring keeps
    /// the legacy `alarm.penalty` until step 6b reads receipts from the ledger.
    var lastChargeAmount: Double {
        guard snoozeCount > 0 else { return 0 }
        return chargeAmount(forSnoozeCount: snoozeCount) ?? alarm.penalty(forSnoozeCount: snoozeCount)
    }

    /// The 4-rung progressive charge ladder for the snoozed state. Amounts are
    /// the doubling schedule `base, ×2, ×4, ×8` in the locked context (the same
    /// ceiling `SnoozePriceResolver` walks). State keys off `snoozeCount`: rungs
    /// strictly before it are `done` (already paid), the rung AT `snoozeCount`
    /// is `current` — the NEXT charge, matching the CTA's next-step price — and
    /// the rest are `future`. `snoozeCount` past the last rung clamps `current`
    /// to rung 4 so the ladder never blanks out at the ceiling. `[]` when the
    /// alarm isn't progressive, or when a rung's price does not resolve (no
    /// guessed amounts on the ladder).
    var ladderSteps: [LadderStep] {
        guard isProgressiveActive else { return [] }
        let resolved = (1...4).compactMap { chargeAmount(forSnoozeCount: $0) }
        guard resolved.count == 4 else { return [] }
        let currentIdx = min(snoozeCount, resolved.count - 1)
        return resolved.enumerated().map { idx, amount in
            let state: LadderStepState
            if idx < currentIdx {
                state = .done
            } else if idx == currentIdx {
                state = .current
            } else {
                state = .future
            }
            return LadderStep(amount: amount, state: state)
        }
    }
}

// MARK: - Display (#1142)

extension AlarmFiringViewModel {

    /// The currency every snooze price on the screen is shown in: the locked
    /// price's own. A pristine wallet on a dollar storefront reads "$0.99",
    /// never "0,99 ₽". A wallet without a context keeps its own currency.
    var priceCurrency: Currency { lockedPriceContext?.currency ?? walletCurrency }

    /// The `count`-th snooze price (1-based) formatted in its own currency, or
    /// `nil` when it does not resolve — nothing numeric is shown then.
    func priceText(forSnoozeCount count: Int) -> String? {
        guard let price = price(forSnoozeCount: count),
              let amount = MoneyDecimal.double(price.amount) else { return nil }
        return MoneyFormatter.quotedString(amount, currency: price.currency)
    }

    /// The Dawn background turns tense once the next price reaches the top tier
    /// of the ring's own scale: 200 ₽ in roubles (`SnoozePriceScale.rouble`, so
    /// every rouble amount keeps today's `>= 200` result), the third-cheapest
    /// pack elsewhere. Compared in the price's currency; a wallet without a
    /// context keeps the bare 200. `false` while progression is unavailable.
    var isPriceTense: Bool {
        guard isProgressiveActive else { return false }
        guard let context = lockedPriceContext else { return currentPenalty >= 200 }
        guard case .scale(let scale) = context, let price = currentPrice,
              let top = scale.price(for: .high) else { return false }
        return (price >= top) ?? false
    }
}

// MARK: - Price context seam

/// A wallet that knows its snooze-price context. `BalanceService` is one; a
/// test stub that only models balance is not, and keeps legacy amounts.
///
/// A separate protocol rather than a requirement of `AlarmFiringBalancing`, so
/// adding the context does not change every existing billing stub.
///
/// ⚠️ Any production `AlarmFiringBalancing` MUST conform: without it the
/// firing screen charges the legacy bare amount in whatever currency the
/// wallet holds, which is the pre-#1109 bug. A non-conforming wallet is logged
/// at lock time ("wallet supplies no price context").
protocol AlarmFiringPriceContextProviding: AnyObject {
    var priceContext: SnoozePriceContext { get }
}

extension BalanceService: AlarmFiringPriceContextProviding {}
