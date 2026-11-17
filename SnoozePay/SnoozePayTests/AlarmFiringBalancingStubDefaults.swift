import Foundation
@testable import SnoozePay

/// Test-target default for the currency-checked charge (#1143), so the billing
/// stubs that model only balance keep compiling unchanged.
///
/// Lives here, not in the app target, on purpose: there the requirement has no
/// default, so a production wallet must implement the guard itself.
/// `BalanceService` does; this forwarding copy is never its witness.
extension AlarmFiringBalancing {
    func chargeWithReceipt(amount: Double, expecting currency: Currency, alarmID: UUID?) -> Transaction? {
        guard currency == walletCurrency else { return nil }
        return chargeWithReceipt(amount: amount, alarmID: alarmID)
    }
}
