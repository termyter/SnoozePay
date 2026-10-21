import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmFiringPricePresentationTests: XCTestCase {
    func testInitialLargeProgressiveHintIsSafeBeforeAnyPaymentWithZeroWallet() {
        let cases: [(Double, String)] = [
            (4_611_686_018_427_387_904, "9223372036854775808"),
            (9_223_372_036_854_775_808, "18446744073709551616")
        ]
        for (base, nextDigits) in cases {
            let viewModel = makeViewModel(base: base)
            XCTAssertEqual(viewModel.balance, 0)
            XCTAssertFalse(viewModel.canSnooze)
            let controller = AlarmFiringViewController(viewModel: viewModel)
            let expected = MoneyFormatter.string(Decimal(string: nextDigits)!)
            XCTAssertEqual(controller.snoozeHintText(), Localized.format("firing.hint.next_price", expected))
            XCTAssertEqual(viewModel.snoozeCount, 0, "The hint is computed before a payment")
        }
    }

    func testActualNextHintQuotesWalletCurrencyAndFractionalPrice() throws {
        for (code, symbol) in [("USD", "$"), ("EUR", "€"), ("RUB", "₽")] {
            let currency = Currency(code: code)!
            let model = makeViewModel(base: 0.49, currency: currency)
            let hint = try XCTUnwrap(AlarmFiringViewController(viewModel: model).snoozeHintText())
            XCTAssertTrue(hint.contains("0,98"))
            XCTAssertTrue(hint.contains(symbol))
            if currency != .rub { XCTAssertFalse(hint.contains("₽")) }
            XCTAssertEqual(model.snoozeCount, 0)
            XCTAssertEqual(model.balance, 0)
        }
        let model = makeViewModel(base: 0.001, currency: Currency(code: "KWD")!)
        let hint = try XCTUnwrap(AlarmFiringViewController(viewModel: model).snoozeHintText())
        XCTAssertTrue(hint.contains("0,002"), "Preserve the currency's third fractional digit")
    }

    func testActualNextHintOmitsPositivePricesBelowCurrencyDisplayPrecision() {
        for (code, base) in [("USD", 0.001), ("JPY", 0.1)] {
            let currency = Currency(code: code)!
            let model = makeViewModel(base: base, currency: currency)
            XCTAssertNil(AlarmFiringViewController(viewModel: model).snoozeHintText())
            XCTAssertNotNil(AlarmFiringViewController.quotedPriceText(0, currency: currency),
                            "A genuine free price is different from a positive price displayed as zero")
            XCTAssertEqual(model.alarm.penalty(forSnoozeCount: 2), base * 2)
        }
    }

    func testQuotedPricePreservesHugeFiniteCurrencyAndRejectsInvalidOrLossySubunits() throws {
        let currency = Currency(code: "USD")!
        let digits = try XCTUnwrap(AlarmFiringViewController.roundedPriceText(
            .greatestFiniteMagnitude, withCurrency: false
        ))
        XCTAssertEqual(AlarmFiringViewController.quotedPriceText(.greatestFiniteMagnitude, currency: currency),
                       digits + MoneyFormatter.narrowSpace + "USD")
        for invalid in [Double.nan, .infinity, -.infinity, -1, .leastNonzeroMagnitude] {
            XCTAssertNil(AlarmFiringViewController.quotedPriceText(invalid, currency: currency))
        }
    }

    func testRoundedPriceTextPreservesOrdinaryCurrencyFormattingAndKnownLargeDigits() {
        XCTAssertEqual(AlarmFiringViewController.roundedPriceText(1234.5), MoneyFormatter.string(1235))
        XCTAssertEqual(AlarmFiringViewController.roundedPriceText(9_223_372_036_854_775_808, withCurrency: false),
                       "9223372036854775808")
        XCTAssertEqual(AlarmFiringViewController.roundedPriceText(18_446_744_073_709_551_616, withCurrency: false),
                       "18446744073709551616")
    }

    func testNonfinitePriceIsNotQuotedAndFiniteDecimalOverflowStillHasDigits() throws {
        let controller = AlarmFiringViewController(viewModel: makeViewModel(base: .greatestFiniteMagnitude))
        XCTAssertNil(controller.snoozeHintText(), "Do not quote a finite charge when multiplication overflowed")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertNil(AlarmFiringViewController.roundedPriceText(invalid))
        }
        let digits = try XCTUnwrap(AlarmFiringViewController.roundedPriceText(
            .greatestFiniteMagnitude, withCurrency: false
        ))
        XCTAssertEqual(digits.count, 309)
        XCTAssertTrue(digits.hasPrefix("17976931348623157"))
        XCTAssertTrue(digits.utf8.allSatisfy { (48...57).contains($0) })
        XCTAssertEqual(AlarmFiringViewController.roundedPriceText(.greatestFiniteMagnitude),
                       digits + MoneyFormatter.narrowSpace + "₽")
    }

    func testLadderKeepsLargeAmountsAndStatesAndRendersActualDigits() {
        let viewModel = makeViewModel(base: 4_611_686_018_427_387_904, snoozeCount: 1)
        XCTAssertEqual(viewModel.ladderSteps.map(\.amount), [
            4_611_686_018_427_387_904, 9_223_372_036_854_775_808,
            18_446_744_073_709_551_616, 36_893_488_147_419_103_232
        ])
        XCTAssertEqual(viewModel.ladderSteps.map(\.state), [.done, .current, .future, .future])
        let labels = ladderLabels(for: viewModel)
        XCTAssertEqual(labels.map { $0.filter(\.isNumber) }, [
            "4611686018427387904", "9223372036854775808", "18446744073709551616", "36893488147419103232"
        ])
        XCTAssertTrue(labels.allSatisfy { $0.hasSuffix(MoneyFormatter.narrowSpace + "₽") })
    }

    func testLadderMultiplicationOverflowShowsUnavailableWithoutChangingIndexing() {
        let viewModel = makeViewModel(base: .greatestFiniteMagnitude, snoozeCount: 6)
        XCTAssertEqual(viewModel.ladderSteps.first?.amount, Double.greatestFiniteMagnitude)
        XCTAssertTrue(viewModel.ladderSteps.dropFirst().allSatisfy { $0.amount == .infinity })
        XCTAssertEqual(viewModel.ladderSteps.map(\.state), [.done, .done, .done, .current])
        let rendered = ladderLabels(for: viewModel)
        XCTAssertEqual(rendered.first?.filter(\.isNumber).count, 309)
        XCTAssertTrue(rendered.first?.hasSuffix(MoneyFormatter.narrowSpace + "₽") == true)
        XCTAssertEqual(Array(rendered.dropFirst()), ["—", "—", "—"])
    }

    func testActualLadderLabelsPreserveEngineFractionsAndWalletCurrency() {
        for code in ["RUB", "USD", "EUR", "KWD"] {
            let currency = Currency(code: code)!
            let base = code == "KWD" ? 0.001 : 0.49
            let expected: [Double] = code == "KWD" ? [0.001, 0.002, 0.004, 0.008] : [0.49, 0.98, 1.96, 3.92]
            let model = makeViewModel(base: base, snoozeCount: 2, currency: currency)
            XCTAssertEqual(model.ladderSteps.map(\.amount), expected)
            XCTAssertEqual(model.ladderSteps.map(\.amount), (1...4).map { model.alarm.penalty(forSnoozeCount: $0) })
            XCTAssertEqual(model.ladderSteps.map(\.state), [.done, .done, .current, .future])
            let rendered = ladderLabels(for: model)
            XCTAssertEqual(rendered, expected.map { MoneyFormatter.string($0, currency: currency) })
            if currency != .rub { XCTAssertTrue(rendered.allSatisfy { !$0.contains("₽") }) }
            XCTAssertEqual(model.alarm.penaltyAmount, base)
            XCTAssertEqual(model.snoozeCount, 2)
            XCTAssertEqual(model.balance, 0)
        }
    }

    func testLadderPositiveUnderflowIsUnknownWhileRealZeroRemainsZero() {
        for (code, base) in [("RUB", 0.001), ("USD", 0.001), ("EUR", 0.001), ("JPY", 0.1)] {
            let currency = Currency(code: code)!
            let model = makeViewModel(base: base, currency: currency)
            let rendered = ladderLabels(for: model)
            XCTAssertEqual(Array(rendered.prefix(3)), ["—", "—", "—"])
            XCTAssertEqual(rendered.last, MoneyFormatter.string(base * 8, currency: currency))
            XCTAssertEqual(model.ladderSteps.map(\.amount), [base, base * 2, base * 4, base * 8])
            XCTAssertEqual(ladderLabels(for: makeViewModel(base: 0, currency: currency)),
                           Array(repeating: MoneyFormatter.string(0.0, currency: currency), count: 4))
        }
    }

    func testLadderRebuildSnapshotsChangedWalletCurrencyOnceAndReplacesOldColumns() {
        let wallet = EmptyWallet(currency: .rub)
        let model = AlarmFiringViewModel(alarm: Alarm(penaltyAmount: 0.49, progressiveScale: true),
                                        snoozeCount: 1, balanceService: wallet)
        let controller = AlarmFiringViewController(viewModel: model)
        let ladder = controller.makeLadderStack()
        controller.snoozedLadderStack = ladder
        for code in ["RUB", "USD", "EUR", "RUB"] {
            wallet.currency = Currency(code: code)!
            let oldColumns = ladder.arrangedSubviews
            let reads = wallet.currencyReads
            controller.rebuildLadder()
            XCTAssertEqual(wallet.currencyReads, reads + 1)
            XCTAssertEqual(ladder.arrangedSubviews.count, 4)
            XCTAssertTrue(oldColumns.allSatisfy { $0.superview == nil })
            XCTAssertEqual(amountLabels(in: ladder).compactMap(\.text), [0.49, 0.98, 1.96, 3.92].map {
                MoneyFormatter.string($0, currency: wallet.currency)
            })
            XCTAssertEqual(model.snoozeCount, 1)
            XCTAssertEqual(model.ladderSteps.map(\.state), [.done, .current, .future, .future])
        }
    }

    func testLadderKeepsFourStepsAndExistingAttemptStateClampAndNonprogressiveHiding() {
        let scenarios: [(Int, [AlarmFiringViewModel.LadderStepState])] = [
            (0, [.current, .future, .future, .future]), (1, [.done, .current, .future, .future]),
            (2, [.done, .done, .current, .future]), (3, [.done, .done, .done, .current]),
            (6, [.done, .done, .done, .current])
        ]
        for (count, states) in scenarios {
            let model = makeViewModel(base: 0.49, snoozeCount: count, currency: Currency(code: "USD")!)
            XCTAssertEqual(model.ladderSteps.map(\.amount), [0.49, 0.98, 1.96, 3.92])
            XCTAssertEqual(model.ladderSteps.map(\.state), states)
            XCTAssertEqual(ladderLabels(for: model).count, 4)
            XCTAssertEqual(model.snoozeCount, count)
        }
        let model = makeViewModel(base: 0.49, snoozeCount: 2, progressive: false)
        XCTAssertTrue(model.ladderSteps.isEmpty)
        XCTAssertTrue(ladderLabels(for: model).isEmpty)
        XCTAssertEqual(model.snoozeCount, 2)
    }

    func testOrdinaryCurrencyFractionLabelsFitTheActualLadderAt390Points() {
        for code in ["RUB", "USD", "EUR", "KWD"] {
            let currency = Currency(code: code)!
            let model = makeViewModel(base: code == "KWD" ? 0.001 : 0.49, currency: currency)
            let controller = AlarmFiringViewController(viewModel: model)
            let ladder = controller.makeLadderStack()
            controller.snoozedLadderStack = ladder
            controller.rebuildLadder()
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
            host.addSubview(ladder)
            NSLayoutConstraint.activate([
                ladder.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
                ladder.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
                ladder.topAnchor.constraint(equalTo: host.topAnchor, constant: 20)
            ])
            host.layoutIfNeeded()
            let labels = amountLabels(in: ladder)
            XCTAssertEqual(labels.count, 4)
            for label in labels {
                XCTAssertGreaterThan(label.bounds.width, 0)
                XCTAssertLessThanOrEqual(label.intrinsicContentSize.width, label.bounds.width + 0.5)
                let frame = label.convert(label.bounds, to: host)
                XCTAssertGreaterThanOrEqual(frame.minX, 19.5)
                XCTAssertLessThanOrEqual(frame.maxX, 370.5)
            }
        }
    }

    #if DEBUG
    func testProgressiveTourPenaltyIsFiniteAndDoesNotChangeTheDefault() {
        XCTAssertEqual(UITourRoutes.progressiveFiringPenalty(arguments: []), 50)
        for invalid in ["nan", "inf", "0", "-1", "invalid"] {
            XCTAssertEqual(UITourRoutes.progressiveFiringPenalty(arguments: ["-uitour-penalty", invalid]), 50)
        }
        XCTAssertEqual(UITourRoutes.progressiveFiringPenalty(arguments: ["-uitour-penalty", "4611686018427387904"]),
                       4_611_686_018_427_387_904)
    }
    #endif

    private func makeViewModel(
        base: Double, snoozeCount: Int = 0, currency: Currency = .rub, progressive: Bool = true
    ) -> AlarmFiringViewModel {
        AlarmFiringViewModel(alarm: Alarm(penaltyAmount: base, progressiveScale: progressive),
                            snoozeCount: snoozeCount, balanceService: EmptyWallet(currency: currency))
    }

    private func ladderLabels(for viewModel: AlarmFiringViewModel) -> [String] {
        let controller = AlarmFiringViewController(viewModel: viewModel)
        let ladder = controller.makeLadderStack()
        controller.snoozedLadderStack = ladder
        controller.rebuildLadder()
        return amountLabels(in: ladder).compactMap(\.text)
    }

    private func amountLabels(in ladder: UIStackView) -> [UILabel] {
        ladder.arrangedSubviews.compactMap { ($0 as? UIStackView)?.arrangedSubviews.first as? UILabel }
    }

    private final class EmptyWallet: AlarmFiringBalancing {
        func acceptsPurchase(in currency: Currency) -> Bool { false }
        var currency: Currency
        private(set) var currencyReads = 0
        var walletCurrency: Currency { currencyReads += 1; return currency }
        init(currency: Currency) { self.currency = currency }
        let balance: Double = 0
        func canAfford(_ amount: Double) -> Bool { false }
        func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? { nil }
        func refund(amount: Double, refundsTransactionID: UUID?) -> Bool { false }
    }
}
