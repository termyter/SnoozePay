import Foundation
import os.log

/// Value type for monetary amounts.
///
/// Wraps `Decimal` (not `Double`) because money in floating-point accumulates
/// precision errors (`0.1 + 0.2 != 0.3`). All arithmetic here is exact within
/// `Decimal`'s 38-digit mantissa.
///
/// Invariants:
/// - amount is non-negative (negative money is never a valid balance/penalty
///   in this app — debits/credits are encoded by `Transaction.type`, not sign).
/// - amount is finite (no NaN/infinity sneak-ins from `Double` bridges).
/// - **an amount always carries the currency it is denominated in.** There is no
///   currency-less `Money`; a bare number is not an amount of money (#561).
///
/// The app never converts between currencies — there is no network and no rate
/// source (#559) — so mixing them is a programmer error, and every operation
/// that could mix them returns `nil` instead of a plausible wrong number.
///
/// Phase 1 of #31: introduced as a parallel API alongside the existing
/// `Double`-based API on `BalanceService` / `Alarm` / `Transaction`. Callers
/// will be migrated over a follow-up PR (phase 2).
struct Money: Equatable, Hashable, Codable {

    /// The non-negative monetary amount, denominated in `currency`.
    let amount: Decimal

    /// What the amount is denominated in. Never inferred at the point of use —
    /// legacy `Double` storage enters through `Money.legacy(_:)`.
    let currency: Currency

    // MARK: - Construction

    /// Failable init that enforces invariants:
    /// - rejects negative values
    /// - rejects NaN (Decimal has its own NaN representation, separate from Double)
    init?(_ amount: Decimal, currency: Currency) {
        guard !amount.isNaN, amount >= 0 else { return nil }
        self.amount = amount
        self.currency = currency
    }

    /// Internal init used by constants and arithmetic operators where the
    /// invariant is already established by the caller (e.g. literal `0`, or
    /// the sum of two already-validated `Money` values). Stays `private` so
    /// only `Money` itself can bypass validation.
    private init(unchecked amount: Decimal, currency: Currency) {
        self.amount = amount
        self.currency = currency
    }

    /// Convenience bridge from `Double`. Rejects NaN / infinite / negative
    /// before the conversion can silently round-trip into `Decimal`.
    init?(_ amount: Double, currency: Currency) {
        guard amount.isFinite, amount >= 0 else { return nil }
        self.init(Decimal(amount), currency: currency)
    }

    /// Convenience for integer literals — always valid for non-negative.
    init?(_ amount: Int, currency: Currency) {
        guard amount >= 0 else { return nil }
        self.init(Decimal(amount), currency: currency)
    }

    /// The additive identity in a given currency. Useful as a starting accumulator.
    static func zero(_ currency: Currency) -> Money {
        Money(unchecked: Decimal(0), currency: currency)
    }

    // MARK: - Legacy bridge

    /// The boundary with data that predates currencies: `BalanceService.balance`,
    /// `Alarm.penaltyAmount`, `Transaction.amount` are all bare `Double`s written
    /// when roubles were the only possibility. Those call sites — and only those —
    /// go through here, so the assumption is greppable in one hop
    /// (`Currency.legacyDefault`) rather than sprinkled as a default argument.
    static func legacy(_ amount: Double) -> Money? {
        Money(amount, currency: .legacyDefault)
    }

    /// See `legacy(_: Double)`.
    static func legacy(_ amount: Int) -> Money? {
        Money(amount, currency: .legacyDefault)
    }

    private static let log = OSLog(
        subsystem: "Ivan-Emelyanov.SnoozePay",
        category: "Money"
    )

    // MARK: - Bridges

    /// Lossy bridge for legacy Double-based APIs (`BalanceService.balance: Double`,
    /// `Alarm.penaltyAmount: Double`). Removed once phase 2 migrates callers.
    func toDouble() -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    // MARK: - Arithmetic

