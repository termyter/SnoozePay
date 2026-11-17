import UIKit
import XCTest
@testable import SnoozePay

/// Follow-ups of the firing price display (#1148): the stranded guard order of
/// the hint, the amount sheet's preselection and insufficient rows, the firing
/// screen → sheet wiring, and the background tone on a dollar scale.
///
/// Every wallet lives in an isolated `UserDefaults` suite
/// (`makeIsolatedDefaults`): the host app may have cached a storefront scale in
/// `.standard`, which would make the shared wallet's context depend on the simulator.
@MainActor
final class AlarmFiringPriceFollowUpTests: XCTestCase {

    private var defaults: UserDefaults!
    private var repository: TransactionRepository!
    private var scaleStore: SnoozePriceScaleStore!
    private var wallet: BalanceService!

    private let usd = Currency(code: "USD")!
    private var usdScale: SnoozePriceScale { SnoozePriceScale(currency: usd, tierStrings: ["0.99", "1.99", "2.99"])! }
    private let scheduler = AlarmScheduler(
        notificationCenter: InertNotificationCenter(), alarmKit: TestAlarmKitBackend()
    )

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        let center = NotificationCenter()
        repository = TransactionRepository(defaults: defaults)
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        wallet = BalanceService(
            defaults: defaults, transactionRepository: repository,
            notificationCenter: center, priceScaleStore: scaleStore
        )
    }

    override func tearDown() {
        // The pool empties the suite itself; never write to it from here.
        wallet = nil
        scaleStore = nil
        repository = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeController(_ alarm: Alarm, snoozeCount: Int = 0) -> CapturingController {
        let alarmRepository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        alarmRepository.save(alarm)
        let model = AlarmFiringViewModel(
            alarm: alarm, snoozeCount: snoozeCount, balanceService: wallet,
            alarmRepository: alarmRepository,
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults), ledger: repository
        )
        let controller = CapturingController(viewModel: model)
        controller.loadViewIfNeeded()
        controller.updateUI()
        return controller
    }

    private func fund(_ amount: Double, in currency: Currency) {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: amount, currency: currency), .credited)
    }

    private func sku(_ nominal: Int) -> String { "io.mobilife.snoozepay.balance.\(nominal)" }

    /// The whole catalogue in dollars: $0.99 … $9.99.
    private func dollarCatalogue() throws -> [String: TopUpOffer] {
        let prices: [Int: String] = [49: "0.99", 149: "1.49", 299: "2.99", 499: "4.99", 999: "9.99"]
        var catalogue: [String: TopUpOffer] = [:]
        for (nominal, price) in prices {
            catalogue[sku(nominal)] = try XCTUnwrap(TopUpOffer(
                productID: sku(nominal), price: Decimal(string: price)!, currencyCode: "USD", displayPrice: "$\(price)"
            ))
        }
        return catalogue
    }

    private func makeSheet(
        price: Double, currency: Currency?, catalogue: [String: TopUpOffer]
    ) -> FiringTopUpBottomSheetViewController {
        FiringTopUpBottomSheetViewController(
            snoozePrice: price, snoozePriceCurrency: currency, balance: wallet,
            notificationCenter: NotificationCenter(),
            scheduleSuccessDismissal: { _, _ in }, purchaseProduct: { _ in },
            presentPurchaseFailure: { _ in }, pauseLifecycle: { _ in }, preflightRefusal: { _ in nil },
            offerProvider: { catalogue[$0] }, arguments: []
        )
    }

    /// Row nominals in order, the selected one and the dimmed (insufficient) ones.
    private struct SheetRows {
        let ids: [Int]
        let selected: Int?
        let dimmed: [Int]
    }

    private func rows(of sheet: FiringTopUpBottomSheetViewController) -> SheetRows {
        sheet.loadViewIfNeeded()
        let rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
        let id: (FiringTopUpPresetRow) -> Int? = { Int($0.accessibilityIdentifier?.split(separator: ".").last ?? "") }
        return SheetRows(ids: rows.compactMap(id), selected: rows.first(where: \.isSelected).flatMap(id),
                         dimmed: rows.filter(\.insufficient).compactMap(id))
    }

    // MARK: - Stranded guard order

    /// At count 2 the next rung is the ceiling. A stranded ring hides its CTA,
    /// so the hint must go too instead of promising the max-price copy.
    func testStrandedRingAtTheCeilingQuotesNoHint() {
        let controller = makeController(Alarm(penaltyAmount: 50, progressiveScale: true), snoozeCount: 2)
        XCTAssertEqual(controller.snoozeHintText(), Localized.text("firing.hint.max_price"), "not stranded yet")

        XCTAssertTrue(scaleStore.record(usdScale))
        fund(9.99, in: usd)
        controller.updateUI()

        XCTAssertTrue(controller.viewModel.isLockedPriceStranded)
        XCTAssertEqual(controller.snoozeCTA?.isHidden, true)
        XCTAssertNil(controller.snoozeHintText(), "a stranded ring quotes no hint, not even the ceiling")
    }

    // MARK: - Amount sheet

    /// $4.50: the minimal sufficient pack ($4.99) is already a default row, so
    /// the rows stay put and only the preselection reads the price currency.
    /// Without it the dollar packs have unknown coverage and nothing is dimmed.
    func testSheet_priceAlreadyCoveredByADefaultRow_preselectsItAndDimsTheShortRow() throws {
        let catalogue = try dollarCatalogue()
        XCTAssertEqual(wallet.walletCurrency, .rub)

        let inDollars = rows(of: makeSheet(price: 4.50, currency: usd, catalogue: catalogue))
        XCTAssertEqual(inDollars.ids, [149, 499, 999])
        XCTAssertEqual(inDollars.selected, 499)
        XCTAssertEqual(inDollars.dimmed, [149], "$1.49 on an empty wallet does not cover $4.50")

        let inWalletCurrency = rows(of: makeSheet(price: 4.50, currency: nil, catalogue: catalogue))
        XCTAssertEqual(inWalletCurrency.ids, [149, 499, 999])
        XCTAssertEqual(inWalletCurrency.selected, 149)
        XCTAssertEqual(inWalletCurrency.dimmed, [], "unknown coverage never claims a row is short")
    }

    /// A wallet frozen in dollars holding $2.00: $2.99 + $2.00 covers $4.50, so
    /// the $2.99 pack replaces $1.49 and is preselected; no row is short.
    func testSheet_frozenDollarWalletWithPartialBalance_countsTheBalanceTowardsCoverage() throws {
        fund(2, in: usd)
        XCTAssertEqual(wallet.walletCurrency, usd)
        XCTAssertEqual(wallet.balance, 2)
        let catalogue = try dollarCatalogue()

        let sheet = rows(of: makeSheet(price: 4.50, currency: usd, catalogue: catalogue))
        XCTAssertEqual(sheet.ids, [299, 499, 999])
        XCTAssertEqual(sheet.selected, 299)
        XCTAssertEqual(sheet.dimmed, [])
    }

    /// The firing screen hands the sheet the next charge in the locked price's
    /// currency: a pristine rouble wallet facing $2.99 is offered the $2.99 pack.
    func testFiringScreen_presentsTheSheetWithTheLockedPriceAndItsCurrency() throws {
        XCTAssertTrue(scaleStore.record(usdScale))
        let catalogue = try dollarCatalogue()
        let controller = makeController(Alarm(penaltyAmount: 200))
        var built: (price: Double, currency: Currency?)?
        controller.makeTopUpSheet = { [unowned self] price, currency in
            built = (price, currency)
            return makeSheet(price: price, currency: currency, catalogue: catalogue)
        }

        controller.presentTopUpSheet()

        XCTAssertEqual(built?.price, 2.99)
        XCTAssertEqual(built?.currency, usd)
        let sheet = try XCTUnwrap(controller.presented as? FiringTopUpBottomSheetViewController)
        let state = rows(of: sheet)
        XCTAssertEqual(state.ids, [299, 499, 999])
        XCTAssertEqual(state.selected, 299)
    }

    // MARK: - Tone at the view

    /// Dollar scale, legacy 50 progressive: $1.98 at count 1 is calm, $3.96 at
    /// count 2 is past the $2.99 top tier and tense.
    func testDollarScale_backgroundToneFollowsTheTopTier() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fund(100, in: usd)
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)
        XCTAssertEqual(makeController(alarm, snoozeCount: 1).dawnBackgroundView.tone, .calm)
        XCTAssertEqual(makeController(alarm, snoozeCount: 2).dawnBackgroundView.tone, .tense)
    }
}

@MainActor
private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }

/// The real layout, without audio, observers, ticker or breathing; captures
/// what it would present instead of presenting it.
@MainActor
private final class CapturingController: AlarmFiringViewController {
    private(set) var presented: UIViewController?

    override func viewDidLoad() {
        buildFiringLayout()
    }

    override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        presented = controller
    }
}
