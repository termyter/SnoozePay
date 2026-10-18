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
        XCTAssertEqual(ladderLabels(for: viewModel), [
            "4611686018427387904", "9223372036854775808", "18446744073709551616", "36893488147419103232"
        ])
    }

    func testLadderMultiplicationOverflowShowsUnavailableWithoutChangingIndexing() {
        let viewModel = makeViewModel(base: .greatestFiniteMagnitude, snoozeCount: 6)
        XCTAssertEqual(viewModel.ladderSteps.first?.amount, Double.greatestFiniteMagnitude)
        XCTAssertTrue(viewModel.ladderSteps.dropFirst().allSatisfy { $0.amount == .infinity })
        XCTAssertEqual(viewModel.ladderSteps.map(\.state), [.done, .done, .done, .current])
        XCTAssertEqual(Array(ladderLabels(for: viewModel).dropFirst()), ["—", "—", "—"])
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

    private func makeViewModel(base: Double, snoozeCount: Int = 0) -> AlarmFiringViewModel {
        AlarmFiringViewModel(alarm: Alarm(penaltyAmount: base, progressiveScale: true),
                            snoozeCount: snoozeCount, balanceService: EmptyWallet())
    }

    private func ladderLabels(for viewModel: AlarmFiringViewModel) -> [String] {
        let controller = AlarmFiringViewController(viewModel: viewModel)
        let ladder = controller.makeLadderStack()
        controller.snoozedLadderStack = ladder
        controller.rebuildLadder()
        return ladder.arrangedSubviews.compactMap {
            (($0 as? UIStackView)?.arrangedSubviews.first as? UILabel)?.text
        }
    }

    private final class EmptyWallet: AlarmFiringBalancing {
        let balance: Double = 0
        func canAfford(_ amount: Double) -> Bool { false }
        func chargeWithReceipt(amount: Double, alarmID: UUID?) -> Transaction? { nil }
        func refund(amount: Double, refundsTransactionID: UUID?) -> Bool { false }
    }
}
