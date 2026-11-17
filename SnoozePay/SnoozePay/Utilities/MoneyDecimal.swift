import Foundation

/// Exact money arithmetic over the `Double`s that storage still holds (#1119).
///
/// Every amount is bridged to `Decimal` through its shortest round-trip text
/// (1.99 → "1.99" → 1.99), summed or compared there, and handed back through
/// text again. In binary floating point 1.99 + 1.99 − 2.99 − 0.99 is −2.2e-16
/// and 3.98 − 2.99 is 0.9899999999999998; in `Decimal` they are 0 and 0.99.
///
/// When an operand cannot be bridged (beyond `Decimal`'s 38 digits or its
/// exponent range) the operation falls back to plain `Double` arithmetic —
/// the behaviour before this type existed — rather than inventing a value.
nonisolated enum MoneyDecimal {

    /// Signed exact bridge. `.nan` when `amount` is non-finite or has no exact
    /// `Decimal` text; never a silently rounded neighbour.
    static func exact(_ amount: Double) -> Decimal {
        guard amount.isFinite else { return .nan }
        guard amount >= 0 else {
            let magnitude = exact(-amount)
            return magnitude.isNaN ? .nan : -magnitude
        }
        // Decimal(Double) can change even exact large integers. Keep their
        // fixed C-format digits; for fractions use Double's shortest text.
        let integral = amount.rounded(.towardZero) == amount
        let text = integral ? String(format: "%.0f", amount) : String(amount)
        if integral {
            // A successful Decimal parse may round beyond its 38-digit
            // precision. Exclude trailing zeros, which use only its exponent.
            let significantDigits = text.drop(while: { $0 == "0" })
                .reversed().drop(while: { $0 == "0" }).count
            guard significantDigits <= 38 else { return .nan }
        }
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN,
              Double(NSDecimalNumber(decimal: decimal).stringValue) == amount else { return .nan }
        return decimal
    }

    /// The `Double` whose text is `value`'s, or `nil` for NaN / overflow.
    static func double(_ value: Decimal) -> Double? {
        guard !value.isNaN,
              let result = Double(NSDecimalNumber(decimal: value).stringValue),
              result.isFinite else { return nil }
        return result
    }

    /// Exact Σ of `amounts`, or `nil` if any of them cannot be bridged.
    static func sum(_ amounts: [Double]) -> Decimal? {
        var total = Decimal(0)
        for amount in amounts {
            let term = exact(amount)
            guard !term.isNaN else { return nil }
            total += term
        }
        return total
    }

    static func adding(_ lhs: Double, _ rhs: Double) -> Double {
        sum([lhs, rhs]).flatMap(double) ?? lhs + rhs
    }

    static func subtracting(_ lhs: Double, _ rhs: Double) -> Double {
        sum([lhs, -rhs]).flatMap(double) ?? lhs - rhs
    }

    /// `balance >= amount`, decided on the decimal values the user sees.
    static func covers(_ balance: Double, _ amount: Double) -> Bool {
        let available = exact(balance), required = exact(amount)
        guard !available.isNaN, !required.isNaN else { return balance >= amount }
        return available >= required
    }
}
