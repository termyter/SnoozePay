import UIKit
import XCTest
@testable import SnoozePay

/// The alarms list's gear builds Settings priced from the list's own wallet
/// and notification center (#1155), not from `BalanceService.shared`.
@MainActor
final class SettingsGearWiringTests: XCTestCase {

    func testGearSettingsQuotesTheListWalletAndFollowsItsCenter() {
        let usd = Currency(code: "USD")!
        let defaults = makeIsolatedDefaults()
        let center = NotificationCenter()
        let ledger = TransactionRepository(defaults: defaults)
        let wallet = BalanceService(
            defaults: defaults, transactionRepository: ledger, notificationCenter: center,
            priceScaleStore: SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        )
        let model = AlarmsListViewModel(
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler()),
            balanceService: wallet, transactionRepository: ledger, notificationCenter: center,
            alarmDefaults: AlarmDefaults(defaults: defaults),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
            )
        )
        let list = AlarmsListViewController(
            viewModel: model, bannerStreakCount: { 0 },
            occurrenceRecovery: EmptyRecovery(), recoveryNotificationCenter: center
        )

        let settings = list.makeSettingsViewController()
        XCTAssertEqual(settings.priceContext, .scale(.rouble), "a pristine isolated wallet prices in roubles")

        // A dollar purchase with no cached dollar scale: only this wallet knows.
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 3, currency: usd), .credited)
        XCTAssertEqual(wallet.priceContext, .unavailable(usd))
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { settings.priceContext == .unavailable(usd) }
            },
            object: nil
        )
        wait(for: [moved], timeout: 5)
        XCTAssertEqual(list.makeSettingsViewController().priceContext, .unavailable(usd))
    }
}

@MainActor
private final class EmptyRecovery: AlarmOccurrenceRecovering {
    func pendingFinishes() throws -> [AlarmOccurrenceRecoveryEntry] { [] }
    func resume(
        _ ticket: AlarmOccurrenceFinishTicket
    ) -> Result<AlarmOccurrenceFinishOutcome, AlarmOccurrenceFinishError> {
        XCTFail("the gear test never resumes a finish")
        return .failure(.unsupported)
    }
}
