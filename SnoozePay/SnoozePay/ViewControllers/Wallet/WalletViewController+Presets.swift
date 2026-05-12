import Foundation

/// Preset top-up amounts shown on the Wallet V2 screen — mirrors the
/// `WalletV2` grid in `docs/design/v2-handoff/components/SPScreensV2.jsx`
/// (L441-448). Extracted so the rouble values and the secondary labels
/// stay in one place; the view controller iterates the array and binds
/// each entry to an `SPAmountPreset`.
struct WalletAmountPreset {
    let value: Decimal
    let label: String
    let popular: Bool

    /// Whether this preset is the initial selection. Exactly one preset is
    /// marked as default — `500 ₽`, matching the JSX `useState(500)`.
    let isDefault: Bool
}

enum WalletPresets {

    static let presets: [WalletAmountPreset] = [
        .init(value: 100,   label: "≈ 2 откладывания",   popular: false, isDefault: false),
        .init(value: 500,   label: "≈ 10 откладываний",  popular: true,  isDefault: true),
        .init(value: 1000,  label: "≈ 20 откладываний",  popular: false, isDefault: false),
        .init(value: 2000,  label: "≈ 40 откладываний",  popular: false, isDefault: false),
        .init(value: 5000,  label: "на месяц",           popular: false, isDefault: false),
        .init(value: 10000, label: "макс.",              popular: false, isDefault: false)
    ]

    static var defaultAmount: Decimal {
        presets.first(where: { $0.isDefault })?.value ?? 500
    }

    /// Localised "Хватит на ~N откладываний при текущей цене" hint —
    /// matches the JSX hardcoded copy. The N defaults to 17 (840 ÷ 50 ≈ 17)
    /// when balance / price are not yet bound; live callers should compute
    /// it via `affordHint(forBalance:price:)`.
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
