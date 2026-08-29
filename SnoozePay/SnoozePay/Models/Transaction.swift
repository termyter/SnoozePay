import Foundation

/// Type of balance transaction.
///
/// `topup` is reserved for IAP / paid-money credits that flow through Apple's
/// StoreKit pipeline — Statistics revenue accounting and any future receipt-
/// reconciliation logic keys off this case. `promotion` covers free credits
/// granted by in-app marketing flows (referrals, daily bonuses, etc.) so they
/// stay segregated from purchases the user actually paid for. `refund` is the
/// compensating credit posted when a snooze penalty was charged but the
/// scheduler refused the trigger — real money moves back into the wallet, but
/// no revenue was ever earned, so it must NOT be booked as a `topup`
/// (issue #358). `charge` is a debit (snooze penalty).
///
/// Persisted verbatim (as the raw string) into the `"stored_transactions"`
/// UserDefaults ledger, so the token set is an on-disk contract: rename a case
/// and every historic row becomes unreadable.
enum TransactionType: Codable, Equatable, Hashable {
    case topup
    case charge
    case promotion
    case refund
    /// Any token this build doesn't recognise, carrying the original string.
    ///
    /// `TransactionRepository` decodes the whole ledger as a single array and
    /// treats ANY decode failure as corruption (locks the ledger, see #72), so
    /// a strict enum turns one unreadable token into total ledger loss. This
    /// case keeps the surrounding rows readable, and because the raw string is
    /// carried along, re-encoding round-trips it losslessly rather than
    /// overwriting it with a sentinel.
    ///
    /// **This does NOT make `.refund` downgrade-safe.** A rollback to a
    /// pre-#358 build decodes with *that* build's strict `String`-backed enum,
    /// which has never heard of `.unknown` — the token `"refund"` throws there
    /// and locks the ledger. Adopting `.refund` is therefore one-way: once a
    /// user has posted one, rolling their build back bricks their wallet
    /// history until the ledger is cleared. The tolerance here only protects
    /// cases added *after* this build ships, plus in-place string damage to an
    /// otherwise valid blob.
    ///
    /// In production this case can only originate from ledger damage or such a
    /// future-version skew — both operationally interesting, so
    /// `TransactionRepository` logs and latches
    /// `lastLoadHadUnrecognizedTypes` when a load produces one. Aggregates
    /// deliberately ignore these rows (an unrecognised row can't be classified
    /// as credit or debit), which means a silently-tolerated one would make
    /// on-screen totals disagree with `user_balance` — hence the flag.
    ///
    /// Never constructed by app code.
    case unknown(String)

    /// Stable persisted token.
    var rawValue: String {
        switch self {
        case .topup: return "topup"
        case .charge: return "charge"
        case .promotion: return "promotion"
        case .refund: return "refund"
        case .unknown(let raw): return raw
        }
    }

