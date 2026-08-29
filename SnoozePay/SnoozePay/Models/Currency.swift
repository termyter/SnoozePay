import Foundation

/// The currency of a monetary amount — ISO 4217 alpha-3, canonicalised to
/// upper case (`"RUB"`, `"USD"`).
///
/// ## Why a wrapper instead of `Locale.Currency`
///
/// `Locale.Currency` is what `StoreKit.Transaction.currency` hands us, and this
/// type bridges to it in both directions (`init?(_:)` / `localeCurrency`). It is
/// deliberately *not* used as the storage type itself, for two reasons:
///
/// - It validates nothing and is `ExpressibleByStringLiteral`, so
///   `Locale.Currency("руб")` and `Locale.Currency("rub")` both compile and both
///   look like currencies. Wallet currency is compared for equality (a purchase
///   in a foreign currency must be refused, #563) — and `"rub" != "RUB"` would
///   make that comparison silently fail open.
/// - Canonicalising on construction means the code stored on disk and the code
///   handed to `NumberFormatter` are the same string, whatever the source.
///
/// So: parse/validate once at the boundary, carry a known-good value afterwards.
struct Currency: Hashable, Codable, CustomStringConvertible {

    /// ISO 4217 alpha-3 code, upper case.
    let code: String

    // MARK: - Construction

    /// Fails for anything that is not three ASCII letters.
    ///
    /// The check is structural rather than a lookup in `Locale.Currency.isoCurrencies`:
    /// that list ships with the OS and lags currency changes, and rejecting a real
    /// storefront currency would be a worse failure than accepting an unknown but
    /// well-formed code. What it does catch is the class of mistakes that actually
    /// happens — localized names ("руб"), symbols ("₽"), empty strings.
    init?(code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 3,
              normalized.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        self.code = normalized
    }

    /// Bridge from StoreKit (`Transaction.currency` is a `Locale.Currency`).
    init?(_ currency: Locale.Currency) {
        self.init(code: currency.identifier)
    }

    /// Bridge back for Foundation APIs that speak `Locale.Currency`.
    var localeCurrency: Locale.Currency {
        Locale.Currency(code)
    }

    // MARK: - Known currencies

    static let rub = Currency(code: "RUB")!

    /// **The one place in the app where a currency is assumed rather than known.**
    ///
    /// Everything the app persisted before it knew about currencies is roubles:
    /// the store has only ever sold a rouble balance. Data written without a
    /// currency therefore decodes as this value, and nothing else may default
    /// — a wallet's real currency is established by its first paid top-up and
    /// then never changes (#563).
    static let legacyDefault = Currency.rub

    // MARK: - Description

    var description: String { code }

    // MARK: - Codable

    /// Encodes as a bare string (`"RUB"`), not as an object — the on-disk shape
    /// is the ISO code and nothing else, so it stays readable and stays stable
    /// if this type ever grows more members.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let currency = Currency(code: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(raw)\" is not an ISO 4217 alpha-3 currency code"
            )
        }
        self = currency
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}
