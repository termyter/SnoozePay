import Foundation

/// Outcome of an attempt to establish the wallet's currency.
///
/// Not a `Bool` and not a silent no-op on purpose: writing a *different*
/// currency over an established one is a programmer error, and the only way to
/// notice it at the call site is for the call site to be forced to look. The
/// result is therefore not `@discardableResult` anywhere it is produced —
/// ignoring it does not compile cleanly.
enum WalletCurrencyFreeze: Equatable {

    /// The wallet had no currency; it now has this one. The first paid top-up.
    case frozen(Currency)

    /// The wallet already held exactly this currency — idempotent replay of a
    /// freeze (StoreKit re-delivering a transaction, a second top-up in the
    /// same storefront). Nothing was written.
    case unchanged(Currency)

    /// The wallet already holds `existing` and `attempted` is something else.
    /// **Nothing was written.** There is no conversion in this app (#559), so
    /// re-denominating a wallet would silently restate every amount in it —
    /// including `Alarm.penaltyAmount`, which is stored in the same units as
    /// the balance (a `50` penalty configured in roubles must not become $50).
    case refused(existing: Currency, attempted: Currency)
}

/// Persistence for the one fact a wallet learns exactly once: what currency it
/// is denominated in.
///
/// ## The rule
///
/// The currency is established by the **first paid top-up** (from
/// `StoreKit.Transaction.currency`) and then never changes (#563). Absence of a
/// record reads as `Currency.legacyDefault` — everything the app persisted
/// before it knew about currencies is roubles, because the store has only ever
/// sold a rouble balance.
///
/// ## Why a separate type rather than two lines in `BalanceService`
///
/// `BalanceService.walletCurrency` is read from *inside* its serial queue
/// (every ledger row is stamped with it, and the derived balance sums only rows
/// that match it — #562). Anything it calls must therefore be free of
/// `queue.sync`. Keeping the storage here, behind its own lock, makes that
/// property structural instead of a comment someone has to remember.
final class WalletCurrencyStore {

    /// `UserDefaults` key, named alongside `user_balance` / `stored_alarms` /
    /// `stored_transactions`. Stores the bare ISO code (`"RUB"`), not JSON, so
    /// the value stays readable in a defaults dump and cannot fail to decode
    /// as a whole document.
    static let storageKey = "wallet_currency"

    private let defaults: UserDefaults
    /// Serialises read-then-write inside `freeze(_:)`. Two concurrent first
    /// top-ups are not reachable today (StoreKit credit paths are `@MainActor`),
    /// but "first write wins" is the entire contract of this type — it should
    /// not depend on the caller's threading staying the way it is.
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Read

    /// The currency recorded for this wallet, or `nil` when none has been
    /// established yet (fresh install, or a legacy wallet that predates #563).
    ///
    /// An unreadable value (hand-edited defaults, a localized name instead of a
    /// code) reads as `nil` rather than trapping: the wallet then behaves as a
    /// legacy rouble wallet, which is what it was before the bad write.
    var storedCurrency: Currency? {
        guard let raw = defaults.string(forKey: Self.storageKey) else { return nil }
        guard let currency = Currency(code: raw) else {
            AppLogger.balance.error(
                """
                wallet_currency holds \(raw, privacy: .public), which is not an \
                ISO 4217 code — treating the wallet as unset
                """
            )
            return nil
        }
        return currency
    }

    /// The currency to denominate this wallet's amounts in. Never `nil`: an
    /// unset wallet is a rouble wallet until its first paid top-up says
    /// otherwise (`Currency.legacyDefault`).
    var currency: Currency {
        storedCurrency ?? .legacyDefault
    }

    // MARK: - Write (once)

    /// Records the wallet's currency if it does not have one yet.
    ///
    /// Never overwrites: see `WalletCurrencyFreeze.refused`. The refusal is
    /// logged at `fault` level because reaching it means a foreign-currency
    /// purchase got past the pre-purchase gate — money has already changed
    /// hands by then, and that is worth a signal in the logs rather than a
    /// return value someone might drop.
    func freeze(_ currency: Currency) -> WalletCurrencyFreeze {
        lock.lock()
        defer { lock.unlock() }

        if let existing = storedCurrency {
            guard existing == currency else {
                AppLogger.balance.fault(
                    """
                    refused to re-denominate wallet from \(existing.code, privacy: .public) \
                    to \(currency.code, privacy: .public) — wallet currency is set once
                    """
                )
                return .refused(existing: existing, attempted: currency)
            }
            return .unchanged(existing)
        }

        defaults.set(currency.code, forKey: Self.storageKey)
        AppLogger.balance.notice(
            "wallet currency established as \(currency.code, privacy: .public)"
        )
        return .frozen(currency)
    }
}
