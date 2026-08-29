import Foundation
import StoreKit
import UIKit

/// The pre-purchase gate for a storefront whose currency is not the wallet's.
///
/// A wallet's currency is set by its first paid top-up and never changes
/// (#563). So a user whose storefront has since changed — moved country,
/// switched Apple Account region — can be offered products priced in a currency
/// the wallet cannot hold. Once `Product.purchase(_:)` has run it is too late
/// to be honest: crediting the catalogue number would turn $2.99 into 299 ₽
/// (#558), and crediting nothing keeps money for nothing. So the refusal
/// happens here, before the purchase sheet.
///
/// This blocks **topping up**, not the app: the existing balance stays
/// spendable, alarms keep firing and penalties keep being charged.
enum ForeignCurrencyNotice {

    static let alertTitle = "Другая валюта"

    /// The currency this product is priced in, or `nil` when StoreKit did not
    /// give us a usable one (`priceFormatStyle` falls back to an empty code
    /// when the price locale carries none).
    static func storefrontCurrency(of product: Product) -> Currency? {
        Currency(code: product.priceFormatStyle.currencyCode)
    }

    /// Message to show instead of starting the purchase, or `nil` when the
    /// purchase may proceed.
    ///
    /// Fails **open** on an unknown storefront currency: blocking a top-up we
    /// merely failed to identify would take the store away from a user whose
    /// wallet is perfectly fine.
    static func blockingMessage(
        for product: Product,
        balanceService: BalanceService = .shared,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let storefront = storefrontCurrency(of: product) else { return nil }
        guard !balanceService.acceptsPurchase(in: storefront) else { return nil }
        return message(
            wallet: balanceService.walletCurrency,
            storefront: storefront,
            locale: locale
        )
    }

    /// User-facing copy. Says what the wallet holds, what the store is selling,
    /// why the app will not bridge the two, and — the part that keeps this from
    /// reading as "your money is gone" — that the balance is still spendable.
    static func message(
        wallet: Currency,
        storefront: Currency,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "Валюта кошелька — \(name(of: wallet, locale: locale)). "
            + "App Store сейчас продаёт пакеты пополнения за другую валюту: "
            + "\(name(of: storefront, locale: locale)). "
            + "Пересчитать одно в другое приложение не может: курса у него нет, "
            + "а выдумывать курс для ваших денег оно не станет. "
            + "Пополнение в другой валюте недоступно. Остаток на балансе никуда не делся — "
            + "его можно тратить как обычно."
    }

    /// Ready-made alert for the top-up screens, so all three entry points show
    /// the same thing.
    @MainActor
    static func alert(message: String) -> UIAlertController {
        let alert = UIAlertController(
            title: alertTitle,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        return alert
    }

    /// `"российский рубль (RUB)"` when the OS can localize the code, `"RUB"` when it
    /// cannot — the code alone is still unambiguous, and an unknown-but-valid
    /// code is expected (`Currency` accepts codes newer than the OS's table).
    private static func name(of currency: Currency, locale: Locale) -> String {
        guard let localized = locale.localizedString(forCurrencyCode: currency.code),
              localized != currency.code else {
            return currency.code
        }
        return "\(localized) (\(currency.code))"
    }
}
