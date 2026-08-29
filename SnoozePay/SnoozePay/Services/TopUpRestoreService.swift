import Foundation
import StoreKit
import os

/// One paid transaction as the restore cares about it.
///
/// A plain value rather than `StoreKit.Transaction` because that type has no
/// initializer outside a live App Store session — the restore *rules* (which
/// SKU counts, which currency wins, what a replay does) are the part that moves
/// money, so they have to be testable without one.
struct RestorableTopUp: Equatable {

    /// `StoreKit.Transaction.id` — the identity the whole idempotency guarantee
    /// hangs on. Shared with `StoreKitService`'s dedup table, so a transaction
    /// credited by the restore is not credited a second time by the
    /// `Transaction.updates` listener (and vice versa).
    let transactionID: UInt64

    let productID: String

    /// `StoreKit.Transaction.currency`, which is optional: StoreKit does not
    /// always report one. `nil` is carried through rather than guessed — see
    /// `BalanceService.topUpFromPurchase(amount:currency:purchasedAt:)`.
    let currency: Currency?

    /// The original purchase date. Restored rows are stamped with it instead of
    /// "now" so a top-up from March does not show up as March revenue being
    /// earned today in Statistics.
    let purchaseDate: Date
}

/// What one restore pass did. Returned (rather than only logged) so the
/// money-correctness tests can assert on it.
struct TopUpRestoreReport: Equatable {

    /// Sum actually credited, in `currency`.
    var credited: Double = 0
    var creditedCount: Int = 0

    /// Transactions already present in the dedup table — a second launch, or a
    /// transaction the `Transaction.updates` listener got to first. The whole
    /// point of the guarantee: these credit nothing.
    var alreadyCredited: Int = 0

    /// Paid in a currency this wallet cannot hold (see the type documentation).
    var foreignCurrency: Int = 0

    /// A product ID that is not one of ours — a SKU from a future build, or one
    /// this build has been rolled back past. Ignored, never credited.
    var unknownProduct: Int = 0

    /// Verified and ours, but the ledger refused the write (locked / corrupt).
    /// The dedup mark is rolled back for these, so a later pass can retry.
    var notRecorded: Int = 0
}

/// Rebuilds the paid part of a wallet from Apple's transaction history when the
/// app is installed on a device that has none (#364).
///
/// ## The compromise, stated out loud
///
/// The ledger lives in UserDefaults, so deleting the app deletes it. Apple, on
/// the other hand, keeps every transaction for the Apple ID forever — but Apple
/// only knows what was *bought*. It has never heard of a snooze charge, and it
/// has never heard of a referral bonus, because both are local events.
///
/// So a restored wallet is **deliberately too generous**: it comes back as
/// `Σ(paid top-ups)` with the charges that spent them missing. A user who
/// bought 999 ₽, spent 900 ₽ of it and reinstalled gets 999 ₽ back rather than
/// 99 ₽.
///
/// That asymmetry is chosen, not overlooked. The opposite error — a user who
/// paid Apple and finds an empty wallet — is a refund request and a one-star
/// review; this one costs us balance the user already paid for once. CloudKit
/// would carry the charges too and was the original plan for this issue; it was
/// dropped (entitlement, container, an account-change surface, weeks) in favour
/// of the version that ships. See the "Отвергнуто: CloudKit" section on #364.
///
/// ## Why it cannot run twice
///
/// Two independent guards, and both are load-bearing:
///
///  * **Per transaction** — every credit goes through
///    `StoreKitService.markProcessed(transactionID:)`, the same dedup table the
///    purchase and `Transaction.updates` paths use. A replay is a no-op there,
///    whichever path saw it first.
///  * **Per wallet** — the pass only runs on a *pristine* wallet (zero balance,
///    empty ledger, no latched corruption). A wallet with history already holds
///    the money these transactions bought.
@MainActor
final class TopUpRestoreService {

    static let shared = TopUpRestoreService()

    private let balance: BalanceService
    /// Owner of the dedup table (`storekit.processed_tx_ids`). The real service
    /// rather than a protocol seam: tests construct one over their own
    /// `UserDefaults` suite via its test initializer, and sharing the actual
    /// implementation is the point — a parallel dedup would not dedup.
    private let storeKit: StoreKitService

    init(balance: BalanceService = .shared, storeKit: StoreKitService = .shared) {
        self.balance = balance
        self.storeKit = storeKit
    }

    // MARK: - Entry point