    /// Sum of two monetary amounts, or `nil` when they are not addable.
    ///
    /// Returns `nil` in two cases, both of which used to be impossible to see
    /// from the call site:
    /// - **different currencies** — 100 ₽ + 100 $ has no numeric answer without
    ///   a rate, and this app has none;
    /// - non-finite `Decimal` result (only reachable at the
    ///   `Decimal.greatestFiniteMagnitude` boundary — unreachable for real wallet
    ///   balances, but force-unwrapping there would crash a release build).
    static func + (lhs: Money, rhs: Money) -> Money? {
        guard lhs.currency == rhs.currency else { return nil }
        let sum = lhs.amount + rhs.amount
        if let result = Money(sum, currency: lhs.currency) {
            return result
        }
        os_log(
            "Money.+ produced invalid Decimal (overflow?); returning nil. lhs=%{public}@ rhs=%{public}@",
            log: Self.log, type: .fault,
            String(describing: lhs.amount), String(describing: rhs.amount)
        )
        return nil
    }

    /// Subtraction with saturating semantics — returns `nil` if the currencies
    /// differ or the result would be negative (i.e. would violate the invariant).
    /// Callers explicitly surface "insufficient funds" via the `nil` return
    /// rather than discovering it via a runtime trap.
    static func - (lhs: Money, rhs: Money) -> Money? {
        guard lhs.currency == rhs.currency else { return nil }
        return Money(lhs.amount - rhs.amount, currency: lhs.currency)
    }

    /// Multiplication by a non-negative *scalar* (e.g. progressive penalty
    /// doubling) — a scalar has no currency, so the result keeps this one.
    /// Returns `nil` if the multiplier is negative or NaN.
    func multiplied(by multiplier: Decimal) -> Money? {
        guard !multiplier.isNaN, multiplier >= 0 else { return nil }
        return Money(amount * multiplier, currency: currency)
    }

    // MARK: - Ordering

    // Ordering is `Bool?`, not `Bool`, and `Money` is deliberately not
    // `Comparable`: "is 100 ₽ more than 2 $" has no answer here. Returning
    // `false` would read as "no" and be wrong; returning `nil` cannot be
    // mistaken for an answer, because `if a < b` stops compiling.

    static func < (lhs: Money, rhs: Money) -> Bool? {
        guard lhs.currency == rhs.currency else { return nil }
        return lhs.amount < rhs.amount
    }

    static func <= (lhs: Money, rhs: Money) -> Bool? {
        guard lhs.currency == rhs.currency else { return nil }
        return lhs.amount <= rhs.amount
    }

    static func > (lhs: Money, rhs: Money) -> Bool? {
        guard lhs.currency == rhs.currency else { return nil }
        return lhs.amount > rhs.amount
    }

    static func >= (lhs: Money, rhs: Money) -> Bool? {
        guard lhs.currency == rhs.currency else { return nil }
        return lhs.amount >= rhs.amount
    }

    // MARK: - Formatting

    /// Localized formatted representation, e.g. "150 ₽" for a rouble amount in
    /// a Russian locale, "$150" for a dollar amount in `en_US`.
    ///
    /// Currency comes from the value; locale stays a parameter, because they are
    /// independent: a dollar amount shown to a Russian-speaking user is still
    /// dollars, formatted with Russian grouping. Defaults to the device locale so
    /// that localization (#569) does not have to unpick a hardcoded `ru_RU` here.
    /// Rounds to whole units by default (the app transacts integer amounts).
    func formatted(
        locale: Locale = .autoupdatingCurrent,
        fractionDigits: Int = 0
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.locale = locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? "\(amount) \(currency.code)"
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case amount
        case currency
    }

    /// Tolerates the pre-#561 shape (`{"amount": 150}`, no currency) by reading
    /// it as `Currency.legacyDefault`. This is not politeness: `TransactionRepository`
    /// treats any decoding failure as corruption and locks the whole ledger (#72),
    /// so a stricter decoder would not crash — it would quietly take a user's
    /// history away.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Decimal.self, forKey: .amount)
        let currency = try container.decodeIfPresent(Currency.self, forKey: .currency)
            ?? .legacyDefault
        guard let money = Money(amount, currency: currency) else {
            throw DecodingError.dataCorruptedError(
                forKey: .amount,
                in: container,
                debugDescription: "Money amount must be non-negative and finite, got \(amount)"
            )
        }
        self = money
    }
}
