import Foundation

/// Balance-hint copy for the Wallet tab's `SPBalanceCard`.
///
/// Renamed from `WalletPresets` in #233 — the 3×2 preset grid moved into
/// `DepositBottomSheetViewController` (see `DepositPresets`), leaving only
/// the affordability hint logic on this screen.
///
/// The arithmetic itself lives in `SnoozeAffordability` (#546): this screen and
/// the alarms list answer the same question and must not answer it twice. What
/// stays here is the wallet-only empty-balance copy, which nudges toward the
/// deposit button this screen owns.
enum WalletHints {

    /// Shown while the balance is empty. Wallet-specific on purpose — the
    /// alarms list says "Откладывать не получится", which is the right line
    /// on a screen with no way to top up; here the user is one tap away.
    static let emptyBalanceHint = "Пока баланс пуст — пополните, чтобы откладывать"

    /// Derives the wallet-card hint from the live balance and the user's
    /// alarms. Identical string to `AlarmsListViewModel.affordabilityHint` for
    /// the same inputs — that equality is the point of #546, where the wallet
    /// divided by a hardcoded 50 ₽ (and still claimed "при текущей цене") while
    /// the list divided by the priciest alarm, so 298 ₽ read as "~5" here and
    /// "~1" one tap away.
    static func affordHint(
        forBalance balance: Double,
        alarms: [Alarm],
        defaults: AlarmDefaults = .shared
    ) -> String {
        guard balance > 0 else { return emptyBalanceHint }
        return SnoozeAffordability.hint(balance: balance, alarms: alarms, defaults: defaults)
    }
}
