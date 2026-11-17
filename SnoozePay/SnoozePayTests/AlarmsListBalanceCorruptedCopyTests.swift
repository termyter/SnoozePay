import UIKit
import XCTest
@testable import SnoozePay

/// The corrupt-balance alert on the alarms list names the zero the reset leaves
/// in the wallet's display currency (#1109): a rouble wallet reads byte for byte
/// what it read before, a dollar wallet reads «$0.00», and with no currency the
/// sentence names no amount.
///
/// Three layers: the pure currency → text mapping (the only place the `nil`
/// case is reachable), the view model building the body from its own
/// `balanceCurrency`, and the mounted list presenting that body in its alert.
///
/// Every wallet lives in an isolated suite (`makeIsolatedDefaults`) with its own
/// `NotificationCenter`: `.shared` follows whatever the host app cached.
@MainActor
final class AlarmsListBalanceCorruptedCopyTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private var defaults: UserDefaults!
    private var window: UIWindow?

    private static let ruPrefix = "В хранилище обнаружено некорректное значение баланса"
    private static let ruMiddle = "Пополнения и списания приостановлены."
    private static let enPrefix = "The stored balance can’t be read"
    private static let enMiddle = "Top-ups and charges are paused."

    /// The catalogue words, transcribed rather than read back out of the file
    /// under test. The rouble ru and en values are the pre-#1109 text.
    private static let ruCopy: [String: String] = [
        "alarms.balance_corrupted.message": "\(ruPrefix) (%@). \(ruMiddle) Сбросить баланс до 0 ₽?",
        "alarms.balance_corrupted.message_currency": "\(ruPrefix) (%1$@). \(ruMiddle) Сбросить баланс до %2$@?",
        "alarms.balance_corrupted.message_unpriced": "\(ruPrefix) (%@). \(ruMiddle) Сбросить баланс в ноль?"
    ]
    private static let enCopy: [String: String] = [
        "alarms.balance_corrupted.message": "\(enPrefix) (%@). \(enMiddle) Reset your balance to 0 ₽?",
        "alarms.balance_corrupted.message_currency": "\(enPrefix) (%1$@). \(enMiddle) Reset your balance to %2$@?",
        "alarms.balance_corrupted.message_unpriced": "\(enPrefix) (%@). \(enMiddle) Reset your balance to zero?"
    ]

    /// The rouble body exactly as main rendered it before #1109 for a raw value
    /// of −42. Plain U+0020 before «₽».
    private let roubleBody = "\(ruPrefix) (-42.0). \(ruMiddle) Сбросить баланс до 0 ₽?"

    private var dollarZero: String { MoneyFormatter.string(Decimal(0), currency: usd) }
    private var dollarBody: String { "\(Self.ruPrefix) (-42.0). \(Self.ruMiddle) Сбросить баланс до \(dollarZero)?" }

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
    }

    override func tearDown() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
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

    /// The streak modal reads shared history and would take the presentation
    /// slot; this fixture keeps only the corrupt-balance alert.
    private final class HostedList: AlarmsListViewController {
        override func presentStreakModalIfNeeded(in viewController: UIViewController? = nil) {}
    }

    // MARK: - Catalogue

    func testEveryVariantResolvesToTheTranscribedCopy() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"),
            "en.lproj/Localizable.strings is not in the app bundle"
        )
        let english = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        for (key, expected) in Self.ruCopy {
            XCTAssertNotEqual(Localized.text(key), key, "\(key) is missing from the catalogue")
            XCTAssertEqual(Localized.text(key), expected, "ru copy drifted for \(key)")
            XCTAssertEqual(english[key], Self.enCopy[key], "en copy drifted for \(key)")
        }
    }

    // MARK: - Pure mapping

    func testMappingPerCurrency() {
        let rouble = AlarmsListViewModel.balanceCorruptedMessage(rawValue: -42, currency: .rub)
        XCTAssertEqual(Array(rouble.utf8), Array(roubleBody.utf8), "the rouble body changed bytes: \(rouble)")

        XCTAssertTrue(dollarZero.contains("$"), "test precondition: \(dollarZero) should be a dollar amount")
        XCTAssertEqual(AlarmsListViewModel.balanceCorruptedMessage(rawValue: -42, currency: usd), dollarBody)
    }

    func testUnknownCurrencyNamesNoAmount() {
        let body = AlarmsListViewModel.balanceCorruptedMessage(rawValue: -42, currency: nil)
        XCTAssertEqual(body, "\(Self.ruPrefix) (-42.0). \(Self.ruMiddle) Сбросить баланс в ноль?")
        XCTAssertFalse(
            body.replacingOccurrences(of: "(-42.0)", with: "").contains(where: \.isNumber),
            "no amount may appear besides the raw value: \(body)"
        )
    }

    // MARK: - The view model reads its own currency

    func testCorruptDollarWalletBodyNamesDollarZero() {
        let viewModel = makeCorruptListViewModel(storedCurrency: usd)
        XCTAssertEqual(viewModel.balanceCorruptedMessage(rawValue: -42), dollarBody)
    }

    func testCorruptLegacyWalletBodyIsTheRoubleText() {
        let viewModel = makeCorruptListViewModel(storedCurrency: nil)
        XCTAssertEqual(viewModel.balanceCorruptedMessage(rawValue: -42), roubleBody)
    }

    // MARK: - The mounted list presents that body

    func testMountedListAlertForDollarWalletNamesDollarZero() throws {
        let viewModel = makeCorruptListViewModel(storedCurrency: usd)
        let controller = HostedList(viewModel: viewModel, bannerStreakCount: { 0 })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        self.window = window
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        // The callback the controller bound in `viewDidLoad`. If appearance
        // already presented the alert, its guard keeps that one.
        let callback = try XCTUnwrap(viewModel.onBalanceCorrupted, "the list did not bind the corrupt callback")
        callback(-42)

        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, Localized.text("alarms.balance_corrupted.title"))
        XCTAssertEqual(alert.message, dollarBody)
    }
}
