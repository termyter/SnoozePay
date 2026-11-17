import UIKit
import XCTest
@testable import SnoozePay

/// The editor offers the snooze price as tiers of the wallet's scale outside
/// roubles (#1146). Every context is injected; nothing here reads
/// `BalanceService.shared`, whose host-simulator wallet may cache a USD scale.
@MainActor
final class CreateAlarmPriceTierTests: XCTestCase {

    private var defaults: UserDefaults!
    private var repository: AlarmRepository!

    private let usd = Currency(code: "USD")!
    private var usdScale: SnoozePriceScale {
        SnoozePriceScale(currency: usd, tiers: ["0.99", "1.99", "2.99"].map { Decimal(string: $0)! })!
    }

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        repository = AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
    }

    override func tearDown() {
        repository = nil
        defaults = nil
        super.tearDown()
    }

    private func makeViewModel(
        alarm: Alarm? = nil, defaultAmount: Double? = nil, context: SnoozePriceContext
    ) -> CreateAlarmViewModel {
        if let alarm { XCTAssertTrue(repository.save(alarm)) }
        let alarmDefaults = AlarmDefaults(defaults: defaults)
        if let defaultAmount { alarmDefaults.penaltyAmount = defaultAmount }
        return CreateAlarmViewModel(
            alarm: alarm,
            repository: repository,
            defaults: alarmDefaults,
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available),
                notificationCenter: NotificationCenter()
            ),
            priceContext: context
        )
    }

    private func savedAlarm() throws -> Alarm {
        let saved = try repository.fetchAllChecked()
        XCTAssertEqual(saved.count, 1)
        return try XCTUnwrap(saved.first)
    }

    private func json(_ alarm: Alarm) throws -> [String: Any] {
        let data = try JSONEncoder().encode(alarm)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Rouble context: unchanged

    func testRoubleContextKeepsAmountEntryAndSavesNoTier() throws {
        let model = makeViewModel(context: .scale(.rouble))
        XCTAssertTrue(model.offersAmountEntry)
        XCTAssertTrue(model.tierPrices.isEmpty)
        XCTAssertNil(model.selectedTier)
        model.selectTier(.high)
        XCTAssertNil(model.selectedTier, "no tiers are offered in roubles")
        model.penaltyAmount = 137
        XCTAssertTrue(model.save())
        let saved = try savedAlarm()
        XCTAssertEqual(saved.penaltyAmount, 137)
        XCTAssertNil(saved.penaltyTier)
        XCTAssertNil(try json(saved)["penaltyTier"], "rouble JSON carries no tier key")
        XCTAssertEqual(model.progressiveChain, [137, 274, 548, 1096])
    }

    // MARK: - Production wiring

    func testControllerReadsThePriceContextOfTheWalletItIsGiven() {
        let center = NotificationCenter()
        let scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        XCTAssertTrue(scaleStore.record(usdScale))
        let wallet = BalanceService(
            defaults: defaults, transactionRepository: TransactionRepository(defaults: defaults),
            notificationCenter: center, priceScaleStore: scaleStore
        )
        XCTAssertEqual(wallet.walletCurrency, .rub, "pristine wallet")
        let sut = CreateAlarmViewController(alarm: nil, balanceService: wallet)
        XCTAssertEqual(sut.viewModel.priceContext, .scale(usdScale))
        XCTAssertFalse(sut.viewModel.offersAmountEntry)
        XCTAssertEqual(sut.viewModel.walletCurrency, .rub, "the view model uses the same wallet")
    }

    // MARK: - USD scale

    func testUSDScaleOffersThreeTierPricesAndNoAmountEntry() {
        let model = makeViewModel(context: .scale(usdScale))
        XCTAssertFalse(model.offersAmountEntry)
        XCTAssertEqual(model.priceCurrency, usd)
        XCTAssertEqual(model.tierPrices.map(\.amount), ["0.99", "1.99", "2.99"].map { Decimal(string: $0)! })
        XCTAssertTrue(model.tierPrices.allSatisfy { $0.currency == usd })
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(
            model.tierPrices.map { MoneyFormatter.string($0.amount, currency: usd, locale: english) },
            ["$0.99", "$1.99", "$2.99"]
        )
    }

    func testSelectingMidSavesTierAndReopeningPreselectsIt() throws {
        let model = makeViewModel(context: .scale(usdScale))
        XCTAssertEqual(model.selectedTier, .low, "a new alarm opens on its default 50 read as low")
        model.selectTier(.mid)
        XCTAssertTrue(model.save())
        let saved = try savedAlarm()
        XCTAssertEqual(saved.penaltyTier, .mid)
        XCTAssertEqual(saved.penaltyAmount, 100, "the rouble equivalent of mid")
        XCTAssertEqual(try json(saved)["penaltyTier"] as? Int, 2)

        let reopened = makeViewModel(alarm: saved, context: .scale(usdScale))
        XCTAssertEqual(reopened.selectedTier, .mid)
    }

    func testLegacyAmountsOpenOnTheirTier() {
        for (amount, tier) in [(20.0, SnoozePriceTier.low), (50, .low), (51, .mid), (100, .mid), (500, .high)] {
            let model = makeViewModel(alarm: Alarm(penaltyAmount: amount), context: .scale(usdScale))
            XCTAssertEqual(model.selectedTier, tier, "\(amount)")
            repository = AlarmRepository(
                defaults: makeIsolatedDefaults(), scheduler: AlarmsListViewModelTests.StubScheduler()
            )
        }
    }

    func testNewAlarmSavedUntouchedKeepsTheDefaultAmountAndChargesTheLitChip() throws {
        for (amount, lit, charged) in [(50.0, SnoozePriceTier.low, "0.99"), (500, .high, "2.99")] {
            repository = AlarmRepository(
                defaults: makeIsolatedDefaults(), scheduler: AlarmsListViewModelTests.StubScheduler()
            )
            let model = makeViewModel(defaultAmount: amount, context: .scale(usdScale))
            XCTAssertEqual(model.selectedTier, lit)
            XCTAssertTrue(model.save())
            let saved = try savedAlarm()
            XCTAssertEqual(saved.penaltyAmount, amount)
            XCTAssertNil(saved.penaltyTier)
            XCTAssertNil(try json(saved)["penaltyTier"])
            let shown = model.tierPrices[lit.rawValue - 1]
            let resolved = SnoozePriceResolver.base(saved.price, in: .scale(usdScale))
            XCTAssertEqual(resolved, shown, "shown == charged")
            XCTAssertEqual(resolved?.amount, Decimal(string: charged))
        }
    }

    func testTappingTheLitChipDoesNotRewriteTheRecord() throws {
        let original = Alarm(penaltyAmount: 137, repeatMode: .never)
        let model = makeViewModel(alarm: original, context: .scale(usdScale))
        XCTAssertEqual(model.selectedTier, .high)
        model.selectTier(.high)
        XCTAssertTrue(model.save())
        XCTAssertEqual(try savedAlarm(), original)
    }

    func testPickingAnotherTierAndBackKeepsTheRecord() throws {
        let original = Alarm(penaltyAmount: 137, repeatMode: .never)
        let model = makeViewModel(alarm: original, context: .scale(usdScale))
        model.selectTier(.low)
        model.selectTier(.high)
        XCTAssertTrue(model.save())
        XCTAssertEqual(try savedAlarm(), original)
    }

    func testLegacy50AlarmSavedUntouchedIsNotRewritten() throws {
        let original = Alarm(penaltyAmount: 50, repeatMode: .never)
        let model = makeViewModel(alarm: original, context: .scale(usdScale))
        XCTAssertEqual(model.selectedTier, .low)
        XCTAssertTrue(model.save())
        let saved = try savedAlarm()
        XCTAssertEqual(saved, original)
        XCTAssertNil(try json(saved)["penaltyTier"])
    }

    func testFreeAlarmLightsNoTierAndStaysFree() throws {
        let original = Alarm(penaltyAmount: 0, repeatMode: .never)
        let model = makeViewModel(alarm: original, context: .scale(usdScale))
        XCTAssertNil(model.selectedTier)
        XCTAssertEqual(model.progressiveChain, [0, 0, 0, 0])
        XCTAssertTrue(model.save())
        XCTAssertEqual(try savedAlarm(), original)
    }

    func testProgressiveChainDoublesTheTierPriceInTheContext() {
        let model = makeViewModel(context: .scale(usdScale))
        assertChain(model.progressiveChain, [0.99, 1.98, 3.96, 7.92])
        model.selectTier(.high)
        assertChain(model.progressiveChain, [2.99, 5.98, 11.96, 23.92])
        XCTAssertTrue(model.progressiveScalePreview.contains("$"))
        XCTAssertFalse(model.progressiveScalePreview.contains("₽"))
    }

    // MARK: - Unavailable

    func testUnavailableShowsNoNumbersAndKeepsThePriceOnSave() throws {
        for original in [Alarm(penaltyAmount: 137), Alarm(penaltyAmount: 50, penaltyTier: .high)] {
            repository = AlarmRepository(
                defaults: makeIsolatedDefaults(), scheduler: AlarmsListViewModelTests.StubScheduler()
            )
            let model = makeViewModel(alarm: original, context: .unavailable(usd))
            XCTAssertFalse(model.offersAmountEntry)
            XCTAssertTrue(model.tierPrices.isEmpty)
            XCTAssertNil(model.selectedTier)
            model.selectTier(.low)
            XCTAssertNil(model.selectedTier)
            XCTAssertTrue(model.progressiveChain.allSatisfy(\.isNaN))
            XCTAssertEqual(
                model.progressiveScalePreview.components(separatedBy: " → ").map { $0.hasSuffix("—") },
                [true, true, true, true], model.progressiveScalePreview
            )
            XCTAssertTrue(model.save())
            let saved = try savedAlarm()
            XCTAssertEqual(saved.penaltyAmount, original.penaltyAmount)
            XCTAssertEqual(saved.penaltyTier, original.penaltyTier)
        }
    }

    // MARK: - Editor wiring

    func testEditorCardShowsTierChipsAndATapReachesTheModel() throws {
        let sut = CreateAlarmViewController(viewModel: makeViewModel(context: .scale(usdScale)))
        sut.loadViewIfNeeded()
        let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        let cell = sut.makePenaltyCell(sut.tableView, at: indexPath)
        let field = try XCTUnwrap(descendants(in: cell).compactMap { $0 as? UITextField }.first)
        XCTAssertTrue(isHidden(field, in: cell), "no free entry outside roubles")
        assertRoublePresetsHidden(in: cell)
        let chips = tierChips(in: cell)
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(
            chips.map { $0.title(for: .normal) },
            sut.viewModel.tierPrices.map { MoneyFormatter.string($0.amount, currency: usd) }
        )
        XCTAssertTrue(chips.allSatisfy(\.isEnabled))
        XCTAssertTrue(chips[0].accessibilityTraits.contains(.selected))
        chips[1].sendActions(for: .touchUpInside)
        XCTAssertEqual(sut.viewModel.selectedTier, .mid)
        XCTAssertTrue(chips[1].accessibilityTraits.contains(.selected))
        XCTAssertFalse(chips[0].accessibilityTraits.contains(.selected))
    }

    func testEditorCardDisablesChipsWhenUnavailable() throws {
        let sut = CreateAlarmViewController(viewModel: makeViewModel(context: .unavailable(usd)))
        sut.loadViewIfNeeded()
        let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        let cell = sut.makePenaltyCell(sut.tableView, at: indexPath)
        let field = try XCTUnwrap(descendants(in: cell).compactMap { $0 as? UITextField }.first)
        XCTAssertTrue(isHidden(field, in: cell), "no free entry while the scale is unknown")
        assertRoublePresetsHidden(in: cell)
        let chips = tierChips(in: cell)
        XCTAssertEqual(chips.map { $0.title(for: .normal) }, ["—", "—", "—"])
        XCTAssertTrue(chips.allSatisfy { !$0.isEnabled })
    }

    func testRoubleCardCarriesNoTierChips() {
        let sut = CreateAlarmViewController(viewModel: makeViewModel(context: .scale(.rouble)))
        sut.loadViewIfNeeded()
        let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        let cell = sut.makePenaltyCell(sut.tableView, at: indexPath)
        XCTAssertTrue(tierChips(in: cell).isEmpty)
        let presets = descendants(in: cell).compactMap { $0 as? UIButton }
        XCTAssertEqual(presets.count, PenaltyCell.presets.count)
        XCTAssertTrue(presets.allSatisfy { !isHidden($0, in: cell) }, "the hidden-preset check is not vacuous")
    }

    // MARK: - Progressive card, mounted

    func testMountedProgressiveCardFollowsTheTierInTheContextCurrency() throws {
        let (sut, window) = mount(context: .scale(usdScale))
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertEqual(sut.viewModel.walletCurrency, .rub, "pristine wallet: wallet units are still roubles")
        let label = try progressiveLabel(in: sut)
        XCTAssertFalse(label.text?.contains("₽") == true, label.text ?? "")
        let low = try XCTUnwrap(MoneyFormatter.quotedDigits(0.99, currency: usd))
        XCTAssertTrue(label.text?.hasPrefix(low) == true, label.text ?? "")

        let penalty = try XCTUnwrap(sut.tableView.cellForRow(
            at: IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        ))
        tierChips(in: penalty)[2].sendActions(for: .touchUpInside)
        let high = try XCTUnwrap(MoneyFormatter.quotedDigits(2.99, currency: usd))
        let refreshed = try progressiveLabel(in: sut)
        XCTAssertTrue(refreshed.text?.hasPrefix(high) == true, refreshed.text ?? "")
        XCTAssertFalse(refreshed.text?.contains("₽") == true)
    }

    func testMountedProgressiveCardShowsDashesWhenUnavailable() throws {
        let (sut, window) = mount(context: .unavailable(usd))
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertEqual(try progressiveLabel(in: sut).text, "— → — → — → —")
    }

    // MARK: - Helpers

    /// A window tall enough that the price card and the progressive card are
    /// both on screen, so a tap must refresh the mounted progressive card.
    private func mount(context: SnoozePriceContext) -> (CreateAlarmViewController, UIWindow) {
        let sut = CreateAlarmViewController(viewModel: makeViewModel(context: context))
        sut.viewModel.progressiveScale = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 3000))
        window.rootViewController = sut
        window.isHidden = false
        window.layoutIfNeeded()
        sut.tableView.layoutIfNeeded()
        return (sut, window)
    }

    private func progressiveLabel(in sut: CreateAlarmViewController) throws -> UILabel {
        let cell = try XCTUnwrap(sut.tableView.cellForRow(
            at: IndexPath(row: 0, section: CreateAlarmViewController.Section.progressiveScale.rawValue)
        ) as? ProgressiveScaleCell)
        return try XCTUnwrap(descendants(in: cell).compactMap { $0 as? UILabel }
            .first { $0.attributedText?.string.contains(" → ") == true })
    }

    /// Every button that is not a tier chip (the 20…500 presets) and the
    /// «Минимум» helper are hidden in tier mode.
    private func assertRoublePresetsHidden(in cell: UIView, line: UInt = #line) {
        let others = descendants(in: cell).compactMap { $0 as? UIButton }
            .filter { $0.accessibilityIdentifier?.hasPrefix("createAlarm.penaltyTier.") != true }
        XCTAssertEqual(others.count, PenaltyCell.presets.count, line: line)
        XCTAssertTrue(others.allSatisfy { isHidden($0, in: cell) }, "rouble presets leak into tier mode", line: line)
        let helper = descendants(in: cell).compactMap { $0 as? UILabel }
            .first { $0.text == Localized.text("create_alarm.penalty.minimum") }
        XCTAssertNotNil(helper, line: line)
        XCTAssertTrue(helper.map { isHidden($0, in: cell) } ?? false, "helper hidden", line: line)
    }

    private func assertChain(_ chain: [Double], _ expected: [Double], line: UInt = #line) {
        XCTAssertEqual(chain.count, expected.count, line: line)
        for (value, want) in zip(chain, expected) {
            XCTAssertEqual(value, want, accuracy: 1e-9, line: line)
        }
    }

    private func tierChips(in view: UIView) -> [UIButton] {
        descendants(in: view).compactMap { $0 as? UIButton }
            .filter { $0.accessibilityIdentifier?.hasPrefix("createAlarm.penaltyTier.") == true }
    }

    private func isHidden(_ view: UIView, in root: UIView) -> Bool {
        var current: UIView? = view
        while let node = current, node !== root {
            if node.isHidden { return true }
            current = node.superview
        }
        return false
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
