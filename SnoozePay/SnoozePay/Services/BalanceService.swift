import Foundation
import os

/// Manages the user's local balance stored in UserDefaults.
/// All operations are synchronous and offline-first.
///
/// The balance is **derived from the ledger** — `openingBalance + Σ(rows)` via
/// `BalanceLedgerStore` (#483). `user_balance` is kept as a cache of that sum
/// so every existing reader keeps working, but the rows are what count: a
/// replayed `Transaction.id` credits nothing, and a cache that disagrees with
/// the ledger is repaired on read.
/// Mutations and reads are serialized via a private serial queue
/// to prevent check-then-write races between concurrent callers
/// (e.g. notification action + foreground UI).
final class BalanceService {

    static let shared = BalanceService()

    /// Broadcast on every successful balance mutation (charge / topUp).
    /// Multiple observers may subscribe simultaneously — each is independent
    /// and must remove its own observer in `deinit` (or rely on
    /// `NotificationCenter`'s automatic cleanup of dealloc'd weak observers).
    /// `userInfo[Self.balanceUserInfoKey]` carries the new balance as `Double`.
    static let balanceChangedNotification = Notification.Name("snoozepay.balance.changed")
    static let balanceUserInfoKey = "balance"

    /// Broadcast once per process when a negative `user_balance` is observed
    /// in storage (concurrent write race, downgrade, manual tampering — see
    /// issue #119). UI surfaces an alert and offers the user to wipe the
    /// corrupt value via `acknowledgeCorruption()` (future Settings entry,
    /// see #102). Mirrors the locked-ledger pattern from #72.
    static let balanceCorruptedNotification = Notification.Name("snoozepay.balance.corrupted")
    /// Carries the raw negative `Double` that was read from storage so the
    /// UI / support tooling can display what was found.
    static let balanceCorruptedRawValueKey = "rawValue"

    private let defaults: UserDefaults
    private let balanceKey = "user_balance"
    /// What this wallet's amounts are denominated in — established by the first
    /// paid top-up, then fixed (#563). Deliberately free of `queue.sync`: it is
    /// read from inside the serial queue while stamping ledger rows.
    private let currencyStore: WalletCurrencyStore
    /// Source of truth for the balance (#483): every mutation is an append
    /// here, and `user_balance` is a cache of `openingBalance + Σ(ledger)`.
    private let ledgerStore: BalanceLedgerStore
    private let queue = DispatchQueue(label: "com.snoozepay.balance.serial")
    private let notificationCenter: NotificationCenter
    private static let log = OSLog(
        subsystem: AppLogger.subsystem,
        category: "BalanceService"
    )

    /// Set inside `queue.sync` whenever a negative raw balance is observed.
    /// While true, `charge`/`topUp` refuse to mutate storage so the corrupt
    /// value is not overwritten before the user has a chance to acknowledge
    /// the loss (mirrors `TransactionRepository._lastLoadFailed`, issue #72).
    private var _balanceCorrupted: Bool = false
    var balanceCorrupted: Bool { queue.sync { _balanceCorrupted } }

    /// The raw invalid value that latched `balanceCorrupted`, kept until the
    /// user acknowledges via `acknowledgeCorruption()`. `nil` while healthy.
    ///
    /// `balanceCorruptedNotification` is posted once per process and
    /// `NotificationCenter` does not retro-deliver: when corruption is
    /// detected by the init-time probe (cold start, before any UI exists)
    /// the event is dropped for late subscribers. This queryable seam lets a
    /// late-registering observer (e.g. `AlarmsListViewModel.loadData()`) pull
    /// the pending corruption state after attaching, so the user-facing alert
    /// still fires (#206).
    private var _corruptedRawValue: Double?
    var corruptedRawValue: Double? { queue.sync { _corruptedRawValue } }

