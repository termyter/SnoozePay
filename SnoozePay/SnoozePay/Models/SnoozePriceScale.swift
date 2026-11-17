import Foundation

/// The three snooze prices of one currency, cheapest first (#1109).
///
/// Outside roubles the scale is derived from the storefront's top-up packs, whose
/// prices Apple already localises: tier `low` = the cheapest pack, `mid` = the next,
/// `high` = the one after. There is no conversion and no hand-kept country table.
///
/// Roubles are the exception: their scale is the constant `rouble` (50 / 100 / 200)
/// and never comes from the catalogue, so a rouble user's prices cannot move when
/// pack prices do.
///
/// Encodes the tiers as decimal strings (`["0.99","1.99","2.99"]`), not numbers:
/// `JSONEncoder` routes `Decimal` through a binary float and can write `0.99` as
/// `0.98999999999999999`, which would then be charged.
nonisolated struct SnoozePriceScale: Equatable, Hashable, Codable, Sendable {

    /// Number of tiers in every scale — one per `SnoozePriceTier` case.
    static let tierCount = SnoozePriceTier.allCases.count

    let currency: Currency
    /// Exactly `tierCount` positive prices, strictly ascending.
    let tiers: [Decimal]

    // MARK: - Construction

    /// Fails unless `tiers` holds exactly three positive, finite, strictly
    /// ascending prices. A rouble scale is accepted only when it equals the
    /// constant — a cached or decoded rouble scale with other numbers is corrupt.
    init?(currency: Currency, tiers: [Decimal]) {
        guard tiers.count == Self.tierCount,
              tiers.allSatisfy({ !$0.isNaN && $0 > 0 }),
              zip(tiers, tiers.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        guard currency != .rub || tiers == Self.roubleTiers else { return nil }
        self.currency = currency
        self.tiers = tiers
    }

    private static let roubleTiers: [Decimal] = [50, 100, 200]

    /// 50 / 100 / 200 ₽ — constant, never derived from the catalogue.
    static let rouble = SnoozePriceScale(currency: .rub, tiers: roubleTiers)!

    /// The scale of a loaded storefront catalogue: the three cheapest distinct
    /// pack prices, ascending.
    ///
    /// `nil` when the offers disagree on currency (a scale has one currency and the
    /// app never converts), or when fewer than three distinct prices remain after
    /// de-duplication. Rouble offers yield the constant `rouble` scale: the RUB
    /// prices of the packs never become snooze prices.
    init?(offers: [TopUpOffer]) {
        guard let currency = offers.first?.currency,
              offers.allSatisfy({ $0.currency == currency }) else { return nil }
        if currency == .rub {
            self = .rouble
            return
        }
        var distinct: [Decimal] = []
        for price in offers.map(\.price).sorted() where distinct.last != price {
            distinct.append(price)
        }
        guard distinct.count >= Self.tierCount else { return nil }
        self.init(currency: currency, tiers: Array(distinct.prefix(Self.tierCount)))
    }

    // MARK: - Lookup

    /// The price of `tier` in this scale's currency.
    func price(for tier: SnoozePriceTier) -> Money? {
        Money(tiers[tier.rawValue - 1], currency: currency)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case currency, tiers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try container.decode(Currency.self, forKey: .currency)
        let raw = try container.decode([String].self, forKey: .tiers)
        let posix = Locale(identifier: "en_US_POSIX")
        let tiers = raw.compactMap { Decimal(string: $0, locale: posix) }
        guard tiers.count == raw.count,
              let scale = SnoozePriceScale(currency: currency, tiers: tiers) else {
            throw DecodingError.dataCorruptedError(
                forKey: .tiers, in: container,
                debugDescription: "Snooze price scale needs three ascending positive prices, got \(raw)"
            )
        }
        self = scale
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currency, forKey: .currency)
        try container.encode(tiers.map { NSDecimalNumber(decimal: $0).stringValue }, forKey: .tiers)
    }
}
