import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmFiringChargeFlyUpTests: XCTestCase {
    private struct PriceCase {
        let code: String
        let amount: Double
        let digits: String
    }

    func testActualAnimationLabelPreservesCurrencyAndRawFractions() throws {
        let cases = [
            PriceCase(code: "RUB", amount: 49.5, digits: "49,5"),
            PriceCase(code: "USD", amount: 2.99, digits: "2,99"),
            PriceCase(code: "EUR", amount: 1.25, digits: "1,25"),
            PriceCase(code: "KWD", amount: 0.001, digits: "0,001")
        ]
        for item in cases {
            let currency = try XCTUnwrap(Currency(code: item.code))
            let controller = makeController(amount: item.amount, currency: currency)
            let label = try XCTUnwrap(controller.makeLastChargeLabel())
            XCTAssertEqual(label.text, "−" + MoneyFormatter.string(item.amount, currency: currency))
            XCTAssertTrue(label.text?.contains(item.digits) == true)
            if currency != .rub { XCTAssertFalse(label.text?.contains("₽") == true) }
            XCTAssertEqual(label.font, AppFonts.mono(.bold, 14))
            XCTAssertFalse(label.translatesAutoresizingMaskIntoConstraints)
            XCTAssertFalse(controller.isViewLoaded, "Rendering a receipt must not start audio or timers")
            XCTAssertEqual(controller.viewModel.lastChargeAmount, item.amount)
            XCTAssertEqual(controller.viewModel.snoozeCount, 1)
        }
    }

    func testExactAmountBeyondIntRangeRendersWithoutNarrowingOrClamping() throws {
        let amount = 18_446_744_073_709_551_616.0
        let controller = makeController(amount: amount, currency: .rub)
        let label = try XCTUnwrap(controller.makeLastChargeLabel())
        XCTAssertEqual(label.text?.filter(\.isNumber), "18446744073709551616")
        XCTAssertTrue(label.text?.hasPrefix("−") == true)
        XCTAssertTrue(label.text?.hasSuffix("\u{202F}₽") == true)
        XCTAssertEqual(controller.viewModel.lastChargeAmount, amount)
    }

    func testRealZeroCreatesNoFlyUpButUnrepresentableAndUnderflowStayUnknown() throws {
        let usd = try XCTUnwrap(Currency(code: "USD"))
        XCTAssertNil(makeController(amount: 0, currency: usd).makeLastChargeLabel())
        XCTAssertNil(makeController(amount: 50, currency: usd, snoozeCount: 0).makeLastChargeLabel())
        for amount in [0.002, Double.greatestFiniteMagnitude] {
            let controller = makeController(amount: amount, currency: usd)
            let label = try XCTUnwrap(controller.makeLastChargeLabel())
            XCTAssertEqual(label.text, "—", "Invalid amounts must not print a charge of zero")
            XCTAssertFalse(controller.isViewLoaded)
            XCTAssertEqual(controller.viewModel.lastChargeAmount, amount)
        }
    }

    func testValidProgressivePenaltyOverflowStaysUnknownWithoutCrashing() throws {
        let controller = makeController(
            amount: .greatestFiniteMagnitude, currency: .rub, snoozeCount: 2, progressive: true
        )
        XCTAssertTrue(controller.viewModel.lastChargeAmount.isInfinite)
        XCTAssertEqual(try XCTUnwrap(controller.makeLastChargeLabel()).text, "—")
        XCTAssertFalse(controller.isViewLoaded)
    }

    private func makeController(
        amount: Double, currency: Currency, snoozeCount: Int = 1, progressive: Bool = false
    ) -> AlarmFiringViewController {
        let suite = "test.firing.chargeFlyUp.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(WalletCurrencyStore(defaults: defaults).freeze(currency), .frozen(currency))
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend())
        let model = AlarmFiringViewModel(
            alarm: Alarm(penaltyAmount: amount, progressiveScale: progressive), snoozeCount: snoozeCount,
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults)
        )
        return AlarmFiringViewController(viewModel: model)
    }
}