    /// Reads Apple's transaction history and credits what this wallet is
    /// missing. Returns `nil` when the pass did not run because the wallet
    /// already has history.
    @discardableResult
    func restoreIfNeeded() async -> TopUpRestoreReport? {
        // Cheap guard first: on every launch after the first this is the branch
        // that runs, and it must not cost a StoreKit round trip.
        guard balance.walletIsPristine else { return nil }
        let candidates = await Self.paidTopUps()
        return restore(candidates)
    }

    /// The rules, over an explicit list. `restoreIfNeeded()` supplies the list
    /// from `StoreKit.Transaction.all`; tests supply their own.
    @discardableResult
    func restore(_ candidates: [RestorableTopUp]) -> TopUpRestoreReport? {
        guard balance.walletIsPristine else { return nil }

        var report = TopUpRestoreReport()
        // Newest first, and that ordering decides the wallet's currency (#563):
        // the first credit freezes it, so the *most recent* storefront wins and
        // older purchases from a storefront the user has left are skipped. The
        // other order would hand a user who moved from RUB to USD a rouble
        // wallet that refuses every purchase they can actually make.
        for candidate in candidates.sorted(by: { $0.purchaseDate > $1.purchaseDate }) {
            guard let amount = StoreKitService.productAmounts[candidate.productID] else {
                report.unknownProduct += 1
                continue
            }
            switch storeKit.markProcessed(transactionID: candidate.transactionID) {
            case .alreadyProcessed:
                report.alreadyCredited += 1
                continue
            case .degraded:
                // The dedup table's plist type has drifted, so "already
                // credited?" has no answer. Stop the whole pass rather than
                // credit blind — the wallet stays pristine and the next launch
                // (after recovery) tries again.
                AppLogger.storeKit.error("restore aborted — dedup table degraded")
                return report
            case .recorded:
                break
            }
            credit(candidate, amount: amount, into: &report)
        }

        AppLogger.balance.notice(
            """
            restore: credited \(report.credited, privacy: .public) over \
            \(report.creditedCount, privacy: .public) tx; skipped \
            \(report.alreadyCredited, privacy: .public) already, \
            \(report.foreignCurrency, privacy: .public) foreign-currency, \
            \(report.unknownProduct, privacy: .public) unknown-product, \
            \(report.notRecorded, privacy: .public) not-recorded
            """
        )
        return report
    }

    private func credit(
        _ candidate: RestorableTopUp,
        amount: Double,
        into report: inout TopUpRestoreReport
    ) {
        switch balance.topUpFromPurchase(
            amount: amount,
            currency: candidate.currency,
            purchasedAt: candidate.purchaseDate
        ) {
        case .credited:
            report.credited += amount
            report.creditedCount += 1

        case .refusedCurrency(let wallet, let purchase):
            // A purchase from a storefront the user has since left. Crediting
            // the bare number would book `purchase` money as `wallet` money
            // (#558) and there is no conversion in this app (#559), so it is
            // dropped. Unmarked so it stays eligible if the wallet is ever
            // wiped back to pristine.
            storeKit.unmarkProcessed(transactionID: candidate.transactionID)
            report.foreignCurrency += 1
            AppLogger.balance.notice(
                """
                restore skipped tx paid in \(purchase.code, privacy: .public) — \
                wallet holds \(wallet.code, privacy: .public)
                """
            )

        case .notRecorded:
            storeKit.unmarkProcessed(transactionID: candidate.transactionID)
            report.notRecorded += 1
            AppLogger.balance.error("restore could not record a top-up — ledger refused the write")
        }
    }

    // MARK: - Apple's history

    /// Every verified, non-revoked purchase of one of our top-up SKUs that
    /// Apple still associates with this Apple ID.
    ///
    /// `Transaction.all` (not `currentEntitlements`): consumables are consumed
    /// on purchase and never appear as entitlements, so `all` is the only place
    /// a spent top-up still exists.
    static func paidTopUps() async -> [RestorableTopUp] {
        var found: [RestorableTopUp] = []
        for await result in StoreKit.Transaction.all {
            // Unverified: no signature, no credit. Revoked: refunded or removed
            // from Family Sharing — Apple gave the money back, so we must not.
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  StoreKitService.productAmounts[transaction.productID] != nil else { continue }
            found.append(
                RestorableTopUp(
                    transactionID: transaction.id,
                    productID: transaction.productID,
                    currency: transaction.currency.flatMap { Currency($0) },
                    purchaseDate: transaction.purchaseDate
                )
            )
        }
        return found
    }
}
