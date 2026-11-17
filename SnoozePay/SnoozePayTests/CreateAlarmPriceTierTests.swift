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

    private func makeViewModel(alarm: Alarm? = nil, context: SnoozePriceContext) -> CreateAlarmViewModel {
        if let alarm { XCTAssertTrue(repository.save(alarm)) }
        return CreateAlarmViewModel(
            alarm: alarm,
            repository: repository,
            defaults: AlarmDefaults(defaults: defaults),
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

    func testDefaultContextIsRoubles() {
        let model = CreateAlarmViewModel(
            repository: repository,
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
        )
        XCTAssertEqual(model.priceContext, .scale(.rouble))
        XCTAssertTrue(model.offersAmountEntry)
    }

    // MARK: - USD scale

    func testUSDScaleOffersThreeTierPricesAndNoAmountEntry() {
        let model = makeViewModel(context: .scale(usdScale))
        XCTAssertFalse(model.offersAmountEntry)
        XCTAssertEqual(model.priceCurrency, usd)
        XCTAssertEqual(model.tierPrices.map(\.amount), ["0.99", "1.99", "2.99"].map { Decimal(string: $0)! })
        XCTAssertTrue(model.tierPrices.allSatisfy { $0.currency == usd })
        XCTAssertEqual(
            model.tierPrices.map { MoneyFormatter.string($0.amount, currency: usd, locale: Locale(identifier: "en_US")) },
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

    func testEditorCardDisablesChipsWhenUnavailable() {
        let sut = CreateAlarmViewController(viewModel: makeViewModel(context: .unavailable(usd)))
        sut.loadViewIfNeeded()
        let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        let chips = tierChips(in: sut.makePenaltyCell(sut.tableView, at: indexPath))
        XCTAssertEqual(chips.map { $0.title(for: .normal) }, ["—", "—", "—"])
        XCTAssertTrue(chips.allSatisfy { !$0.isEnabled })
    }

    func testRoubleCardCarriesNoTierChips() {
        let sut = CreateAlarmViewController(viewModel: makeViewModel(context: .scale(.rouble)))
        sut.loadViewIfNeeded()
        let indexPath = IndexPath(row: 0, section: CreateAlarmViewController.Section.penalty.rawValue)
        XCTAssertTrue(tierChips(in: sut.makePenaltyCell(sut.tableView, at: indexPath)).isEmpty)
    }

    // MARK: - Helpers

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
