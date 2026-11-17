import Foundation

/// Recommendation for one next charge, never a forecast of future snoozes.
enum FiringTopUpCopy {
    static func coversNextCharge(
        offer: TopUpOffer, balance: Double, price: Double, walletCurrency: Currency
    ) -> Bool? {
        guard offer.currency == walletCurrency, balance.isFinite, balance >= 0, price.isFinite, price > 0 else {
            return nil
        }
        var current = MoneyFormatter.decimalForDisplay(balance)
        let required = MoneyFormatter.decimalForDisplay(price)
        guard !current.isNaN, !required.isNaN else { return nil }
        var paid = offer.price
        var total = Decimal()
        guard NSDecimalAdd(&total, &current, &paid, .plain) == .noError else { return nil }
        return total >= required
    }

    /// Compare actual offers only within one currency. Unknown arithmetic uses
    /// the cheapest offer; when none covers a known charge, use the largest.
    static func recommendedProductID(
        offers: [TopUpOffer], balance: Double, price: Double, walletCurrency: Currency
    ) -> String? {
        guard let first = offers.first, offers.allSatisfy({ $0.currency == first.currency }) else { return nil }
        let sorted = offers.sorted { $0.price == $1.price ? $0.productID < $1.productID : $0.price < $1.price }
        let coverage = sorted.map { coversNextCharge(offer: $0, balance: balance, price: price,
                                                   walletCurrency: walletCurrency) }
        guard coverage.allSatisfy({ $0 != nil }) else { return sorted.first?.productID }
        return zip(sorted, coverage).first { $0.1 == true }?.0.productID ?? sorted.last?.productID
    }

    /// The pack both firing entry points pick (#652): the amount sheet opens on
    /// it and the direct no-balance CTA buys it. Offers the wallet refuses only
    /// stand in when nothing else exists, so the tap can explain the refusal.
    static func preselectedOffer(
        offers: [TopUpOffer], balance: Double, price: Double, walletCurrency: Currency,
        acceptsPurchase: (Currency) -> Bool
    ) -> TopUpOffer? {
        let compatible = offers.filter { acceptsPurchase($0.currency) }
        let productID = recommendedProductID(offers: compatible, balance: balance, price: price,
                                             walletCurrency: walletCurrency) ?? offers.first?.productID
        return offers.first { $0.productID == productID }
    }

    /// The rows the firing sheet offers (#1112): the minimal pack of the whole
    /// catalogue covering the next charge is always one of them. When the
    /// defaults lack it, it replaces the dearest non-popular default cheaper than
    /// it (else the cheapest non-popular one), so three rows stay sorted by price
    /// and the popular row stays put. No sufficient pack, unknown coverage
    /// (including a wallet/storefront currency mismatch) or an unpriced default
    /// keep the defaults untouched.
    static func offeredProductIDs(
        defaults: [String], popular: Set<String>, catalogue: [TopUpOffer], balance: Double, price: Double,
        walletCurrency: Currency, acceptsPurchase: (Currency) -> Bool
    ) -> [String] {
        let compatible = catalogue.filter { acceptsPurchase($0.currency) }.sorted(by: cheaperFirst)
        let coverage = compatible.map { coversNextCharge(offer: $0, balance: balance, price: price,
                                                        walletCurrency: walletCurrency) }
        guard coverage.allSatisfy({ $0 != nil }),
              let pick = zip(compatible, coverage).first(where: { $0.1 == true })?.0,
              !defaults.contains(pick.productID) else { return defaults }
        let priced = defaults.compactMap { id in compatible.first { $0.productID == id } }
        let replaceable = priced.filter { !popular.contains($0.productID) }
        guard priced.count == defaults.count,
              let victim = replaceable.last(where: { cheaperFirst($0, pick) }) ?? replaceable.first else {
            return defaults
        }
        let rows = priced.filter { $0.productID != victim.productID } + [pick]
        return rows.sorted(by: cheaperFirst).map(\.productID)
    }

    private static func cheaperFirst(_ lhs: TopUpOffer, _ rhs: TopUpOffer) -> Bool {
        lhs.price == rhs.price ? lhs.productID < rhs.productID : lhs.price < rhs.price
    }
}
