import UIKit
import XCTest
@testable import SnoozePay

/// The firing screen shows every price in the currency of the price locked for
/// the ring (#1142): hint, CTA, no-balance card, top-up pick and tone. Rouble
/// wallets render exactly what they rendered before.
///
/// Every wallet lives in an isolated `UserDefaults` suite
/// (`makeIsolatedDefaults`): the host app may have cached a storefront scale in
/// `.standard`, which would make the shared wallet's context depend on the simulator.
@MainActor
final class AlarmFiringPriceDisplayTests: XCTestCase {

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

    private func makeViewModel(_ alarm: Alarm, snoozeCount: Int = 0) -> AlarmFiringViewModel {
        let alarmRepository = AlarmRepository(defaults: defaults, scheduler: scheduler)
        alarmRepository.save(alarm)
        return AlarmFiringViewModel(
            alarm: alarm, snoozeCount: snoozeCount, balanceService: wallet,
            alarmRepository: alarmRepository,
            scheduler: scheduler, wakeStore: WakeEventStore(defaults: defaults), ledger: repository
        )
    }

    private func makeController(
        _ alarm: Alarm, snoozeCount: Int = 0,
        purchase: ((AlarmFiringViewController) -> AlarmFiringNoBalancePurchase)? = nil
    ) -> PriceDisplayController {
        let controller = PriceDisplayController(viewModel: makeViewModel(alarm, snoozeCount: snoozeCount))
        if let purchase { controller.noBalancePurchase = purchase(controller) }
        controller.loadViewIfNeeded()
        controller.updateUI()
        return controller
    }

    private func fund(_ amount: Double, in currency: Currency) {
        XCTAssertEqual(wallet.topUpFromPurchase(amount: amount, currency: currency), .credited)
    }

    private func money(_ text: String, _ currency: Currency) -> String {
        MoneyFormatter.string(Decimal(string: text)!, currency: currency)
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

    // MARK: - Rouble parity

    /// Presets 20/50/100/200/500, flat and progressive, counts 0…5: CTA, card,
    /// hint, title and tone equal the pre-#1142 formulas, which read
    /// `alarm.penalty` in the wallet currency and a bare `>= 200`.
    func testRoubleWallet_everyPriceTextAndToneEqualsThePreviousFormulas() throws {
        fund(1_000_000, in: .rub)
        for amount in [20.0, 50, 100, 200, 500] {
            for progressive in [false, true] {
                let alarm = Alarm(penaltyAmount: amount, progressiveScale: progressive)
                for count in 0...5 {
                    let label = "\(amount) progressive=\(progressive) count=\(count)"
                    let controller = makeController(alarm, snoozeCount: count)
                    let model = controller.viewModel
                    let penalty = alarm.penalty(forSnoozeCount: count + 1)

                    XCTAssertEqual(model.priceCurrency, .rub, label)
                    let cta = try XCTUnwrap(controller.snoozeCTA, label)
                    XCTAssertEqual(cta.accessibilityValue, MoneyFormatter.string(penalty, currency: .rub), label)
                    XCTAssertEqual(controller.noBalanceSnoozeCard?.accessibilityValue, cta.accessibilityValue, label)
                    XCTAssertEqual(cta.currency, .rub, label)

                    let oldHint: String?
                    if !progressive {
                        oldHint = nil
                    } else if alarm.isPenaltyAtCeiling(forSnoozeCount: count + 2) {
                        oldHint = Localized.text("firing.hint.max_price")
                    } else {
                        let next = try XCTUnwrap(MoneyFormatter.quotedString(
                            alarm.penalty(forSnoozeCount: count + 2), currency: .rub
                        ))
                        oldHint = Localized.format("firing.hint.next_price", next)
                    }
                    XCTAssertEqual(controller.snoozeHintText(), oldHint, label)

                    XCTAssertEqual(model.snoozeButtonTitle, Localized.format(
                        "firing.snooze.button.affordable", alarm.snoozeMinutes, MoneyFormatter.string(penalty)
                    ), label)
                    XCTAssertEqual(model.isPriceTense, progressive && penalty >= 200, label)
                }
            }
        }
    }

    // MARK: - Dollar wallet with a cached scale

    func testDollarWallet_progressiveLegacyFifty_quotesTheLadderInDollars() throws {
        XCTAssertTrue(scaleStore.record(usdScale))
        fund(100, in: usd)
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: true)

        let first = makeController(alarm, snoozeCount: 0)
        XCTAssertEqual(first.viewModel.priceCurrency, usd)
        XCTAssertEqual(first.snoozeCTA?.accessibilityValue, money("0.99", usd))
        XCTAssertEqual(first.snoozeCTA?.currency, usd)
        XCTAssertEqual(first.snoozeHintText(), Localized.format("firing.hint.next_price", money("1.98", usd)))
        XCTAssertFalse(first.snoozeHintText()?.contains("₽") ?? true)
        XCTAssertEqual((1...4).map { first.viewModel.priceText(forSnoozeCount: $0) },
                       ["0.99", "1.98", "3.96", "7.92"].map { money($0, usd) })
        XCTAssertFalse(first.viewModel.snoozeButtonTitle.contains("₽"))
        XCTAssertTrue(first.viewModel.snoozeButtonTitle.contains(money("0.99", usd)))

        let atCap = makeController(alarm, snoozeCount: 2)
        XCTAssertEqual(atCap.snoozeHintText(), Localized.text("firing.hint.max_price"))
        XCTAssertEqual(atCap.snoozeCTA?.accessibilityValue, money("3.96", usd))
    }

