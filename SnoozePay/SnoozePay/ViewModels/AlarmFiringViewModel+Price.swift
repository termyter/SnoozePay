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
/// - The price resolves in a currency the wallet does not hold (a pristine
///   wallet on a foreign storefront) → cannot afford, so the top-up path stays
///   reachable. Never a debit of a number denominated in another currency.
///
/// Rouble wallets resolve `.amount` to the amount itself and the ladder in
/// `Decimal`, so charges and sufficiency equal `alarm.penalty(forSnoozeCount:)`.
extension AlarmFiringViewModel {

    // MARK: - Lock

    /// Reads the context of `wallet` once, for the whole ring, and logs a lock
    /// that cannot be charged. `nil` when the wallet supplies no context.
    static func lockPriceContext(of wallet: AlarmFiringBalancing, alarm: Alarm) -> SnoozePriceContext? {
        guard let provider = wallet as? AlarmFiringPriceContextProviding else { return nil }
        let context = provider.priceContext
        let alarmID = alarm.id
        if case .unavailable(let currency) = context {
            AppLogger.ui.error(
                """
                firing: price unavailable in \(currency.code, privacy: .public) \
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

    /// The session allows a paid continuation AND the locked price resolves.
    var isProgressionAvailable: Bool {
        isSessionProgressionAvailable && chargeAmount(forSnoozeCount: snoozeCount + 1) != nil
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

// MARK: - Price context seam

/// A wallet that knows its snooze-price context. `BalanceService` is one; a
/// test stub that only models balance is not, and keeps legacy amounts.
///
/// A separate protocol rather than a requirement of `AlarmFiringBalancing`, so
/// adding the context does not change every existing billing stub.
protocol AlarmFiringPriceContextProviding: AnyObject {
    var priceContext: SnoozePriceContext { get }
}

extension BalanceService: AlarmFiringPriceContextProviding {}