    /// Non-failable by design — unrecognised tokens land in `.unknown` rather
    /// than `nil` (see the case documentation).
    init(rawValue: String) {
        switch rawValue {
        case "topup": self = .topup
        case "charge": self = .charge
        case "promotion": self = .promotion
        case "refund": self = .refund
        default: self = .unknown(rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// `true` when the transaction takes money out of the wallet. `.unknown`
    /// is NOT a debit, but it isn't a credit either — check `isUnrecognized`
    /// before reading this as "money in".
    var isDebit: Bool { self == .charge }

    /// `true` for a token this build can't classify — UI renders such rows
    /// without a +/− sign because the direction is genuinely unknown.
    var isUnrecognized: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// Domain model for a balance transaction
struct Transaction: Identifiable, Codable {
    let id: UUID
    let type: TransactionType
    let amount: Double
    /// What `amount` is denominated in (#562).
    ///
    /// A ledger row states its own currency instead of inheriting the wallet's:
    /// the wallet's currency can be established later (#563) and a historic row
    /// must keep meaning what it meant when it was written. There is no
    /// conversion anywhere in the app (#559), so a row in another currency is
    /// carried and shown as written — never restated in roubles.
    ///
    /// Absent from every row written before this change. The default lands in
    /// exactly two places, both named `Currency.legacyDefault`: `init(from:)`
    /// below (the decoding boundary) and the memberwise `init` (whose default
    /// serves legacy call sites and tests — `BalanceService`, the only writer in
    /// production, passes its `walletCurrency` explicitly).
    let currency: Currency
    let alarmID: String?
    let createdAt: Date
    /// When this transaction is a `refund` posted to offset a failed snooze
    /// schedule, points back at the original `charge` so stats consumers can
    /// exclude both rows from snooze counts / streak resets (issue #133).
    /// `nil` for organic top-ups and for legacy ledger entries written before
    /// the field existed — those continue to count as real charges/top-ups.
    /// Ledgers written before #358 carry this link on a `.topup` row instead;
    /// consumers key off the link, not the type, so both shapes still pair up.
    let refundsTransactionID: UUID?

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Double,
        currency: Currency = .legacyDefault,
        alarmID: String? = nil,
        createdAt: Date = Date(),
        refundsTransactionID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.currency = currency
        self.alarmID = alarmID
        self.createdAt = createdAt
        self.refundsTransactionID = refundsTransactionID
    }

    /// Signed amount for debug / log output. An unrecognised row gets no sign
    /// — matching both UI sites, which refuse to assert a direction the ledger
    /// never stated.
    var formattedAmount: String {
        let prefix = type.isUnrecognized ? "" : (type.isDebit ? "-" : "+")
        return "\(prefix)\(renderedAmount)"
    }

    /// `MoneyFormatter` is the rouble renderer (`fmtRub`: grouped digits, narrow
    /// space, `₽`) — it hardcodes the glyph, so it may only be handed rouble
    /// rows. Anything else goes through `Money.formatted()`, which labels the
    /// amount with its own currency: with no rate source (#559), a dollar row
    /// printed as "50 ₽" would not be a rounding error, it would be a wrong
    /// number.
    private var renderedAmount: String {
        guard currency == .rub else {
            return money?.formatted() ?? "\(amount) \(currency.code)"
        }
        return MoneyFormatter.string(amount)
    }

    // MARK: - Typed views (phase 1 of #31)

    /// Typed view of the transaction amount, denominated in the row's own
    /// `currency` (#562). `nil` if the stored `Double` is negative or
    /// non-finite — old data may have leaked such values since the primitive
    /// API never validated.
    var money: Money? {
        Money(amount, currency: currency)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case amount
        case currency
        case alarmID
        case createdAt
        case refundsTransactionID
    }

    /// Hand-written so the *absence* of `currency` is tolerated: every row in
    /// every existing install predates the field, and `TransactionRepository`
    /// treats any decode failure as corruption of the whole ledger (#72). A
    /// synthesized decoder would therefore not have thrown a visible error on
    /// upgrade — it would have quietly locked every user's history.
    ///
    /// A `currency` that is *present but unparseable* still throws, unlike an
    /// unrecognised `type` token (#358). The asymmetry is deliberate: an
    /// unknown type is excluded from every aggregate, so tolerating it moves no
    /// money, whereas silently reading a damaged currency as roubles would fold
    /// the row's amount into a rouble wallet. Between "loud, recoverable lock
    /// with the blob preserved" and "silently wrong balance", this field sits on
    /// the same side as `id`, `amount` and `createdAt`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(TransactionType.self, forKey: .type)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decodeIfPresent(Currency.self, forKey: .currency) ?? .legacyDefault
        alarmID = try container.decodeIfPresent(String.self, forKey: .alarmID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        refundsTransactionID = try container.decodeIfPresent(UUID.self, forKey: .refundsTransactionID)
    }

    /// Written out rather than synthesized so the on-disk shape stays an
    /// explicit statement: optionals are omitted (not `null`) exactly as the
    /// synthesized encoder did, and `currency` is always written — a row whose
    /// currency is implicit is what this change exists to stop producing.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encodeIfPresent(alarmID, forKey: .alarmID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(refundsTransactionID, forKey: .refundsTransactionID)
    }
}