    /// Tone: tense from the scale's top tier ($2.99 here), so the dollar ladder
    /// turns tense on its third rung exactly as the base-50 rouble ladder does.
    func testDollarWallet_toneTurnsTenseAtTheScalesTopTier() {
        XCTAssertTrue(scaleStore.record(usdScale))
        fund(100, in: usd)
        let progressive = Alarm(penaltyAmount: 50, progressiveScale: true)
        XCTAssertEqual((0...5).map { makeViewModel(progressive, snoozeCount: $0).isPriceTense },
                       [false, false, true, true, true, true])
        XCTAssertTrue(makeViewModel(Alarm(penaltyAmount: 200, progressiveScale: true)).isPriceTense)
        XCTAssertFalse(makeViewModel(Alarm(penaltyAmount: 200, progressiveScale: false)).isPriceTense,
                       "flat alarms never escalate the tone")
    }

    // MARK: - Pristine wallet on a dollar storefront

    func testPristineWalletOnDollarStorefront_cardAndTopUpPickAreInDollars() throws {
        XCTAssertTrue(scaleStore.record(usdScale))
        let catalogue = try dollarCatalogue()
        // 200 ₽ legacy → the high tier, $2.99. Reckoned in roubles the dollar
        // packs had unknown coverage and the cheapest default ($1.49) was
        // picked; in dollars the minimal sufficient pack is the $2.99 one.
        let controller = makeController(Alarm(penaltyAmount: 200)) { controller in
            AlarmFiringNoBalancePurchase(
                controller: controller, center: NotificationCenter(),
                dispatch: { _ in }, offerProvider: { catalogue[$0] },
                beginFeedback: {}, endFeedback: {}
            )
        }

        XCTAssertEqual(wallet.walletCurrency, .rub, "display only: the wallet itself is not stamped")
        XCTAssertEqual(controller.viewModel.priceCurrency, usd)
        XCTAssertEqual(controller.noBalanceContainer?.isHidden, false)
        let card = try XCTUnwrap(controller.noBalanceSnoozeCard)
        XCTAssertEqual(card.accessibilityValue, money("2.99", usd))
        XCTAssertFalse(card.accessibilityValue?.contains("₽") ?? true)
        XCTAssertEqual(controller.noBalancePurchase.offer?.productID, sku(299),
                       "sufficiency is reckoned in dollars: the minimal pack covering $2.99")
    }

    /// The amount sheet reckons coverage of the next charge in the price's
    /// currency, not the wallet's: a pristine rouble wallet facing a $2.99
    /// charge is offered and preselected the $2.99 pack. Without the price
    /// currency the dollar packs have unknown coverage and the sheet keeps its
    /// default rows on the cheapest one.
    func testTopUpSheet_reckonsCoverageInThePriceCurrencyNotTheWallets() throws {
        let catalogue = try dollarCatalogue()
        func sheetRows(priceCurrency: Currency?) -> (ids: [Int], selected: Int?) {
            let sheet = FiringTopUpBottomSheetViewController(
                snoozePrice: 2.99, snoozePriceCurrency: priceCurrency, balance: wallet,
                notificationCenter: NotificationCenter(),
                scheduleSuccessDismissal: { _, _ in }, purchaseProduct: { _ in },
                presentPurchaseFailure: { _ in }, pauseLifecycle: { _ in }, preflightRefusal: { _ in nil },
                offerProvider: { catalogue[$0] }, arguments: []
            )
            sheet.loadViewIfNeeded()
            let rows = descendants(sheet.view).compactMap { $0 as? FiringTopUpPresetRow }
            let id: (FiringTopUpPresetRow) -> Int? = {
                Int($0.accessibilityIdentifier?.split(separator: ".").last ?? "")
            }
            return (rows.compactMap(id), rows.first(where: \.isSelected).flatMap(id))
        }
        XCTAssertEqual(wallet.walletCurrency, .rub)

        let inDollars = sheetRows(priceCurrency: usd)
        XCTAssertEqual(inDollars.ids, [299, 499, 999], "the minimal sufficient pack is swapped in")
        XCTAssertEqual(inDollars.selected, 299)

        let inWalletCurrency = sheetRows(priceCurrency: nil)
        XCTAssertEqual(inWalletCurrency.ids, [149, 499, 999], "rouble wallet vs dollar packs: coverage unknown")
        XCTAssertEqual(inWalletCurrency.selected, 149)
    }

    // MARK: - Mid-ring freeze in another currency

    func testWalletFrozenInAnotherCurrencyMidRing_hidesTheCardAndCTAAndShowsTheRefusal() throws {
        let controller = makeController(Alarm(penaltyAmount: 50, progressiveScale: true))
        XCTAssertEqual(controller.viewModel.lockedPriceContext, .scale(.rouble))
        XCTAssertEqual(controller.noBalanceContainer?.isHidden, false, "pristine rouble wallet: the top-up route")
        XCTAssertTrue(controller.progressionUnavailableLabel.isHidden)

        XCTAssertTrue(scaleStore.record(usdScale))
        fund(9.99, in: usd)
        controller.updateUI()

        XCTAssertTrue(controller.viewModel.isLockedPriceStranded)
        XCTAssertEqual(controller.noBalanceContainer?.isHidden, true)
        XCTAssertEqual(controller.snoozeCTA?.isHidden, true)
        XCTAssertFalse(controller.progressionUnavailableLabel.isHidden)
        XCTAssertEqual(controller.progressionUnavailableLabel.text, Localized.text("firing.progression.unavailable"))
        XCTAssertNil(controller.snoozeHintText(), "a stranded price quotes no number")
        XCTAssertFalse(controller.viewModel.isPriceTense)
    }
}

@MainActor
private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }

/// The real layout, without audio, observers, ticker or breathing.
@MainActor
private final class PriceDisplayController: AlarmFiringViewController {
    override func viewDidLoad() {
        buildFiringLayout()
    }
}
