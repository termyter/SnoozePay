import XCTest
@testable import SnoozePay

/// #1120: what one snooze costs for a tier or a legacy amount, in roubles, in a
/// storefront scale and when the scale is unavailable.
@MainActor
final class SnoozePriceResolverTests: XCTestCase {

    private let usd = Currency(code: "USD")!
    private lazy var usdScale = SnoozePriceScale(
        currency: usd, tiers: ["0.99", "1.99", "2.99"].map { Decimal(string: $0)! }
    )!

    private func money(_ text: String, _ currency: Currency) -> Money {
        Money(Decimal(string: text)!, currency: currency)!
    }

    /// Expected price for snooze counts 0…6 given the base, progressive on.
    private func ladder(_ base: String) -> [String] {
        let value = Decimal(string: base)!
        return [1, 1, 2, 4, 8, 8, 8].map { NSDecimalNumber(decimal: value * Decimal($0)).stringValue }
    }

    private struct Case<Price> {
        let price: Price, context: SnoozePriceContext, base: String?
        init(_ price: Price, _ context: SnoozePriceContext, _ base: String?) {
            (self.price, self.context, self.base) = (price, context, base)
        }
    }

    // MARK: - Tier × count × context

    func testTierResolvesAcrossContextsAndCounts() {
        let cases: [Case<SnoozePriceTier>] = [
            Case(.low, .scale(.rouble), "50"), Case(.mid, .scale(.rouble), "100"), Case(.high, .scale(.rouble), "200"),
            Case(.low, .scale(usdScale), "0.99"), Case(.mid, .scale(usdScale), "1.99"),
            Case(.high, .scale(usdScale), "2.99"),
            Case(.low, .unavailable(usd), nil), Case(.high, .unavailable(.rub), nil)
        ]
        for testCase in cases {
            let currency = testCase.context.currency
            for count in 0...6 {
                let label = "\(testCase.price) in \(testCase.context) at count \(count)"
                let progressive = SnoozePriceResolver.resolve(
                    .tier(testCase.price), snoozeCount: count, isProgressive: true, in: testCase.context
                )
                let flat = SnoozePriceResolver.resolve(
                    .tier(testCase.price), snoozeCount: count, isProgressive: false, in: testCase.context
                )
                guard let base = testCase.base else {
                    XCTAssertNil(progressive, label)
                    XCTAssertNil(flat, label)
                    continue
                }
                XCTAssertEqual(progressive, money(ladder(base)[count], currency), label)
                XCTAssertEqual(flat, money(base, currency), label)
            }
        }
    }

    func testProgressiveCentsAreExactInDecimal() {
        let expected = ["0.99", "0.99", "1.98", "3.96", "7.92", "7.92", "7.92"]
        for count in 0...6 {
            let price = SnoozePriceResolver.resolve(
                .tier(.low), snoozeCount: count, isProgressive: true, in: .scale(usdScale)
            )
            XCTAssertEqual(price?.amount, Decimal(string: expected[count]), "count \(count)")
            XCTAssertEqual(price.map { NSDecimalNumber(decimal: $0.amount).stringValue }, expected[count])
        }
    }

    /// The charging coordinator resolves off the main actor.
    func testResolvesOffTheMainActor() async {
        let scale = usdScale
        let price = await Task.detached {
            SnoozePriceResolver.resolve(.tier(.mid), snoozeCount: 3, isProgressive: true, in: .scale(scale))
        }.value
        XCTAssertEqual(price, money("7.96", usd))
    }

    // MARK: - Amount × count × context

    func testAmountResolvesAcrossContextsAndCounts() {
        let cases: [Case<Double>] = [
            Case(20, .scale(.rouble), "20"), Case(50, .scale(.rouble), "50"), Case(500, .scale(.rouble), "500"),
            Case(75.5, .scale(.rouble), "75.5"),
            Case(20, .scale(usdScale), "0.99"), Case(50, .scale(usdScale), "0.99"), Case(100, .scale(usdScale), "1.99"),
            Case(200, .scale(usdScale), "2.99"), Case(500, .scale(usdScale), "2.99"),
            Case(50, .unavailable(usd), nil), Case(50, .unavailable(.rub), nil)
        ]
        for testCase in cases {
            let currency = testCase.context.currency
            for count in 0...6 {
                let label = "\(testCase.price) in \(testCase.context) at count \(count)"
                let progressive = SnoozePriceResolver.resolve(
                    .amount(testCase.price), snoozeCount: count, isProgressive: true, in: testCase.context
                )
                let flat = SnoozePriceResolver.resolve(
                    .amount(testCase.price), snoozeCount: count, isProgressive: false, in: testCase.context
                )
                guard let base = testCase.base else {
                    XCTAssertNil(progressive, label)
                    XCTAssertNil(flat, label)
                    continue
                }
                XCTAssertEqual(progressive, money(ladder(base)[count], currency), label)
                XCTAssertEqual(flat, money(base, currency), label)
            }
        }
    }

    func testInvalidAmountResolvesToNil() {
        for amount in [-1, Double.nan, .infinity] {
            for context in [SnoozePriceContext.scale(.rouble), .scale(usdScale)] {
                XCTAssertNil(SnoozePriceResolver.resolve(
                    .amount(amount), snoozeCount: 1, isProgressive: true, in: context
                ), "\(amount) in \(context)")
            }
        }
    }

    // MARK: - Parity with today's rouble charge

    func testRoubleAmountMatchesAlarmPenalty() {
        for amount in [20.0, 50, 100, 200, 500] {
            for progressive in [false, true] {
                let alarm = Alarm(penaltyAmount: amount, progressiveScale: progressive)
                for count in 0...6 {
                    let resolved = SnoozePriceResolver.resolve(
                        .amount(amount), snoozeCount: count, isProgressive: progressive, in: .scale(.rouble)
                    )
                    let today = alarm.penalty(forSnoozeCount: count)
                    XCTAssertEqual(resolved?.currency, .rub)
                    XCTAssertEqual(resolved?.amount, MoneyFormatter.decimalForDisplay(today),
                                   "\(amount) progressive=\(progressive) count=\(count)")
                    XCTAssertEqual(resolved?.toDouble(), today)
                }
            }
        }
    }
}
