import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmFiringBalanceCurrencyTests: XCTestCase {
    func testActualInitialAndRefreshedPillsPreserveInjectedUSDAndEURCents() {
        for (code, symbol) in [("USD", "$"), ("EUR", "€")] {
            let wallet = ReadOnlyFiringWallet(balance: 0.49, currency: Currency(code: code)!)
            let controller = makeController(wallet: wallet)
            XCTAssertEqual(controller.initialTone, .money)
            XCTAssertTrue(controller.initialText?.contains("0,49") == true)
            XCTAssertTrue(controller.initialText?.contains(symbol) == true)
            XCTAssertFalse(controller.initialText?.contains("₽") == true)
            XCTAssertEqual(controller.balancePill?.tone, .money)
            XCTAssertEqual(pillText(controller.balancePill), controller.initialText)
        }
    }

    func testRefreshReadsNewCurrencyAndRebuildsOnlyWhenZeroToneChanges() throws {
        let wallet = ReadOnlyFiringWallet(balance: 0, currency: .rub)
        let controller = makeController(wallet: wallet)
        let zero = try XCTUnwrap(controller.balancePill)
        XCTAssertEqual(controller.initialTone, .pain)
        XCTAssertTrue(controller.initialText?.contains("0\u{202F}₽") == true)

        wallet.balance = 0.49
        wallet.walletCurrency = Currency(code: "USD")!
        controller.updateUI()
        let fractional = try XCTUnwrap(controller.balancePill)
        XCTAssertFalse(fractional === zero)
        XCTAssertEqual(fractional.tone, .money)
        XCTAssertTrue(pillText(fractional).contains("0,49"))
        XCTAssertTrue(pillText(fractional).contains("$"))
        XCTAssertFalse(pillText(fractional).contains("₽"))
        XCTAssertNil(zero.superview)

        wallet.balance = 1.49
        controller.updateUI()
        XCTAssertTrue(controller.balancePill === fractional)
        XCTAssertTrue(pillText(controller.balancePill).contains("1,49"))

        wallet.balance = 0
        controller.updateUI()
        XCTAssertFalse(controller.balancePill === fractional)
        XCTAssertEqual(controller.balancePill?.tone, .pain)
        XCTAssertTrue(pillText(controller.balancePill).contains("0,00"))
        XCTAssertTrue(pillText(controller.balancePill).contains("$"))
        XCTAssertNil(fractional.superview)
        XCTAssertEqual(controller.topHeaderRow.arrangedSubviews.filter { $0 is SPPill }.count, 1)
    }

    func testActualInitialAndRefreshRenderExactBeyondIntAndCanonicalRubles() {
        for (balance, expected) in [
            (18_446_744_073_709_551_616.0, "18446744073709551616"),
            (840.0, "840")
        ] {
            let controller = makeController(wallet: ReadOnlyFiringWallet(balance: balance, currency: .rub))
            XCTAssertEqual(controller.initialText?.filter(\.isNumber), expected)
            XCTAssertEqual(pillText(controller.balancePill).filter(\.isNumber), expected)
            XCTAssertTrue(pillText(controller.balancePill).hasSuffix("\u{202F}₽"))
            XCTAssertEqual(controller.initialTone, .money)
            XCTAssertEqual(controller.balancePill?.tone, .money)
        }
    }

    func testRealIsolatedPaidWalletSuppliesCurrencyThroughRequiredProtocol() {
        let suite = "firing-currency-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wallet = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 0.49, currency: Currency(code: "USD")!), .credited)
        let rows = TransactionRepository(defaults: defaults).fetchAll()
        let controller = makeController(wallet: wallet)
        XCTAssertEqual(controller.initialTone, .money)
        XCTAssertTrue(controller.initialText?.contains("0,49") == true)
        XCTAssertTrue(controller.initialText?.contains("$") == true)
        XCTAssertFalse(controller.initialText?.contains("₽") == true)
        XCTAssertEqual(TransactionRepository(defaults: defaults).fetchAll().map(\.id), rows.map(\.id))
        XCTAssertEqual(wallet.balance, 0.49, accuracy: 1e-12)
    }

    func testActualPriceCardsPreserveCurrencyCentsOnInitialLayoutAndRefresh() throws {
        for (code, symbol) in [("USD", "$"), ("EUR", "€")] {
            let wallet = ReadOnlyFiringWallet(balance: 1, currency: Currency(code: code)!)
            let controller = makeController(wallet: wallet, penalty: 0.49)
            for initial in [controller.initialSnoozeValue, controller.initialDisabledValue] {
                XCTAssertTrue(initial?.contains("0,49") == true)
                XCTAssertTrue(initial?.contains(symbol) == true)
                XCTAssertFalse(initial?.contains("₽") == true)
            }
            let snooze = try XCTUnwrap(controller.snoozeCTA)
            let disabled = try XCTUnwrap(controller.noBalanceSnoozeCard)
            XCTAssertTrue(snooze.isEnabled)
            XCTAssertFalse(disabled.isEnabled)
            for card in [snooze, disabled] {
                XCTAssertEqual(card.price, 0.49)
                XCTAssertTrue(pillText(card).contains("−0,49"))
                XCTAssertEqual(card.currency, wallet.walletCurrency)
            }

            wallet.walletCurrency = .rub
            wallet.balance = 0
            controller.updateUI()
            for card in [snooze, disabled] {
                XCTAssertEqual(card.accessibilityValue, "0,49\u{202F}₽")
                XCTAssertFalse(card.isEnabled)
                XCTAssertTrue(card.accessibilityTraits.contains(.notEnabled))
            }
            XCTAssertTrue(controller.noBalanceContainer?.isHidden == false)
        }
    }

    func testActualPriceCardsKeepExactLargeDigitsAndDoNotInventInvalidAmounts() {
        let controller = makeController(
            wallet: ReadOnlyFiringWallet(balance: 1, currency: .rub),
            penalty: 18_446_744_073_709_551_616
        )
        let cards = [controller.snoozeCTA, controller.noBalanceSnoozeCard].compactMap { $0 }
        XCTAssertEqual(cards.count, 2)
        for card in cards {
            XCTAssertEqual(card.accessibilityValue?.filter(\.isNumber), "18446744073709551616")
            for invalid in [Double.nan, .infinity, -1, .greatestFiniteMagnitude] {
                card.update(price: invalid, currency: Currency(code: "USD")!)
                XCTAssertEqual(card.accessibilityValue, "—")
                XCTAssertTrue(pillText(card).contains("—"))
                XCTAssertFalse(pillText(card).contains("−—"))
            }
        }
    }

    private func makeController(wallet: AlarmFiringBalancing, penalty: Double = 50) -> BalanceLayoutController {
        let backend = TestAlarmKitBackend()
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: backend)
        let suite = "firing-layout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let alarm = Alarm(penaltyAmount: penalty)
        let model = AlarmFiringViewModel(
            alarm: alarm, balanceService: wallet,
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults)
        )
        let controller = BalanceLayoutController(viewModel: model)
        controller.loadViewIfNeeded()
        XCTAssertTrue(backend.scheduledIDs.isEmpty)
        XCTAssertTrue(backend.snoozedIDs.isEmpty)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
        return controller
    }
}

