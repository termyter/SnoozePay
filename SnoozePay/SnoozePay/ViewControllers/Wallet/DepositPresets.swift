import Foundation

/// One amount tile in the Deposit bottom sheet (issue #233, artboard 19).
///
/// `productID` points at an existing StoreKit SKU — the design's
/// 50/250/400/500/700/1000 line-up is pending a PM decision on new App
/// Store Connect products, so the sheet ships with the live 49/149/299/
/// 499/999 catalogue (see issue #233 item 8).
struct DepositPreset: Equatable {
    let amount: Int
    let label: String
    let productID: String
    let popular: Bool
}

/// Preset catalogue + label math for `DepositBottomSheetViewController`.
/// Extracted from the controller so the SKU mapping and the localized
/// "≈ N откладываний" pluralisation stay unit-testable.
enum DepositPresets {

    /// Average snooze price used for the "≈ N откладываний" hint. Matches
    /// the default penalty the rest of the app assumes (50 ₽).
    static let averageSnoozePrice = 50

    /// The five live StoreKit SKUs, cheapest first. 149 ₽ carries the
    /// "Популярно" badge and is the initial selection.
    static let presets: [DepositPreset] = [49, 149, 299, 499, 999].map { amount in
        DepositPreset(
            amount: amount,
            label: snoozeCountLabel(forAmount: amount),
            productID: "io.mobilife.snoozepay.balance.\(amount)",
            popular: amount == 149
        )
    }

    /// Initial selection — the popular tile, falling back to the first.
    static var defaultAmount: Int {
        presets.first(where: { $0.popular })?.amount ?? presets.first?.amount ?? 149
    }

    static func preset(forAmount amount: Int) -> DepositPreset? {
        presets.first { $0.amount == amount }
    }

    /// "≈ N откладываний" secondary label. N is the rounded number of
    /// snoozes the amount buys at `averagePrice`, floored at 1 so the
    /// cheapest tile never reads "≈ 0".
    static func snoozeCountLabel(forAmount amount: Int, averagePrice: Int = averageSnoozePrice) -> String {
        guard averagePrice > 0 else { return "" }
        let count = max(1, Int((Double(amount) / Double(averagePrice)).rounded()))
        return "≈ \(count) \(snoozeNoun(for: count))"
    }

    /// Pluralisation for "откладывание".
    static func snoozeNoun(for count: Int) -> String {
        Plural.word(count, .snoozes)
    }
}
