import Foundation
import os

/// Outcome of an idempotent ledger append.
///
/// `duplicate` is a *success* from the caller's point of view — the row is
/// already in the ledger, so the money it represents has already been counted.
/// It is a separate case from `recorded` only so callers can tell "I moved the
/// balance" from "someone else already did" (StoreKit restore, future CloudKit
/// resync — issue #364).
enum LedgerWriteResult: Equatable {
    case recorded
    case duplicate
    case rejected
}

/// Which backend holds the ledger. Phase 1 of #364 adds the CloudKit provider
/// behind this same seam; until it ships, `.cloudKit` resolves to local.
enum BalanceLedgerProvider: String {
    case local
    case cloudKit
}

/// Persistence seam for the balance ledger.
///
/// The wallet balance is `openingBalance + Σ(ledger)` — the ledger is the
/// source of truth and `user_balance` is a cache of that sum (#483). Splitting
/// persistence behind a protocol keeps the derivation identical whether the
/// rows come from UserDefaults today or from CloudKit later, without
/// `BalanceService` learning about either.
protocol BalanceLedgerStore: AnyObject {

    /// `false` while the underlying ledger is unreadable (corrupt blob awaiting
    /// user acknowledgement). A balance derived from a partial ledger would be
    /// wrong in the user's favour or against it, so callers must not derive.
    var isReadable: Bool { get }

    /// Scalar the ledger sum is applied on top of: money that existed before
    /// the ledger became authoritative. `nil` until adopted — adoption is what
    /// makes the switch lossless for an existing install (no migration pass).
    var openingBalance: Double? { get set }

    /// Every persisted row. Throws when the ledger cannot be read.
    func loadEntries() throws -> [Transaction]

    /// Idempotent write keyed on `Transaction.id`.
    func append(_ transaction: Transaction) -> LedgerWriteResult
}

/// Pure ledger arithmetic, kept out of both the store and `BalanceService` so
/// the recomputation has exactly one definition.
enum BalanceLedger {

    /// Net movement recorded by `entries` **in `currency`**:
    /// `Σ(topup + promotion + refund − charge)` over the rows denominated in it.
    ///
    /// Rows are deduplicated by `Transaction.id` — a resync or a Restore that
    /// replays the same purchase must not credit it twice. Rows this build
    /// can't classify (`.unknown`) and rows with a non-finite / non-positive
    /// amount are skipped: their direction is genuinely unknown, and guessing
    /// one would move real money (#358, #441).
    ///
    /// **A row in another currency is skipped for the same reason** (#562).
    /// `Σ` over mixed currencies is not a quantity — 100 ₽ + 2 $ has no value
    /// without a rate, and this app has no rate source (#559). So the answer to
    /// "what happens to the balance cache when the ledger holds mixed
    /// currencies" is: the cache stays the sum of the wallet's own currency, and
    /// a foreign row neither inflates nor deflates it. It is visible in history
    /// and invisible to the balance.
    ///
    /// Today this changes nothing: nothing writes a foreign row, legacy rows
    /// decode as `Currency.legacyDefault`, and `BalanceService.walletCurrency`
    /// is that same value — so every existing row still counts. The filter is
    /// what keeps that true once #563 gives the wallet a real currency.
    ///
    /// Order-independent by construction — a shuffled or newest-first ledger
    /// yields the same number as a chronological one.
    static func net(of entries: [Transaction], in currency: Currency) -> Double {
        var seenIdentifiers = Set<UUID>()
        var total: Double = 0
        for entry in entries {
            guard seenIdentifiers.insert(entry.id).inserted else { continue }
            guard entry.currency == currency else { continue }
            guard entry.amount.isFinite, entry.amount > 0 else { continue }
            switch entry.type {
            case .topup, .promotion, .refund:
                total += entry.amount
            case .charge:
                total -= entry.amount
            case .unknown:
                continue
            }
        }
        return total
    }
}

/// UserDefaults-backed ledger store: the rows live in `TransactionRepository`
/// (which already owns the serial queue, the corrupt-blob backup and the
/// decode-failure lock), the opening balance in its own key.
final class LocalBalanceLedgerStore: BalanceLedgerStore {

    /// Money that predates ledger-derived balance. Adopted once, never
    /// migrated: see `BalanceService.readRawBalance()`.
    static let openingBalanceKey = "balance_ledger_opening"

    private let repository: TransactionRepository
    private let defaults: UserDefaults

    init(repository: TransactionRepository, defaults: UserDefaults) {
        self.repository = repository
        self.defaults = defaults
    }

    var isReadable: Bool { !repository.lastLoadFailed }

    var openingBalance: Double? {
        get {
            // `object(forKey:)` rather than `double(forKey:)`: an absent key and
            // a stored `0` must stay distinguishable, otherwise a brand-new
            // wallet re-adopts on every read.
            guard let stored = defaults.object(forKey: Self.openingBalanceKey) as? Double,
                  stored.isFinite else { return nil }
            return stored
        }
        set {
            guard let newValue, newValue.isFinite else {
                defaults.removeObject(forKey: Self.openingBalanceKey)
                return
            }
            defaults.set(newValue, forKey: Self.openingBalanceKey)
        }
    }

    func loadEntries() throws -> [Transaction] {
        try repository.fetchAllChecked()
    }

    /// Reads before writing so a replayed `Transaction.id` is dropped instead
    /// of appended. The read/write pair is not atomic on its own — every
    /// production caller goes through `BalanceService`'s serial queue, which is
    /// what actually serialises wallet mutation.
    func append(_ transaction: Transaction) -> LedgerWriteResult {
        let existing: [Transaction]
        do {
            existing = try repository.fetchAllChecked()
        } catch {
            return .rejected
        }
        guard !existing.contains(where: { $0.id == transaction.id }) else {
            return .duplicate
        }
        return repository.record(transaction) ? .recorded : .rejected
    }
}

/// Resolves the configured provider into a store. The flag exists so the
/// CloudKit provider can be switched on separately once phase 1 of #364 lands
/// (it needs an iCloud entitlement and a container — both PM-gated), without
/// another change to `BalanceService`.
enum BalanceLedgerStoreFactory {

    /// Set to a `BalanceLedgerProvider` raw value to pick the backend.
    /// Absent / unrecognised means `.local`.
    static let providerKey = "balance_ledger_provider"

    private static let log = OSLog(
        subsystem: "Ivan-Emelyanov.SnoozePay",
        category: "BalanceLedgerStore"
    )

    static func provider(defaults: UserDefaults) -> BalanceLedgerProvider {
        guard let raw = defaults.string(forKey: providerKey),
              let provider = BalanceLedgerProvider(rawValue: raw) else { return .local }
        return provider
    }

    static func makeStore(
        repository: TransactionRepository,
        defaults: UserDefaults
    ) -> BalanceLedgerStore {
        let local = LocalBalanceLedgerStore(repository: repository, defaults: defaults)
        guard provider(defaults: defaults) == .cloudKit else { return local }
        // Deliberately not a fatalError: a stale flag on a device must degrade
        // to the working local wallet, not brick it.
        os_log(
            "CloudKit ledger provider requested but not built yet (#364 phase 1) — using local store",
            log: log, type: .info
        )
        return local
    }
}
