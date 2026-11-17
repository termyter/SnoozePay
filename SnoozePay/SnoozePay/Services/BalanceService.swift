import CoreFoundation
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
    /// A first paid currency freeze invalidates already scheduled price labels.
    static let walletCurrencyChangedNotification = Notification.Name("snoozepay.wallet.currency.changed")

    /// Broadcast once per process when a negative `user_balance` is observed
    /// in storage (concurrent write race, downgrade, manual tampering — see
    /// issue #119). UI surfaces an alert and offers the user to wipe the
    /// corrupt value via `acknowledgeCorruption()` (future Settings entry,
    /// see #102). Mirrors the locked-ledger pattern from #72.
    /// Delivered asynchronously on main, outside the serial queue, whatever
    /// thread latched it (see `notifyBalanceCorrupted`, #851).
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
    /// Cached storefront snooze-price scales (#1109). Read by `priceContext`
    /// (`BalanceService+PriceContext.swift`); a lock-guarded UserDefaults read,
    /// never StoreKit.
    let priceScaleStore: SnoozePriceScaleStore
    /// Source of truth for the balance (#483): every mutation is an append
    /// here, and `user_balance` is a cache of `openingBalance + Σ(ledger)`.
    private let ledgerStore: BalanceLedgerStore
    private let transactionRepository: TransactionRepository
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
        notificationCenter: NotificationCenter = .default,
        priceScaleStore: SnoozePriceScaleStore? = nil
    ) {
        self.defaults = defaults
        self.transactionRepository = transactionRepository
        self.currencyStore = WalletCurrencyStore(defaults: defaults)
        // Same suite as the wallet unless injected, so a test never reads `.standard`.
        self.priceScaleStore = priceScaleStore ?? SnoozePriceScaleStore(defaults: defaults)
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
            notificationCenter: .default,
            priceScaleStore: .shared
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
    ///
    /// Debits the bare number in whatever currency the wallet holds. An amount
    /// priced in a known currency goes through
    /// `chargeWithReceipt(amount:expecting:alarmID:)` instead (#1143).
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        try? debit(amount: amount, expecting: nil, alarmID: alarmID).get()
    }

    /// Charge of an amount priced in `currency` (#1143): `nil` — no ledger row,
    /// balance unchanged — unless the wallet holds `currency` at the debit.
    ///
    /// Compared inside the serial queue, against the same `walletCurrency` read
    /// the row is stamped with. A caller-side check leaves a gap in which a
    /// first purchase freezes and credits another currency, and a number priced
    /// in roubles would then be debited as dollars.
    func chargeWithReceipt(amount: Double, expecting currency: Currency, alarmID: UUID?) -> Transaction? {
        try? debit(amount: amount, expecting: currency, alarmID: alarmID).get()
    }

    /// Why a debit did not land (#1136). Decided inside the serial queue, so a
    /// caller reports this reason instead of re-deriving one from its own read.
    enum DebitRefusal: Error, Equatable {
        /// Non-finite or non-positive amount (#441).
        case invalidAmount
        /// Priced in `price` while the wallet holds `wallet`; there is no conversion.
        case currencyMismatch(price: Currency, wallet: Currency)
        /// The stored balance is negative (#119).
        case balanceCorrupted
        case insufficientFunds
        /// The ledger refused the row: locked store, encoding, or a replay (#483).
        case notRecorded
    }

    /// The one debit every charge entry point goes through (#1136). `expected`
    /// is the currency the amount is priced in; `nil` only for the unpriced
    /// legacy `chargeWithReceipt(amount:alarmID:)`, which debits wallet units.
    func debit(amount: Double, expecting expected: Currency?, alarmID: UUID?) -> Result<Transaction, DebitRefusal> {
        // Reject non-finite / non-positive amounts up front, matching
        // `creditPromotion`'s contract (#441). Without this a negative amount
        // passes the `current >= amount` guard and records a `.charge` that
        // INCREASES the balance (and injects a phantom snooze day into
        // streak/stats); a NaN would persist into storage before the read-time
        // corruption guard catches it.
        guard amount.isFinite, amount > 0 else { return .failure(.invalidAmount) }
        let result: (outcome: Result<Transaction, DebitRefusal>, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            // Read once: the comparison and the stamp see the same currency.
            // Enough on its own: a freeze to another currency needs a pristine
            // wallet, and the credit that follows it runs through this queue.
            let held = walletCurrency
            if let expected, expected != held {
                // A pristine wallet on a foreign storefront is a new user
                // outside Russia, an expected state; anything else is a defect.
                let pristine = current == 0 && !_balanceCorrupted
                    && (try? ledgerStore.loadEntries())?.isEmpty == true
                AppLogger.emit(
                    .balance, pristine ? .default : .error,
                    "charge refused: priced in \(expected.code), wallet in \(held.code)"
                )
                return (.failure(.currencyMismatch(price: expected, wallet: held)), current)
            }
            guard !_balanceCorrupted else { return (.failure(.balanceCorrupted), current) }
            guard MoneyDecimal.covers(current, amount) else { return (.failure(.insufficientFunds), current) }

            // The ledger append IS the mutation (#483). If the store is locked
            // (corrupt blob waiting on user ack), encoding fails, or the row is
            // a replay of one already present, the balance must not move —
            // otherwise money disappears from the wallet with no record in
            // stats (see #72 hunter review of PR #101).
            let transaction = Transaction(type: .charge, amount: amount, currency: held, alarmID: alarmID?.uuidString)
            guard ledgerStore.append(transaction) == .recorded else {
                return (.failure(.notRecorded), current)
            }

            // Recompute from the ledger rather than `current - amount`: the sum
            // over the rows is the balance, and this call also refreshes the
            // `user_balance` cache.
            return (.success(transaction), readRawBalance())
        }

        if case .success = result.outcome { notifyBalanceChanged(result.newBalance) }
        return result.outcome
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
        credit(type: .topup, amount: amount) == .recorded
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
        credit(type: .refund, amount: amount, refundsTransactionID: refundsTransactionID) == .recorded
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
        credit(type: .promotion, amount: amount) == .recorded
    }

    /// Shared implementation behind every credit (`topUp` / `refund` /
    /// `creditPromotion`). Only the ledger `type` differs — the corruption
    /// gating, amount validation and ledger-first ordering are identical and
    /// must stay that way, so they live in one place.
    ///
    /// `id` is random for every credit except a paid purchase, whose row id is
    /// derived from the StoreKit transaction (#1011) — that is what makes a
    /// replay come back `.duplicate` instead of crediting twice.
    private func credit(
        type: TransactionType,
        amount: Double,
        createdAt: Date = Date(),
        id: UUID = UUID(),
        refundsTransactionID: UUID? = nil
    ) -> LedgerWriteResult {
        // Reject non-finite / non-positive amounts (#441): a negative credit
        // would record a positive-typed row while DECREASING the balance
        // (ledger/balance divergence that can drive `user_balance` negative and
        // latch #119 corruption); a NaN would persist into storage before the
        // read-time guard fires.
        guard amount.isFinite, amount > 0 else { return .rejected }

        let result: (write: LedgerWriteResult, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted else { return (.rejected, current) }

            let transaction = Transaction(
                id: id,
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
            let write = ledgerStore.append(transaction)
            return (write, write == .recorded ? readRawBalance() : current)
        }

        if result.write == .recorded {
            notifyBalanceChanged(result.newBalance)
        }
        return result.write
    }

    // MARK: - Validation

    func canAfford(_ amount: Double) -> Bool {
        queue.sync { MoneyDecimal.covers(readRawBalance(), amount) }
    }

    // MARK: - Recovery (corruption)

    /// Erases only an unreadable ledger, preserving its last valid cached
    /// balance (#910). Never derive from the corrupt rows or reset purchase IDs.
    /// Opening is saved BEFORE unlocking/removing the ledger: a restart between
    /// those writes still sees the locked ledger and unchanged cache. The wallet
    /// queue excludes concurrent charges, credits and reads during recovery.
    /// `false` leaves recovery data untouched when the cache cannot be trusted.
    func recoverCorruptTransactionHistory() -> Bool {
        queue.sync {
            guard transactionRepository.lastLoadFailed else { return true }
            guard !_balanceCorrupted,
                  let cached = defaults.object(forKey: balanceKey) as? NSNumber,
                  CFGetTypeID(cached) != CFBooleanGetTypeID(),
                  cached.doubleValue.isFinite, cached.doubleValue >= 0 else { return false }
            ledgerStore.openingBalance = cached.doubleValue
            transactionRepository.clearCorruptState()
            return true
        }
    }

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

    /// The established wallet currency, or `nil` before the first paid top-up.
    /// Free of `queue.sync`, like `walletCurrency`.
    var storedWalletCurrency: Currency? { currencyStore.storedCurrency }

    /// The currency of `alarmQuoteContext` (#1138), or `nil` while AlarmKit
    /// labels stay unpriced. An `.unavailable` context still names its currency
    /// here even though the label it produces carries no number.
    var alarmQuoteCurrency: Currency? { alarmQuoteContext?.currency }

    /// Records this wallet's currency, once. See `WalletCurrencyFreeze` for why
    /// the result is a value the caller has to look at rather than a silent
    /// no-op.
    ///
    /// Callers are the *paid* credit paths only. In particular the DEBUG
    /// fallback behind `topUp(amount:)` (used when the StoreKit catalogue is
    /// empty on a simulator) must never reach here: a debug top-up would
    /// otherwise permanently denominate the wallet.
    func freezeCurrency(_ currency: Currency) -> WalletCurrencyFreeze {
        let result = currencyStore.freeze(currency)
        if case .frozen = result {
            // Store lock has been released; observers read the new currency.
            notificationCenter.post(name: Self.walletCurrencyChangedNotification, object: self)
        }
        return result
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

    /// Why a paid top-up in `currency` would be refused, or `nil` when it is
    /// accepted. Shared by `topUpFromPurchase` and, under `prePurchaseRefusal(in:)`,
    /// the pre-purchase gate of the top-up sheets (#1133, #1163).
    ///
    /// An unreadable ledger takes no credit in any currency, and it is also
    /// what makes the wallet non-pristine: calling that a currency mismatch
    /// would misname the cause. An accepted currency is untouched — it reaches
    /// the ledger write and is refused there, as before.
    func purchaseRefusal(in currency: Currency) -> PurchaseRefusal? {
        guard !acceptsPurchase(in: currency) else { return nil }
        // `init` reads the balance, so an undecodable ledger has already
        // latched `isReadable` by the time anyone asks.
        guard queue.sync(execute: { ledgerStore.isReadable }) else { return .ledgerUnreadable }
        return .foreignCurrency(wallet: walletCurrency, purchase: currency)
    }

    /// The refusal the top-up sheets show **before** `Product.purchase(_:)`.
    ///
    /// Stricter than `purchaseRefusal(in:)`: an unreadable ledger refuses even
    /// an accepted currency, because a purchase dispatched now is charged by
    /// Apple and then not credited (#1163). The read is checked here rather
    /// than trusting the latch, which only moves when something reads — a
    /// ledger damaged after launch would otherwise pass an established wallet.
    func prePurchaseRefusal(in currency: Currency) -> PurchaseRefusal? {
        let readable = queue.sync { (try? ledgerStore.loadEntries()) != nil }
        guard readable else { return .ledgerUnreadable }
        return purchaseRefusal(in: currency)
    }

    /// See `purchaseRefusal(in:)`.
    enum PurchaseRefusal: Equatable {
        /// The wallet holds `wallet` and cannot take `purchase` (#563).
        case foreignCurrency(wallet: Currency, purchase: Currency)
        /// The ledger cannot be read, so nothing can be credited.
        case ledgerUnreadable
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
        /// The row keyed on this purchase is already in the ledger: an earlier
        /// run credited it and died before finishing the transaction (#1011).
        /// Nothing moved now; the caller may mark and finish.
        case alreadyCredited
        /// Ledger locked / encoding failed / corrupted balance — same failure
        /// modes as `topUp(amount:)` returning `false`.
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
    ///
    /// `ledgerID` is `RestorableTopUp.ledgerRowID` — the persisted link between
    /// the StoreKit transaction and its credit (#1011). The default (random)
    /// exists only for callers with no StoreKit transaction behind them.
    func topUpFromPurchase(
        amount: Double,
        currency: Currency?,
        purchasedAt: Date = Date(),
        ledgerID: UUID = UUID()
    ) -> PurchaseCredit {
        guard let currency else {
            return creditPaid(amount: amount, at: purchasedAt, id: ledgerID)
        }
        switch purchaseRefusal(in: currency) {
        case .ledgerUnreadable?:
            AppLogger.emit(.balance, .error, "purchase in \(currency.code) not credited: ledger unreadable")
            return .notRecorded
        case let .foreignCurrency(wallet, purchase)?:
            return .refusedCurrency(wallet: wallet, purchase: purchase)
        case nil:
            break
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
        return creditPaid(amount: amount, at: purchasedAt, id: ledgerID)
    }

    private func creditPaid(amount: Double, at date: Date, id: UUID) -> PurchaseCredit {
        switch credit(type: .topup, amount: amount, createdAt: date, id: id) {
        case .recorded: return .credited
        case .duplicate: return .alreadyCredited
        case .rejected: return .notRecorded
        }
    }

    /// Money-typed charge. Returns `false` when funds are insufficient,
    /// matching the legacy `charge(amount:alarmID:)` contract — or when the
    /// amount is in a currency this wallet does not hold, since there is no
    /// conversion (#559) and debiting the number alone would be plain wrong.
    /// Compared inside the wallet queue by `debit`, not here (#1136).
    @discardableResult
    func charge(_ amount: Money, alarmID: UUID?) -> Bool {
        chargeWithReceipt(amount: amount.toDouble(), expecting: amount.currency, alarmID: alarmID) != nil
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
        let currency = walletCurrency
        let net = BalanceLedger.net(of: entries, in: currency)
        guard let opening = ledgerStore.openingBalance else {
            ledgerStore.openingBalance = MoneyDecimal.subtracting(cached, net)
            return cached
        }
        // Decimal sum (#1119): binary rounding noise must not read as a
        // ledger below zero.
        let sum = MoneyDecimal.adding(opening, net)
        // An opening adopted by a pre-#1119 build was `cached − Σ` in Double
        // and may carry noise (−20.950000000000003), so the exact sum can be
        // −3e-15 (#1122). Round to the minor unit the wallet is shown in
        // before judging the sign. Roubles are left as they are so legacy
        // values stay bit-identical: fractional rouble openings exist, and
        // rounding them would restate wallets that read fine before #1122.
        let derived = currency == .rub ? sum : MoneyDecimal.rounded(sum, toDigits: currency.minorUnitDigits)
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
        ledgerStore.openingBalance = MoneyDecimal.subtracting(target, net)
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

    /// Post from the main queue, after `queue` is released (#851). The same
    /// shape as `AudioService.postOnMain`.
    ///
    /// Reached only from `latchCorruption`, i.e. inside `queue.sync`. The
    /// main-thread branch used to post right there, so an observer that read
    /// the service back (`balance`, `balanceCorrupted`) re-entered `queue.sync`
    /// on the queue its own thread held: a libdispatch trap. It also made the
    /// main-thread post synchronous and the background one asynchronous, so
    /// the two had no order. Always async on main keeps them FIFO.
    ///
    /// `self` is captured strongly so the post is not lost when the last owner
    /// lets go before main runs it; the extra lifetime is one main-queue turn.
    private func notifyBalanceCorrupted(rawValue: Double) {
        DispatchQueue.main.async {
            self.postBalanceCorrupted(rawValue: rawValue)
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
