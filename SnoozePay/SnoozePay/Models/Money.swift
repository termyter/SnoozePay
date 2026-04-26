import Foundation

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
///
/// Phase 1 of #31: introduced as a parallel API alongside the existing
/// `Double`-based API on `BalanceService` / `Alarm` / `Transaction`. Callers
/// will be migrated over a follow-up PR (phase 2).
struct Money: Equatable, Hashable, Codable {

    /// The non-negative monetary amount, in the app's single base currency (RUB).
    let amount: Decimal

    // MARK: - Construction

    /// Failable init that enforces invariants:
    /// - rejects negative values
    /// - rejects NaN (Decimal has its own NaN representation, separate from Double)
    init?(_ amount: Decimal) {
        guard !amount.isNaN, amount >= 0 else { return nil }
        self.amount = amount
    }

    /// Convenience bridge from `Double`. Rejects NaN / infinite / negative
    /// before the conversion can silently round-trip into `Decimal`.
    init?(_ amount: Double) {
        guard amount.isFinite, amount >= 0 else { return nil }
        self.init(Decimal(amount))
    }

    /// Convenience for integer literals — always valid for non-negative.
    init?(_ amount: Int) {
        guard amount >= 0 else { return nil }
        self.init(Decimal(amount))
    }

    /// The additive identity. Useful as a starting accumulator.
    static let zero: Money = Money(Decimal(0))!

    // MARK: - Bridges

    /// Lossy bridge for legacy Double-based APIs (`BalanceService.balance: Double`,
    /// `Alarm.penaltyAmount: Double`). Removed once phase 2 migrates callers.
    func toDouble() -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    // MARK: - Arithmetic

    /// Sum of two monetary amounts. Always non-negative since both operands are.
    static func + (lhs: Money, rhs: Money) -> Money {
        // Forced unwrap is safe: the sum of two non-negative non-NaN Decimals
        // is itself a non-negative non-NaN Decimal.
        Money(lhs.amount + rhs.amount)!
    }

    /// Subtraction with saturating semantics — returns `nil` if the result
    /// would be negative (i.e. would violate the invariant). Callers explicitly
    /// surface "insufficient funds" via the `nil` return rather than discovering
    /// it via a runtime trap.
    static func - (lhs: Money, rhs: Money) -> Money? {
        Money(lhs.amount - rhs.amount)
    }

    /// Multiplication by a non-negative scalar (e.g. progressive penalty
    /// doubling). Returns `nil` if the multiplier is negative or NaN.
    func multiplied(by multiplier: Decimal) -> Money? {
        guard !multiplier.isNaN, multiplier >= 0 else { return nil }
        return Money(amount * multiplier)
    }

    // MARK: - Ordering

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }

    static func <= (lhs: Money, rhs: Money) -> Bool {
        lhs.amount <= rhs.amount
    }

    static func > (lhs: Money, rhs: Money) -> Bool {
        lhs.amount > rhs.amount
    }

    static func >= (lhs: Money, rhs: Money) -> Bool {
        lhs.amount >= rhs.amount
    }

    // MARK: - Formatting

    /// Localized formatted representation, e.g. "150 ₽" for `currencyCode = "RUB"`
    /// in a Russian locale. Default rounds to whole units (the app currently
    /// transacts only integer rubles).
    func formatted(
        currencyCode: String = "RUB",
        locale: Locale = Locale(identifier: "ru_RU"),
        fractionDigits: Int = 0
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? "\(amount) \(currencyCode)"
    }
}
