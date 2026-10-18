import Foundation

/// One amount tile in the Deposit bottom sheet (issue #233, artboard 19).
///
/// `productID` points at an existing StoreKit SKU — the design's
/// 50/250/400/500/700/1000 line-up is pending a PM decision on new App
/// Store Connect products, so the sheet ships with the live 49/149/299/
/// 499/999 catalogue (see issue #233 item 8).
struct DepositPreset: Equatable {
    let amount: Int
    let productID: String
    let popular: Bool
}

/// Stable SKU mapping and initial selection for the Deposit bottom sheet.
enum DepositPresets {

    /// The five live StoreKit SKUs, cheapest first. 149 ₽ carries the
    /// «Популярно» badge and is the initial selection.
    static let presets: [DepositPreset] = [49, 149, 299, 499, 999].map { amount in
        DepositPreset(
            amount: amount,
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

}
