import Foundation
import StoreKit

/// Storefront offer for one SKU, distinct from the verified transaction credited later.
struct TopUpOffer {
    let productID: String
    let price: Decimal
    let currency: Currency
    let displayPrice: String

    init?(product: Product) {
        self.init(productID: product.id, price: product.price,
                  currencyCode: product.priceFormatStyle.currencyCode, displayPrice: product.displayPrice)
    }

    init?(productID: String, price: Decimal, currencyCode: String, displayPrice: String) {
        guard !price.isNaN, price > 0, let currency = Currency(code: currencyCode),
              !displayPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.productID = productID
        self.price = price
        self.currency = currency
        self.displayPrice = displayPrice
    }
}
