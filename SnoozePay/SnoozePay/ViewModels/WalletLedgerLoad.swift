import Foundation

/// Read seam the Wallet surfaces share so the reload decision — "render
/// rows / empty-state vs. a load-error banner" — can be unit-tested with a
/// mock that fails its decode without standing up `UserDefaults` corruption
/// (issue #419). `TransactionRepository` is the production conformer.
///
/// Mirrors the `fetchAllChecked()` contract: a decode failure throws instead
/// of being swallowed into a misleading `[]` (the lossy `fetchAll()` was what
/// let a corrupt ledger render as the friendly "нет операций" empty-state).
protocol WalletLedgerReading {
    func fetchAllChecked() throws -> [Transaction]
}

extension TransactionRepository: WalletLedgerReading {}

/// Outcome of a checked ledger read for a Wallet surface. The VCs branch on
/// this to pick rendering: `.loaded` drives rows / empty-state, `.failed`
/// drives the distinct "Не удалось загрузить историю" banner — the same
/// honest-corruption treatment `StatisticsViewModel` gives its load (#72/#419).
enum WalletLedgerLoad {
    case loaded([Transaction])
    case failed

    /// Performs the checked read and collapses any error into `.failed`.
    /// Centralised so the three Wallet read sites (preview, weekly stats,
    /// full history) can never drift on how a decode failure is classified.
    static func load(from repository: WalletLedgerReading) -> WalletLedgerLoad {
        do {
            return .loaded(try repository.fetchAllChecked())
        } catch {
            return .failed
        }
    }

    /// Transactions to render, or `[]` when the load failed (the caller shows
    /// the error banner instead of trusting this emptiness as "no operations").
    var transactions: [Transaction] {
        switch self {
        case .loaded(let txs): return txs
        case .failed: return []
        }
    }

    /// `true` when the ledger could not be decoded — the surface must show a
    /// load-error banner rather than a friendly empty-state.
    var didFail: Bool {
        switch self {
        case .loaded: return false
        case .failed: return true
        }
    }
}
