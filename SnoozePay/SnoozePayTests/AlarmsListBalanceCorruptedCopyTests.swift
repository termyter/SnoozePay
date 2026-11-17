import XCTest
@testable import SnoozePay

/// The corrupt-balance alert on the alarms list names the zero the reset leaves
/// in the wallet's display currency (#1109): a rouble wallet reads byte for byte
/// what it read before, a dollar wallet reads «$0.00», and with no currency the
/// sentence names no amount.
///
/// Every wallet lives in an isolated suite (`makeIsolatedDefaults`) with its own
/// `NotificationCenter`: `.shared` follows whatever the host app cached.
@MainActor
final class AlarmsListBalanceCorruptedCopyTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private var defaults: UserDefaults!

    /// The rouble body exactly as main rendered it before #1109 for a raw value
    /// of −42: the transcription, not a read-back of the catalogue under test.
    /// Plain U+0020 before «₽».
    private let roubleBody = "В хранилище обнаружено некорректное значение баланса (-42.0). "
        + "Пополнения и списания приостановлены. Сбросить баланс до 0 ₽?"

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A wallet whose stored balance is unreadable, optionally with an
    /// established currency, seen through the list view model.
    private func makeCorruptListViewModel(storedCurrency: Currency?) -> AlarmsListViewModel {
        let center = NotificationCenter()
        if let storedCurrency {
            defaults.set(storedCurrency.code, forKey: WalletCurrencyStore.storageKey)
        }
        defaults.set(-42.0, forKey: "user_balance")
        let wallet = BalanceService(defaults: defaults, notificationCenter: center)
        XCTAssertTrue(wallet.balanceCorrupted, "test precondition: the balance must be latched corrupt")
        return AlarmsListViewModel(
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler()),
            balanceService: wallet,
            transactionRepository: TransactionRepository(defaults: defaults),
            notificationCenter: center,
            alarmDefaults: AlarmDefaults(defaults: defaults),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
            )
        )
    }

    // MARK: - Catalogue

    func testEveryVariantResolvesToCopy() {
        for key in [
            "alarms.balance_corrupted.message",
            "alarms.balance_corrupted.message_currency",
            "alarms.balance_corrupted.message_unpriced"
        ] {
            XCTAssertNotEqual(Localized.text(key), key, "\(key) is missing from the catalogue")
        }
    }

    // MARK: - Body per currency

    func testRoubleWalletReadsExactlyAsBefore() {
        let body = AlarmsListViewController.balanceCorruptedMessage(rawValue: -42, currency: .rub)
        XCTAssertEqual(body, roubleBody)
        XCTAssertEqual(Array(body.utf8), Array(roubleBody.utf8), "the rouble body changed bytes")
    }

    func testDollarWalletNamesZeroInDollars() {
        let body = AlarmsListViewController.balanceCorruptedMessage(rawValue: -42, currency: usd)
        let zero = MoneyFormatter.string(Decimal(0), currency: usd)
        XCTAssertEqual(
            body, Localized.format("alarms.balance_corrupted.message_currency", "-42.0", zero)
        )
        XCTAssertTrue(body.contains("(-42.0)"), "the raw value must stay verbatim: \(body)")
        XCTAssertTrue(body.hasSuffix(" \(zero)?"), "the reset target must be dollar zero: \(body)")
        XCTAssertTrue(zero.contains("$"), "test precondition: \(zero) should be a dollar amount")
        XCTAssertFalse(body.contains("₽"), body)
    }

    func testUnknownCurrencyNamesNoAmount() {
        let body = AlarmsListViewController.balanceCorruptedMessage(rawValue: -42, currency: nil)
        XCTAssertEqual(body, Localized.format("alarms.balance_corrupted.message_unpriced", "-42.0"))
        XCTAssertTrue(body.contains("(-42.0)"), body)
        XCTAssertFalse(body.contains("₽"), body)
        XCTAssertFalse(body.contains("$"), body)
        XCTAssertFalse(
            body.replacingOccurrences(of: "(-42.0)", with: "").contains(where: \.isNumber),
            "no amount may appear besides the raw value: \(body)"
        )
    }

    // MARK: - The view model supplies the currency

    func testCorruptDollarWalletSurfacesDollarZero() {
        let viewModel = makeCorruptListViewModel(storedCurrency: usd)
        XCTAssertEqual(viewModel.balanceCurrency, usd)
        let body = AlarmsListViewController.balanceCorruptedMessage(
            rawValue: -42, currency: viewModel.balanceCurrency
        )
        XCTAssertTrue(body.hasSuffix(" \(MoneyFormatter.string(Decimal(0), currency: usd))?"), body)
        XCTAssertFalse(body.contains("₽"), body)
    }

    func testCorruptLegacyWalletKeepsTheRoubleBody() {
        let viewModel = makeCorruptListViewModel(storedCurrency: nil)
        XCTAssertEqual(viewModel.balanceCurrency, .rub)
        XCTAssertEqual(
            AlarmsListViewController.balanceCorruptedMessage(rawValue: -42, currency: viewModel.balanceCurrency),
            roubleBody
        )
    }
}
