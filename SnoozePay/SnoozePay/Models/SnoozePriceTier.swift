import Foundation

/// One of the three snooze prices a wallet outside roubles can choose from (#1109).
///
/// A tier is a position, not a number: `low` is the cheapest top-up pack of the
/// storefront, `mid` the second, `high` the third (`SnoozePriceScale`). In roubles
/// the same positions are the constant 50 / 100 / 200 ₽. The raw value is what an
/// alarm persists, so the cases must never be renumbered.
nonisolated enum SnoozePriceTier: Int, Codable, CaseIterable, Sendable {
    case low = 1
    case mid = 2
    case high = 3

    /// Upper bound (inclusive) of a legacy rouble amount read as `low`.
    static let legacyLowCeiling: Double = 50
    /// Upper bound (inclusive) of a legacy rouble amount read as `mid`.
    static let legacyMidCeiling: Double = 100

    /// Reads a legacy bare amount — written when every alarm was priced in roubles —
    /// as a tier, for a context where roubles are not the currency: `≤ 50 → low`,
    /// `≤ 100 → mid`, anything above → `high`. Nothing is rewritten on disk; the
    /// mapping happens at read time. `0` maps to `low` here, but the resolver never
    /// asks: a free alarm resolves to zero before this mapping (#1127).
    ///
    /// `nil` for a negative or non-finite amount: such a value was never a valid
    /// price, and guessing a tier for it would charge a number nobody chose.
    init?(legacyAmount amount: Double) {
        guard amount.isFinite, amount >= 0 else { return nil }
        if amount <= Self.legacyLowCeiling {
            self = .low
        } else if amount <= Self.legacyMidCeiling {
            self = .mid
        } else {
            self = .high
        }
    }
}

/// What an alarm's snooze costs, before it meets a currency.
///
/// - `tier` — chosen outside roubles; resolves against the wallet's scale.
/// - `amount` — the legacy rouble number (`Alarm.penaltyAmount`). In a rouble
///   context it is charged exactly as today; elsewhere it is read as a tier via
///   `SnoozePriceTier(legacyAmount:)` — except an amount ≤ 0, which stays free in
///   every currency (`SnoozePriceResolver.base`, #1127).
nonisolated enum SnoozePrice: Equatable, Sendable {
    case tier(SnoozePriceTier)
    case amount(Double)
}
