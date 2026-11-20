import Foundation
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

    /// Computed rather than `static let` for the reason `PluralForms` gives: a
    /// stored property freezes the copy at first access, which is harmless in
    /// the app but hides a catalogue miss behind whichever test ran first.
    static var alertTitle: String { Localized.text("deposit.foreign_currency.title") }

    /// The refusal for an unreadable ledger. It is shown before
    /// `Product.purchase(_:)`, so it says that top-ups are paused and that
    /// nothing was charged. `StoreKitService.ledgerLockedFailureMessage` is the
    /// post-charge copy: "couldn't credit the purchase" before any purchase
    /// reads as money taken and lost (#1182).
    static var ledgerUnreadableMessage: String { Localized.text("deposit.error.ledger_unreadable") }

    /// Message to show instead of starting the purchase, or `nil` when the
    /// purchase may proceed, for a refusal from
    /// `BalanceService.prePurchaseRefusal(in:)`. An
    /// unreadable ledger is named as such whatever the storefront sells: it is
    /// also what makes the wallet non-pristine, and a currency notice would
    /// send the user after the wrong problem (#1163).
    static func blockingMessage(
        for refusal: BalanceService.PurchaseRefusal?,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        switch refusal {
        case nil:
            return nil
        case .ledgerUnreadable?:
            return ledgerUnreadableMessage
        case let .foreignCurrency(wallet, storefront)?:
            return message(wallet: wallet, storefront: storefront, locale: locale)
        }
    }

    /// User-facing copy. Says what the wallet holds, what the store is selling,
    /// why the app will not bridge the two, and — the part that keeps this from
    /// reading as "your money is gone" — that the balance is still spendable.
    ///
    /// One catalogue entry with two positional arguments, not the six
    /// concatenated fragments this replaced (#598): a `+` between clauses is
    /// Russian sentence order written into Swift, and a translator cannot undo
    /// it. `locale` still governs the two *currency names*, which the OS
    /// localizes independently of the surrounding copy.
    static func message(
        wallet: Currency,
        storefront: Currency,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        Localized.format(
            "deposit.foreign_currency.message",
            name(of: wallet, locale: locale),
            name(of: storefront, locale: locale)
        )
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
        alert.addAction(
            UIAlertAction(title: Localized.text("deposit.foreign_currency.dismiss"), style: .default)
        )
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
