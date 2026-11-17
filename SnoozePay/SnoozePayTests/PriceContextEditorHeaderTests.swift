import UIKit
import XCTest
@testable import SnoozePay

/// #1151 follow-ups: the editor's deletion sheet reads the editor's injected
/// wallet, the alarms-list pill's low tone follows `isLowBalance`, and the
/// wallet card hides its hint when no price resolves.
///
/// Every wallet lives in an isolated suite (`makeIsolatedDefaults`) with its own
/// `NotificationCenter`: `.shared` follows the scale the host app cached.
@MainActor
final class PriceContextEditorHeaderTests: XCTestCase {

    private let usd = Currency(code: "USD")!

    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var scaleStore: SnoozePriceScaleStore!
    private var ledger: TransactionRepository!
    private var wallet: BalanceService!
    private var alarms: AlarmRepository!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        center = NotificationCenter()
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        ledger = TransactionRepository(defaults: defaults)
        wallet = BalanceService(
            defaults: defaults, transactionRepository: ledger,
            notificationCenter: center, priceScaleStore: scaleStore
        )
        alarms = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
    }

    override func tearDown() {
        // The pool empties the suite itself; never write to it from here.
        alarms = nil
        wallet = nil
        ledger = nil
        scaleStore = nil
        center = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func recordDollarScale() {
        XCTAssertTrue(scaleStore.record(SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])!))
    }

    private func makeEditor() -> CreateAlarmViewModel {
        CreateAlarmViewModel(
            repository: alarms,
            defaults: AlarmDefaults(defaults: defaults),
            balanceService: wallet,
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
            ),
            priceContext: wallet.priceContext
        )
    }

    private func contextLine(_ editor: CreateAlarmViewModel) -> String {
        AlarmDeletionCopy.contextLine(
            repeatDays: editor.repeatDays, repeatMode: editor.repeatMode,
            time: editor.time, clockTime: editor.selectedTimeOfDay
        )
    }

    private func headerTone() -> SPAlarmsListHeader.PillTone {
        let viewModel = AlarmsListViewModel(
            alarmRepository: alarms, balanceService: wallet, transactionRepository: ledger,
            notificationCenter: center, alarmDefaults: AlarmDefaults(defaults: defaults),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
            )
        )
        viewModel.loadData()
        let header = SPAlarmsListHeader()
        header.setBalance(
            Decimal(viewModel.balance), currency: viewModel.balanceCurrency,
            hint: viewModel.balanceHint, isLow: viewModel.isLowBalance
        )
        return header.pillTone
    }

    private static func firstView(in view: UIView, where match: (UIView) -> Bool) -> UIView? {
        if match(view) { return view }
        for subview in view.subviews {
            if let found = firstView(in: subview, where: match) { return found }
        }
        return nil
    }

    private func rouble(_ amount: Double) {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: amount, currency: nil), .credited)
    }

    // MARK: - Editor deletion sheet

    func testEditorDeletionBody_pristineDollarStorefrontShowsDollarZero() {
        recordDollarScale()
        let body = makeEditor().deletionBody
        XCTAssertTrue(body.contains(MoneyFormatter.string(0.0, currency: usd)), body)
        XCTAssertFalse(body.contains("₽"), body)
    }

    func testEditorDeletionBody_storedDollarWalletShowsItsBalance() {
        recordDollarScale()
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1.99, currency: usd), .credited)
        let body = makeEditor().deletionBody
        XCTAssertTrue(body.contains(MoneyFormatter.string(1.99, currency: usd)), body)
        XCTAssertFalse(body.contains("₽"), body)
    }

    func testEditorDeletionBody_roubleIsByteIdenticalToBefore() {
        rouble(840)
        let editor = makeEditor()
        XCTAssertEqual(
            editor.deletionBody,
            Localized.format(
                "alarms.delete.body", contextLine(editor),
                Localized.format("alarms.delete.reassurance", "840\u{202F}₽")
            )
        )
    }

    /// The sheet the editor presents carries the injected wallet's body, not
    /// one built from `BalanceService.shared`.
    func testEditorPresentsTheSheetWithTheInjectedWalletBody() throws {
        recordDollarScale()
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1.99, currency: usd), .credited)
        let editor = makeEditor()
        let controller = CreateAlarmViewController(viewModel: editor)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        controller.confirmDelete()

        let sheet = try XCTUnwrap(controller.presentedViewController as? ConfirmDeleteAlarmViewController)
        sheet.loadViewIfNeeded()
        let label = try XCTUnwrap(
            Self.firstView(in: sheet.view) { $0.accessibilityIdentifier == "confirmDelete.body" } as? UILabel
        )
        XCTAssertEqual(label.text, editor.deletionBody)
        XCTAssertTrue(label.text?.contains(MoneyFormatter.string(1.99, currency: usd)) == true, label.text ?? "")
        sheet.dismiss(animated: false)
    }

    // MARK: - Alarms-list pill tone

    func testPillTone_dollarWalletFollowsTheResolvedThreshold() {
        recordDollarScale()
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1.99, currency: usd), .credited)
        XCTAssertEqual(headerTone(), .low, "$1.99 is at the mid-tier threshold")
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 3.01, currency: usd), .credited)
        XCTAssertEqual(headerTone(), .normal, "$5.00 is five snoozes, not «under 100»")
    }

    func testPillTone_roubleBoundariesAreUnchanged() {
        XCTAssertEqual(headerTone(), .zero)
        rouble(100)
        XCTAssertEqual(headerTone(), .low, "≤ 100 ₽ is low, as before")
        rouble(1)
        XCTAssertEqual(headerTone(), .normal)
    }

    // MARK: - Wallet card

    func testWalletCard_unavailableContextHidesTheHint() throws {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: 1.99, currency: usd), .credited)
        XCTAssertEqual(wallet.priceContext, .unavailable(usd))
        let controller = WalletViewController(balanceService: wallet, transactionRepository: ledger)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)

        let card = try XCTUnwrap(Self.firstView(in: controller.view) { $0 is SPBalanceCard } as? SPBalanceCard)
        XCTAssertNil(card.hint, "no snooze count is invented for an unresolvable price")
    }
}