@MainActor
private func pillText(_ view: UIView?) -> String {
    guard let view else { return "" }
    let own = (view as? UILabel)?.text ?? ""
    return own + view.subviews.map { pillText($0) }.joined()
}

@MainActor
private final class BalanceLayoutController: AlarmFiringViewController {
    private(set) var initialText: String?
    private(set) var initialTone: SPPill.Tone?
    private(set) var initialSnoozeValue: String?
    private(set) var initialDisabledValue: String?

    override func viewDidLoad() {
        // Exercise the real layout, without audio, observers, ticker or breathing.
        buildFiringLayout()
    }

    override func updateUI() {
        if initialText == nil, let pill = balancePill {
            initialText = pillText(pill)
            initialTone = pill.tone
            initialSnoozeValue = snoozeCTA?.accessibilityValue
            initialDisabledValue = noBalanceSnoozeCard?.accessibilityValue
        }
        super.updateUI()
    }
}

private final class ReadOnlyFiringWallet: AlarmFiringBalancing {
    func acceptsPurchase(in currency: Currency) -> Bool { false }
    var balance: Double
    var walletCurrency: Currency

    init(balance: Double, currency: Currency) {
        self.balance = balance
        walletCurrency = currency
    }

    func canAfford(_ amount: Double) -> Bool { balance >= amount }
    func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? {
        XCTFail("Rendering must not charge")
        return nil
    }
    func refund(amount: Double, refundsTransactionID: UUID?) -> Bool {
        XCTFail("Rendering must not refund")
        return false
    }
}