    /// Production code MUST use `BalanceService.shared` to avoid creating
    /// isolated instances with separate serial queues (which reintroduces the
    /// race this class exists to prevent).
    ///
    /// Tests inject a custom `UserDefaults` suite to stay isolated from app
    /// state — that's why this initializer is `internal`. The `transactionRepository`
    /// argument has no default to keep test ledgers explicit; tests that don't
    /// care about the ledger pass `TransactionRepository(defaults: testDefaults)`.
    init(
        defaults: UserDefaults,
        transactionRepository: TransactionRepository,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.currencyStore = WalletCurrencyStore(defaults: defaults)
        self.ledgerStore = BalanceLedgerStoreFactory.makeStore(
            repository: transactionRepository,
            defaults: defaults
        )
        self.notificationCenter = notificationCenter
        // Detect corruption at construction time so the gate is set BEFORE any
        // background `charge` (notification action handler) can silently hit the
        // refusal branch with no observer in place. Without this probe the
        // `balanceCorruptedNotification` fires only on the FIRST balance read,
        // which can happen on a background thread before any UI listener is
        // attached — `NotificationCenter.post` does not retro-deliver to late
        // subscribers, so the alert would be dropped.
        _ = queue.sync { readRawBalance() }
    }

    /// Convenience for tests that supply only `defaults`: builds a matching
    /// ledger pinned to the same suite so charges land in the test store.
    convenience init(
        defaults: UserDefaults,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            defaults: defaults,
            transactionRepository: TransactionRepository(defaults: defaults),
            notificationCenter: notificationCenter
        )
    }

    private convenience init() {
        self.init(
            defaults: .standard,
            transactionRepository: .shared,
            notificationCenter: .default
        )
    }

    // MARK: - Read

    var balance: Double {
        queue.sync { readRawBalance() }
    }

    // MARK: - Deduct (snooze penalty)

    /// Attempts to charge the given amount from balance.
    /// Returns true if successful, false if insufficient funds OR if the
    /// stored balance is corrupted (negative). When corrupted, the caller
    /// should surface `balanceCorruptedNotification` UX and route the user
    /// to `acknowledgeCorruption()` before any further wallet mutation
    /// (mirrors locked-ledger pattern from #72).
    @discardableResult
    func charge(amount: Double, alarmID: UUID?) -> Bool {
        chargeWithReceipt(amount: amount, alarmID: alarmID) != nil
    }

    /// Charge variant that returns the persisted `Transaction` so the caller
    /// can later post a refund linked to this exact ledger entry (issue #133).
    /// Returns `nil` on the same failure modes as `charge` — insufficient
    /// funds, corrupted balance, or repository write rejection.
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        // Reject non-finite / non-positive amounts up front, matching
        // `creditPromotion`'s contract (#441). Without this a negative amount
        // passes the `current >= amount` guard and records a `.charge` that
        // INCREASES the balance (and injects a phantom snooze day into
        // streak/stats); a NaN would persist into storage before the read-time
        // corruption guard catches it.
        guard amount.isFinite, amount > 0 else { return nil }
        let transaction = Transaction(
            type: .charge,
            amount: amount,
            currency: walletCurrency,
            alarmID: alarmID?.uuidString
        )
        let result: (charged: Bool, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted else { return (false, current) }
            guard current >= amount else { return (false, current) }

            // The ledger append IS the mutation (#483). If the store is locked
            // (corrupt blob waiting on user ack), encoding fails, or the row is
            // a replay of one already present, the balance must not move —
            // otherwise money disappears from the wallet with no record in
            // stats (see #72 hunter review of PR #101).
            guard ledgerStore.append(transaction) == .recorded else {
                return (false, current)
            }

            // Recompute from the ledger rather than `current - amount`: the sum
            // over the rows is the balance, and this call also refreshes the
            // `user_balance` cache.
            return (true, readRawBalance())
        }

        if result.charged {
            notifyBalanceChanged(result.newBalance)
            return transaction
        }
        return nil
    }

    // MARK: - Top up (IAP)

    /// Returns `true` if the credit landed (balance moved AND ledger updated).
    /// Returns `false` when the transaction repository is locked, encoding
    /// failed, or the stored balance is corrupted (negative — see #119) —
    /// caller should surface this to the user instead of pretending
    /// the IAP credited (silent ledger desync was the regression behind the #72
    /// PR #101 hunter feedback).
    ///
    /// Paid credits ONLY. A penalty reversal must go through `refund` — routing
    /// it here books phantom IAP revenue (issue #358), which is why this method
    /// no longer accepts a `refundsTransactionID`.
    @discardableResult
    func topUp(amount: Double) -> Bool {
        credit(type: .topup, amount: amount)
    }

    // MARK: - Refund (reversal of a snooze penalty)

    /// Returns a charged penalty to the wallet and records a `.refund` ledger
    /// entry. Used when the penalty was debited but `AlarmScheduler` then
    /// refused the snooze trigger, so the user must not stay billed for a
    /// snooze that will never re-fire (issues #197 / #366).
    ///
    /// The dedicated `TransactionType.refund` case exists because this credit
    /// is *not* income: booking it as `.topup` made every reversal show up as
    /// paid IAP revenue and inflated the Пополнения aggregate by the refunded
    /// amount (issue #358).
    ///
    /// `refundsTransactionID` links back to the exact `charge` being reversed
    /// so `TransactionRepository.realCharges(from:)` can drop the pair from
    /// snooze counts / streak (issue #133). Returns `false` on the same failure
    /// modes as `topUp` — a locked ledger or corrupted balance means the refund
    /// did NOT land and the caller must surface a wallet-desync warning.
    @discardableResult
    func refund(amount: Double, refundsTransactionID: UUID? = nil) -> Bool {
        credit(type: .refund, amount: amount, refundsTransactionID: refundsTransactionID)
    }

    // MARK: - Promotional credit (referral, daily bonus, ...)

    /// Credits the wallet from a non-monetary source (referral bonus, daily
    /// streak reward, ...) and records a `.promotion` ledger entry. Behaves
    /// like `topUp` w.r.t. corruption gating and ledger-first ordering, but
    /// the dedicated `TransactionType.promotion` case keeps these credits out
    /// of any future StoreKit receipt-reconciliation / revenue accounting
    /// logic that keys off `.topup` (issue #144).
    @discardableResult
    func creditPromotion(amount: Double) -> Bool {
        credit(type: .promotion, amount: amount)
    }

    /// Shared implementation behind every credit (`topUp` / `refund` /
    /// `creditPromotion`). Only the ledger `type` differs — the corruption
    /// gating, amount validation and ledger-first ordering are identical and
    /// must stay that way, so they live in one place.
    private func credit(
        type: TransactionType,
        amount: Double,
        createdAt: Date = Date(),
        refundsTransactionID: UUID? = nil
    ) -> Bool {
        // Reject non-finite / non-positive amounts (#441): a negative credit
        // would record a positive-typed row while DECREASING the balance
        // (ledger/balance divergence that can drive `user_balance` negative and
        // latch #119 corruption); a NaN would persist into storage before the
        // read-time guard fires.
        guard amount.isFinite, amount > 0 else { return false }

        let result: (recorded: Bool, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted else { return (false, current) }

            let transaction = Transaction(
                type: type,
                amount: amount,
                currency: walletCurrency,
                createdAt: createdAt,
                refundsTransactionID: refundsTransactionID
            )
            // Ledger first: if the store is locked (corrupt blob awaiting user
            // ack), encoding fails, or the row is a replay of an id already in
            // the ledger, the balance must not move — an unrecorded credit is a
            // silent desync (#72), a replayed one is double-crediting (#483).
            guard ledgerStore.append(transaction) == .recorded else {
                return (false, current)
            }
            return (true, readRawBalance())
        }

        if result.recorded {
            notifyBalanceChanged(result.newBalance)
        }
        return result.recorded
    }

    // MARK: - Validation

    func canAfford(_ amount: Double) -> Bool {
        queue.sync { readRawBalance() >= amount }
    }

    // MARK: - Recovery (corruption)

    /// Resets `user_balance` to `0` and clears the corruption flag. Called by
    /// the future Settings "Стереть повреждённые данные" button (see #102)
    /// after the user has acknowledged the loss. The notification is posted
    /// so observers can refresh their view of the wallet to the new zero state.
    func acknowledgeCorruption() {
        let cleared: Bool = queue.sync {
            guard _balanceCorrupted else { return false }
            defaults.set(0.0, forKey: balanceKey)
            // The cache alone isn't the wallet any more — without re-pinning
            // the opening balance the ledger would derive the pre-wipe number
            // straight back on the next read (#483).
            rebaseLedger(to: 0)
            _balanceCorrupted = false
            _corruptedRawValue = nil
            return true
        }
        if cleared {
            notifyBalanceChanged(0)
        }
    }

    // MARK: - Typed API (phase 1 of #31)
    //
    // Money-based wrappers around the existing Double API. Storage stays
    // Double for backward compatibility with persisted UserDefaults until
    // phase 2 migrates it. These wrappers reject invalid amounts (negative,
    // NaN, infinite) at the type-system level rather than allowing them
    // through and corrupting the ledger.

    /// Current balance as a `Money` value. Always non-nil — `Double` from
    /// `UserDefaults.double(forKey:)` defaults to `0` (which is valid).
    /// A negative raw value flips `balanceCorrupted` (logged + broadcast via
    /// `balanceCorruptedNotification`) and is reported as `.zero` so UI can
    /// keep rendering while the user is prompted to acknowledge the loss
    /// (issue #119). Subsequent `charge`/`topUp` are gated until cleared via
    /// `acknowledgeCorruption()`.
    ///
    /// Denominated in `walletCurrency`, not in `Money.legacy`'s assumed rouble:
    /// once a wallet has been established as, say, USD by its first paid top-up
    /// (#563), reporting its balance as roubles would be a plain lie — and
    /// would make `charge(_ amount: Money)` refuse every amount derived from it.
    var balanceMoney: Money {
        let currency = walletCurrency
        return Money(balance, currency: currency) ?? .zero(currency)
    }

    /// The currency the stored `Double` balance is denominated in.
    ///
    /// Established by the wallet's first paid top-up and fixed from then on
    /// (#563). A wallet with no record — fresh install before any purchase, or
    /// any install predating #563 — reads as `Currency.legacyDefault`, because
    /// the store has only ever sold a rouble balance.
    ///
    /// ⚠️ Since #562 this is also read from **inside** `queue.sync` (every ledger
    /// row is stamped with it, and the derived balance sums only rows that match
    /// it), so it must stay free of `queue.sync` — a `defaults` read is fine,
    /// calling back into `balance` would deadlock.
    var walletCurrency: Currency { currencyStore.currency }

    /// Records this wallet's currency, once. See `WalletCurrencyFreeze` for why
    /// the result is a value the caller has to look at rather than a silent
    /// no-op.
    ///
    /// Callers are the *paid* credit paths only. In particular the DEBUG
    /// fallback behind `topUp(amount:)` (used when the StoreKit catalogue is
    /// empty on a simulator) must never reach here: a debug top-up would
    /// otherwise permanently denominate the wallet.
    func freezeCurrency(_ currency: Currency) -> WalletCurrencyFreeze {
        currencyStore.freeze(currency)
    }

    /// Whether a paid top-up denominated in `currency` can be accepted.
    ///
    /// Called by the top-up screens *before* `Product.purchase(_:)` so a
    /// foreign-storefront purchase is refused while it is still free to refuse
    /// — after Apple has taken the money the only options left are crediting a
    /// number that means something else (#558) or keeping money with nothing
    /// credited.
    ///
    /// Three cases:
    /// - **currency already established** — only that currency is accepted;
    /// - **no record, wallet untouched** — anything is accepted; this purchase
    ///   is what establishes the currency;
    /// - **no record, wallet has history** — it is a legacy rouble wallet
    ///   (`Currency.legacyDefault`) whose balance, ledger rows and configured
    ///   penalties are all in roubles, so only roubles are accepted. Adopting a
    ///   foreign currency here would also drop every existing row out of
    ///   `BalanceLedger.net(of:in:)` and restate the balance.
    func acceptsPurchase(in currency: Currency) -> Bool {
        if let established = currencyStore.storedCurrency {
            return currency == established
        }
        return currency == .legacyDefault || walletIsPristine
    }

    /// True only for a wallet that has never held or moved money: zero balance,
    /// no ledger rows, no latched corruption. Such a wallet has nothing to
    /// restate, so it may adopt any currency.
    ///
    /// `internal` because `TopUpRestoreService` gates on exactly this state
    /// (#364): a clean install is the one wallet whose paid history may be
    /// rebuilt from `StoreKit.Transaction.all`, and it is the one wallet that
    /// may adopt the currency those transactions were paid in.
    var walletIsPristine: Bool {
        queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted, current == 0 else { return false }
            guard let entries = try? ledgerStore.loadEntries() else { return false }
            return entries.isEmpty
        }
    }

    /// Outcome of crediting a real StoreKit purchase.
    enum PurchaseCredit: Equatable {
        /// Balance moved and a ledger row was written.
        case credited
        /// The purchase is denominated in a currency this wallet does not hold.
        /// Nothing was credited — the caller must surface this rather than
        /// crediting the bare number (that is #558).
        case refusedCurrency(wallet: Currency, purchase: Currency)
        /// Ledger locked / encoding failed / replayed row — same failure modes
        /// as `topUp(amount:)` returning `false`.
        case notRecorded
    }

    /// Credits a verified paid top-up, establishing the wallet currency if this
    /// is the first one.
    ///
    /// `currency` is `StoreKit.Transaction.currency`, which is optional: when
    /// StoreKit does not report one, the amount is credited into the wallet's
    /// existing currency and **nothing is frozen**. Guessing there is exactly
    /// how a wallet would quietly acquire a currency nobody chose.
    ///
    /// `purchasedAt` stamps the ledger row. It defaults to now for a live
    /// purchase and carries the original date when a past purchase is restored
    /// on a clean install (#364) — a top-up bought in March is March's revenue
    /// in Statistics, not today's. It does not affect the balance: the ledger
    /// sum is order-independent.
    func topUpFromPurchase(
        amount: Double,
        currency: Currency?,
        purchasedAt: Date = Date()
    ) -> PurchaseCredit {
        guard let currency else {
            return creditPaid(amount: amount, at: purchasedAt)
        }
        guard acceptsPurchase(in: currency) else {
            return .refusedCurrency(wallet: walletCurrency, purchase: currency)
        }
        // Freeze BEFORE crediting: the ledger row is stamped with
        // `walletCurrency`, so a row written first would carry the old currency
        // and then be excluded from the sum by `BalanceLedger.net(of:in:)`.
        switch freezeCurrency(currency) {
        case .frozen, .unchanged:
            break
        case .refused(let existing, let attempted):
            // Only reachable if the currency was established between the check
            // above and here. Refuse rather than credit into the wrong wallet.
            return .refusedCurrency(wallet: existing, purchase: attempted)
        }
        return creditPaid(amount: amount, at: purchasedAt)
    }

    private func creditPaid(amount: Double, at date: Date) -> PurchaseCredit {
        credit(type: .topup, amount: amount, createdAt: date) ? .credited : .notRecorded
    }

    /// Money-typed charge. Returns `false` when funds are insufficient,
    /// matching the legacy `charge(amount:alarmID:)` contract — or when the
    /// amount is in a currency this wallet does not hold, since there is no
    /// conversion (#559) and debiting the number alone would be plain wrong.
    @discardableResult
    func charge(_ amount: Money, alarmID: UUID?) -> Bool {
        guard amount.currency == walletCurrency else { return false }
        return charge(amount: amount.toDouble(), alarmID: alarmID)
    }

    /// Money-typed top-up. The `Money` invariant guarantees non-negative,
    /// finite — replacing the loose `Double` precondition. Returns whether
    /// the credit actually landed (see legacy `topUp(amount:)`); a foreign
    /// currency never lands.
    @discardableResult
    func topUp(_ amount: Money) -> Bool {
        guard amount.currency == walletCurrency else { return false }
        return topUp(amount: amount.toDouble())
    }

    func canAfford(_ amount: Money) -> Bool {
        amount.currency == walletCurrency && canAfford(amount.toDouble())
    }

    /// Hop to main since `charge`/`topUp` may be called from a background queue
    /// (notification action handler) and observers drive UIKit. NotificationCenter
    /// delivers synchronously on the posting thread, so we explicitly hop here
    /// rather than push that responsibility onto every observer.
    private func notifyBalanceChanged(_ newBalance: Double) {
        if Thread.isMainThread {
            postBalanceChanged(newBalance)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.postBalanceChanged(newBalance)
            }
        }
    }

    private func postBalanceChanged(_ newBalance: Double) {
        notificationCenter.post(
            name: Self.balanceChangedNotification,
            object: self,
            userInfo: [Self.balanceUserInfoKey: newBalance]
        )
    }

    /// Reads the cached balance from storage, side-effects the corruption flag
    /// if an invalid value is observed, and otherwise defers to the ledger
    /// (`ledgerDerivedBalance`). MUST be called inside `queue.sync`.
    /// Returns `0` to callers when corrupt so downstream math (e.g. `canAfford`)
    /// behaves as if the wallet is empty rather than negative — the corruption
    /// flag is the single source of truth for whether further mutation is
    /// allowed (issue #119).
    private func readRawBalance() -> Double {
        let raw = defaults.double(forKey: balanceKey)
        // Treat NaN, ±Infinity AND negative as corruption. UserDefaults stores
        // doubles verbatim, so a non-finite value can land via concurrent write
        // race or external write — and `NaN < 0` is `false`, so a negative-only
        // guard would let NaN/Inf sail through and propagate through
        // `current >= amount` (always false for NaN) silently disabling charge
        // without surfacing the corruption flag. Reject anything that isn't a
        // finite, non-negative double.
        guard raw.isFinite, raw >= 0 else {
            return latchCorruption(raw: raw)
        }
        return ledgerDerivedBalance(cached: raw)
    }

    /// The balance the ledger says the wallet holds: `openingBalance + Σ(rows)`.
    ///
    /// `user_balance` is only a cache of this sum, so a disagreement is
    /// repaired in favour of the ledger — that's what "ledger is the source of
    /// truth" buys (#483). Two escapes:
    ///
    ///   * **Unreadable ledger** — a partial sum would silently invent or erase
    ///     money, so the cached value stands until the user acknowledges.
    ///   * **No opening balance yet** — the first read of an existing install
    ///     adopts `cached − Σ(rows)`, which makes the derived value identical to
    ///     what the user saw before this change. That's the whole migration:
    ///     no pass over storage, no window in which money can be lost.
    ///
    /// MUST be called inside `queue.sync`.
    private func ledgerDerivedBalance(cached: Double) -> Double {
        guard ledgerStore.isReadable, let entries = try? ledgerStore.loadEntries() else {
            return cached
        }
        let net = BalanceLedger.net(of: entries, in: walletCurrency)
        guard let opening = ledgerStore.openingBalance else {
            ledgerStore.openingBalance = cached - net
            return cached
        }
        let derived = opening + net
        // A ledger that sums below zero is a desync, not a wallet the user can
        // spend from — route it through the same #119 gate as a negative
        // `user_balance` instead of handing back a negative number.
        guard derived.isFinite, derived >= 0 else {
            return latchCorruption(raw: derived)
        }
        if derived != cached {
            defaults.set(derived, forKey: balanceKey)
        }
        return derived
    }

    /// Re-pins the opening balance so the ledger derives exactly `target`.
    /// Used after the user wipes a corrupt balance: the rows stay for stats,
    /// but they must not re-inflate the wallet on the next read.
    /// MUST be called inside `queue.sync`.
    private func rebaseLedger(to target: Double) {
        let net = (try? ledgerStore.loadEntries())
            .map { BalanceLedger.net(of: $0, in: walletCurrency) } ?? 0
        ledgerStore.openingBalance = target - net
    }

    /// Latches the corruption flag, logs once, and broadcasts the notification.
    /// Always returns `0` so callers can treat the wallet as empty for math.
    /// MUST be called inside `queue.sync`.
    private func latchCorruption(raw: Double) -> Double {
        // Latch the flag the first time we observe corruption, log once, and
        // broadcast for UI. Subsequent reads stay clamped at 0 until the user
        // acknowledges via `acknowledgeCorruption()`.
        let firstObservation = !_balanceCorrupted
        _balanceCorrupted = true
        // Keep the offending value queryable for late subscribers — the
        // one-shot notification below is dropped when corruption latches at
        // init time before any UI observer is attached (#206).
        _corruptedRawValue = raw
        if firstObservation {
            os_log(
                "Corrupted balance observed in storage: %{public}f — gating mutations until acknowledged",
                log: Self.log, type: .error, raw
            )
            notifyBalanceCorrupted(rawValue: raw)
        }
        return 0
    }

    private func notifyBalanceCorrupted(rawValue: Double) {
        if Thread.isMainThread {
            postBalanceCorrupted(rawValue: rawValue)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.postBalanceCorrupted(rawValue: rawValue)
            }
        }
    }

    private func postBalanceCorrupted(rawValue: Double) {
        notificationCenter.post(
            name: Self.balanceCorruptedNotification,
            object: self,
            userInfo: [Self.balanceCorruptedRawValueKey: rawValue]
        )
    }
}
