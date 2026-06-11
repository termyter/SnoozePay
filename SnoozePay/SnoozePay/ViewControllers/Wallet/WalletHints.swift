import Foundation

/// Balance-hint copy for the Wallet tab's `SPBalanceCard`.
///
/// Renamed from `WalletPresets` in #233 — the 3×2 preset grid moved into
/// `DepositBottomSheetViewController` (see `DepositPresets`), leaving only
/// the affordability hint logic on this screen.
enum WalletHints {

    /// Localised "Хватит на ~N откладываний при текущей цене" hint —
    /// matches the JSX hardcoded copy. The N defaults to 17 (840 ÷ 50 ≈ 17)
    /// when balance / price are not yet bound; live callers should compute
    /// it via `affordHint(forBalance:averagePrice:)`.
    static func defaultBalanceHint() -> String {
        "Хватит на ~17 откладываний при текущей цене"
    }

    /// Derives the wallet-card hint from the live balance and the user's
    /// average snooze price. Falls back to the static copy when price is
    /// non-positive or balance is zero — avoids divide-by-zero noise and
    /// also keeps the empty state from showing "Хватит на ~0".
    static func affordHint(forBalance balance: Double, averagePrice: Double) -> String {
        guard balance > 0, averagePrice > 0 else {
            return "Пока баланс пуст — пополните, чтобы откладывать"
        }
        let count = max(1, Int(balance / averagePrice))
        return "Хватит на ~\(count) откладываний при текущей цене"
    }
}
