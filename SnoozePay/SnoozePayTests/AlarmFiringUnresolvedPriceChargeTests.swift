import os
import XCTest
@testable import SnoozePay

/// #1136: the firing screen never charges a price whose currency it cannot
/// establish. It used to pass `price(...)?.currency ?? walletCurrency`, which
/// silently turned the wallet's currency check off.
///
/// Reaching it takes a legacy alarm whose progressive charge overflows to
/// infinity: `chargeAmount` still answers (so `canSnooze` lets the tap through
/// on a wallet that says it can afford it), but `price` has no `Money` for it.
final class AlarmFiringUnresolvedPriceChargeTests: XCTestCase {

    func testUnresolvedPrice_refusesBeforeAnyCharge() {
        let defaults = makeIsolatedDefaults()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())
        let wallet = AffordEverythingWallet()
        let model = AlarmFiringViewModel(
            alarm: Alarm(penaltyAmount: 1e308, progressiveScale: true), snoozeCount: 1, balanceService: wallet,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults)
        )
        XCTAssertTrue(model.canSnooze, "precondition: the tap reaches the charge")
        XCTAssertNil(model.price(forSnoozeCount: 2), "precondition: no price to take a currency from")

        var uiErrors: [String] = []
        let started = AppLogger.withTestSink({ category, level, message in
            if category == .ui, level == .error { uiErrors.append(message) }
        }, perform: { model.snooze() })

        XCTAssertFalse(started)
        XCTAssertTrue(wallet.chargeCalls.isEmpty, "no charge attempted: \(wallet.chargeCalls)")
        XCTAssertEqual(model.snoozeCount, 1)
        XCTAssertFalse(model.isSnoozeScheduling, "a refused tap must not leave the CTA locked")
        XCTAssertEqual(uiErrors.count, 1, "\(uiErrors)")
        XCTAssertTrue(uiErrors.first?.hasPrefix("firing: snooze price unresolved alarm=") == true, "\(uiErrors)")
    }
}

/// Affords any amount and records every charge attempt, guarded or not.
private final class AffordEverythingWallet: AlarmFiringBalancing {
    let balance: Double = 0
    let walletCurrency: Currency = .rub
    private(set) var chargeCalls: [Currency?] = []

    func acceptsPurchase(in currency: Currency) -> Bool { false }
    func canAfford(_ amount: Double) -> Bool { true }
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        chargeCalls.append(nil)
        return nil
    }
    func chargeWithReceipt(amount: Double, expecting currency: Currency, alarmID: UUID?) -> Transaction? {
        chargeCalls.append(currency)
        return nil
    }
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool { false }
}
