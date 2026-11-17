import XCTest
@testable import SnoozePay

/// Example amounts on onboarding and the alarm-off sheet follow the price
/// context (#1109): roubles render exactly as before, a storefront scale quotes
/// multiples of its tiers in its own currency, and an unavailable scale shows
/// no number at all. Every context is injected — nothing here reads the host
/// app's wallet, whose cached storefront scale may well be USD.
final class ExampleMoneyCopyTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private var usdContext: SnoozePriceContext {
        .scale(SnoozePriceScale(currency: usd, tiers: [Decimal(string: "0.99")!, Decimal(string: "1.99")!, 3])!)
    }
    private var unavailable: SnoozePriceContext { .unavailable(usd) }
    private let rouble = SnoozePriceContext.scale(.rouble)
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func usdText(_ amount: String) -> String {
        MoneyFormatter.string(Decimal(string: amount)!, currency: usd)
    }

    // MARK: - Helper

    func testRoubleContextKeepsTheLegacyLiteral() {
        XCTAssertEqual(ExampleMoneyCopy.string(roubles: 50, tier: .low, in: rouble), MoneyFormatter.string(50))
        XCTAssertEqual(ExampleMoneyCopy.string(roubles: 20, tier: .low, in: rouble), MoneyFormatter.string(20))
        XCTAssertEqual(
            ExampleMoneyCopy.string(roubles: 500, tier: .low, times: 10, in: rouble), MoneyFormatter.string(500)
        )
    }

    func testStorefrontScaleQuotesTierMultiplesInItsCurrency() throws {
        XCTAssertEqual(ExampleMoneyCopy.string(roubles: 50, tier: .low, in: usdContext), usdText("0.99"))
        XCTAssertEqual(ExampleMoneyCopy.string(roubles: 50, tier: .mid, in: usdContext), usdText("1.99"))
        let five = try XCTUnwrap(ExampleMoneyCopy.money(roubles: 250, tier: .low, times: 5, in: usdContext))
        XCTAssertEqual(five, Money(Decimal(string: "4.95")!, currency: usd))
        XCTAssertFalse(usdText("4.95").contains("₽"))
    }

    func testUnavailableScaleHasNoNumber() {
        XCTAssertNil(ExampleMoneyCopy.money(roubles: 50, tier: .low, in: unavailable))
        XCTAssertNil(ExampleMoneyCopy.string(roubles: 500, tier: .low, times: 10, in: unavailable))
    }

    // MARK: - Onboarding

    func testOnboardingDepositPresetsPerContext() {
        let roubles = OnboardingViewController.depositOptions(in: rouble)
        XCTAssertEqual(roubles.map(\.amount), [250, 500, 1000])
        XCTAssertEqual(roubles.map(\.money?.currency), [.rub, .rub, .rub])
        XCTAssertEqual(
            roubles[0].description, Localized.format("onboarding.page3.option1_body", MoneyFormatter.string(50))
        )

        let dollars = OnboardingViewController.depositOptions(in: usdContext)
        XCTAssertEqual(dollars.map(\.amount), ["4.95", "9.9", "19.8"].map { Decimal(string: $0) })
        XCTAssertEqual(dollars.map(\.money?.currency), [usd, usd, usd])
        XCTAssertEqual(dollars[0].description, Localized.format("onboarding.page3.option1_body", usdText("0.99")))

        let none = OnboardingViewController.depositOptions(in: unavailable)
        XCTAssertEqual(none.map(\.amount), [nil, nil, nil])
        XCTAssertEqual(none[0].description, Localized.text("onboarding.page3.option1_body_unpriced"))
    }

    func testOnboardingRendersRoublesExactlyAsBefore() {
        let controller = mount(OnboardingViewController(priceContextSource: { .scale(.rouble) }))
        let rendered = controller.pageViews.flatMap(strings(in:))
        for expected in [
            "−\(MoneyFormatter.string(50))",
            Localized.format("onboarding.page2.step1_title", MoneyFormatter.string(500)),
            Localized.format("onboarding.page2.step2_title", MoneyFormatter.string(50)),
            MoneyFormatter.attributed(Decimal(500), digitsFont: AppTypography.moneyMd).string
        ] {
            XCTAssertTrue(rendered.contains(expected), "«\(expected)» missing: \(rendered)")
        }
        controller.rebuildDepositCTA()
        XCTAssertEqual(controller.primaryButton.accessibilityLabel?.hasSuffix(MoneyFormatter.string(500)), true)
    }

    func testOnboardingQuotesTheStorefrontScaleWithoutRoubles() {
        let context = usdContext
        let controller = mount(OnboardingViewController(priceContextSource: { context }))
        let rendered = controller.pageViews.flatMap(strings(in:))
        XCTAssertFalse(rendered.contains { $0.contains("₽") }, "rouble sign on a USD onboarding: \(rendered)")
        for expected in [
            "−\(usdText("0.99"))",
            Localized.format("onboarding.page2.step1_title", usdText("9.9")),
            Localized.format("onboarding.page2.step2_title", usdText("0.99")),
            usdText("19.8")
        ] {
            XCTAssertTrue(rendered.contains(expected), "«\(expected)» missing: \(rendered)")
        }
        controller.rebuildDepositCTA()
        XCTAssertEqual(controller.primaryButton.accessibilityLabel?.hasSuffix(usdText("9.9")), true)
    }

    func testOnboardingWithoutAScaleInventsNoNumber() {
        let context = unavailable
        let controller = mount(OnboardingViewController(priceContextSource: { context }))
        let rendered = controller.pageViews.flatMap(strings(in:))
        XCTAssertFalse(rendered.contains { $0.contains("₽") || $0.contains("$") }, "\(rendered)")
        XCTAssertTrue(rendered.contains(Localized.text("onboarding.page2.step1_title_unpriced")))
        XCTAssertTrue(rendered.contains(Localized.text("onboarding.page2.step2_title_unpriced")))
        let pill = controller.pageViews[0].allSubviews.compactMap { $0 as? OnboardingPenaltyPill }.first
        XCTAssertEqual(pill?.isHidden, true, "the −price pill must not show a made-up number")
        controller.rebuildDepositCTA()
        XCTAssertEqual(controller.primaryButton.accessibilityLabel, Localized.text("onboarding.button.deposit"))
    }

    /// A first launch builds onboarding before the catalogue loads; the scale
    /// notification must re-quote the pages in the storefront currency.
    func testOnboardingSwitchesWhenTheScaleArrives() {
        let center = NotificationCenter()
        var context = rouble
        let controller = mount(OnboardingViewController(priceContextSource: { context }, notificationCenter: center))
        XCTAssertEqual(controller.depositOptions[1].money?.currency, .rub)

        context = usdContext
        center.post(name: SnoozePriceScaleStore.snoozePriceScaleChangedNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.depositOptions[1].money, Money(Decimal(string: "9.9")!, currency: usd))
        let rendered = controller.pageViews.flatMap(strings(in:))
        XCTAssertTrue(rendered.contains("−\(usdText("0.99"))"), "pages were not rebuilt: \(rendered)")
    }

    // MARK: - Alarm-off sheet

    func testAlarmOffLowerPriceSubtitlePerContext() {
        XCTAssertEqual(
            AlarmOffWarningViewController.lowerPriceSubtitle(in: rouble),
            Localized.format("alarm_off.lower_price.subtitle", MoneyFormatter.string(50), MoneyFormatter.string(20))
        )
        XCTAssertEqual(
            AlarmOffWarningViewController.lowerPriceSubtitle(in: usdContext),
            Localized.format("alarm_off.lower_price.subtitle", usdText("1.99"), usdText("0.99"))
        )
        XCTAssertEqual(
            AlarmOffWarningViewController.lowerPriceSubtitle(in: unavailable),
            Localized.text("alarm_off.lower_price.subtitle_unpriced")
        )
    }

    func testAlarmOffBodyPerContext() {
        let roubleBody = body(of: AlarmOffWarningViewController(priceContext: rouble))
        let legacy = MoneyFormatter.attributed(Decimal(750), digitsFont: AppFonts.mono(.bold, 17), prefix: "−")
        XCTAssertEqual(roubleBody, Localized.format("alarm_off.body", legacy.string))

        let usdBody = body(of: AlarmOffWarningViewController(priceContext: usdContext))
        XCTAssertEqual(usdBody, Localized.format("alarm_off.body", "−" + usdText("14.85")))
        XCTAssertFalse(usdBody?.contains("₽") ?? true)

        XCTAssertEqual(
            body(of: AlarmOffWarningViewController(priceContext: unavailable)),
            Localized.text("alarm_off.body_unpriced")
        )
    }

    // MARK: - Support

    private func body(of sheet: AlarmOffWarningViewController) -> String? {
        sheet.loadViewIfNeeded()
        let prefixes = [Localized.text("alarm_off.body_unpriced"), Localized.format("alarm_off.body", "\u{1}")]
            .map { String($0.prefix(8)) }
        return strings(in: sheet.view).first { text in prefixes.contains { text.hasPrefix($0) } }
    }

    private func mount<T: UIViewController>(_ controller: T) -> T {
        let host = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        host.rootViewController = controller
        host.isHidden = false
        window = host
        controller.loadViewIfNeeded()
        host.layoutIfNeeded()
        return controller
    }

    private func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
