import Foundation
import os

/// Manages the user's local balance stored in UserDefaults.
/// All operations are synchronous and offline-first.
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
    private let transactionRepository: TransactionRepository
    private let queue = DispatchQueue(label: "com.snoozepay.balance.serial")
    private let notificationCenter: NotificationCenter
    private static let log = OSLog(
        subsystem: "Ivan-Emelyanov.SnoozePay",
        category: "BalanceService"
    )

    /// Set inside `queue.sync` whenever a negative raw balance is observed.
    /// While true, `charge`/`topUp` refuse to mutate storage so the corrupt
    /// value is not overwritten before the user has a chance to acknowledge
    /// the loss (mirrors `TransactionRepository._lastLoadFailed`, issue #72).
    private var _balanceCorrupted: Bool = false
    var balanceCorrupted: Bool { queue.sync { _balanceCorrupted } }

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
        self.transactionRepository = transactionRepository
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
        let result: (charged: Bool, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted else { return (false, current) }
            guard current >= amount else { return (false, current) }

            let transaction = Transaction(
                type: .charge,
                amount: amount,
                alarmID: alarmID?.uuidString
            )
            // Record the ledger entry FIRST. If the transaction repository is
            // locked (corrupt blob waiting on user ack) or encoding fails, we
            // refuse to mutate the balance — otherwise money would silently
            // disappear from the wallet with no record in stats (see #72 hunter
            // review of PR #101).
            guard transactionRepository.record(transaction) else {
                return (false, current)
            }

            let newBalance = current - amount
            defaults.set(newBalance, forKey: balanceKey)
            return (true, newBalance)
        }

        if result.charged {
            notifyBalanceChanged(result.newBalance)
        }
        return result.charged
    }

    // MARK: - Top up (IAP)

    /// Returns `true` if the credit landed (balance moved AND ledger updated).
    /// Returns `false` when the transaction repository is locked, encoding
    /// failed, or the stored balance is corrupted (negative — see #119) —
    /// caller should surface this to the user instead of pretending
    /// the IAP credited (silent ledger desync was the regression behind the #72
    /// PR #101 hunter feedback).
    @discardableResult
    func topUp(amount: Double) -> Bool {
        let result: (recorded: Bool, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted else { return (false, current) }

            let transaction = Transaction(
                type: .topup,
                amount: amount
            )
            guard transactionRepository.record(transaction) else {
                return (false, current)
            }
            let updated = current + amount
            defaults.set(updated, forKey: balanceKey)
            return (true, updated)
        }

        if result.recorded {
            notifyBalanceChanged(result.newBalance)
        }
        return result.recorded
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
        guard amount.isFinite, amount > 0 else { return false }

        let result: (recorded: Bool, newBalance: Double) = queue.sync {
            let current = readRawBalance()
            guard !_balanceCorrupted else { return (false, current) }

            let transaction = Transaction(
                type: .promotion,
                amount: amount
            )
            guard transactionRepository.record(transaction) else {
                return (false, current)
            }
            let updated = current + amount
            defaults.set(updated, forKey: balanceKey)
            return (true, updated)
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
            _balanceCorrupted = false
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
    var balanceMoney: Money {
        Money(balance) ?? .zero
    }

    /// Money-typed charge. Returns `false` when funds are insufficient,
    /// matching the legacy `charge(amount:alarmID:)` contract.
    @discardableResult
    func charge(_ amount: Money, alarmID: UUID?) -> Bool {
        charge(amount: amount.toDouble(), alarmID: alarmID)
    }

    /// Money-typed top-up. The `Money` invariant guarantees non-negative,
    /// finite — replacing the loose `Double` precondition. Returns whether
    /// the credit actually landed (see legacy `topUp(amount:)`).
    @discardableResult
    func topUp(_ amount: Money) -> Bool {
        topUp(amount: amount.toDouble())
    }

    func canAfford(_ amount: Money) -> Bool {
        canAfford(amount.toDouble())
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

    /// Reads the raw balance from storage and side-effects the corruption
    /// flag if a negative value is observed. MUST be called inside `queue.sync`.
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
        return raw
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
