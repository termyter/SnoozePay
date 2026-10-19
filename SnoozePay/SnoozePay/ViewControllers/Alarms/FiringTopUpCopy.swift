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
}
