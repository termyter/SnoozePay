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
        alarmID: String? = nil,
        createdAt: Date = Date(),
        refundsTransactionID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.alarmID = alarmID
        self.createdAt = createdAt
        self.refundsTransactionID = refundsTransactionID
    }

    /// Signed amount for debug / log output. An unrecognised row gets no sign
    /// — matching both UI sites, which refuse to assert a direction the ledger
    /// never stated.
    var formattedAmount: String {
        let prefix = type.isUnrecognized ? "" : (type.isDebit ? "-" : "+")
        return "\(prefix)\(MoneyFormatter.string(amount))"
    }

    // MARK: - Typed views (phase 1 of #31)

    /// Typed view of the transaction amount. `nil` if the legacy `Double`
    /// is negative or non-finite — old data may have leaked such values
    /// since the primitive API never validated.
    var money: Money? {
        Money(amount)
    }
}
