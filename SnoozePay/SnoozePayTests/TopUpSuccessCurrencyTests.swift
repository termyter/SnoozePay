import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class TopUpSuccessCurrencyTests: XCTestCase {
    func testBothRealSuccessLabelsUseCreditedFractionAndWalletCurrencyInsteadOfSkuOrTotal() throws {
        for firing in [false, true] {
            for (code, symbol) in [("USD", "$"), ("EUR", "€"), ("RUB", "₽")] {
                let fixture = try Fixture()
                defer { fixture.clear() }
                let currency = try XCTUnwrap(Currency(code: code))
                XCTAssertEqual(fixture.balance.topUpFromPurchase(amount: 10, currency: currency), .credited)
                let sheet = fixture.makeSheet(firing: firing)
                sheet.loadViewIfNeeded()
                let tiles = descendants(in: sheet.view).compactMap { view -> UIControl? in
                    firing ? view as? FiringTopUpPresetRow : view as? SPAmountPreset
                }
                try XCTUnwrap(tiles.last).sendActions(for: .touchUpInside)
                try purchaseButton(in: sheet).sendActions(for: .touchUpInside)
                XCTAssertTrue(try XCTUnwrap(fixture.requested.last).hasSuffix(".999"))
                XCTAssertEqual(fixture.balance.topUpFromPurchase(amount: 0.49, currency: currency), .credited)
                let stored = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
                fixture.postSuccess(0.49)
                let label = try successLabel(in: sheet)
                let text = label.attributedText?.string ?? label.text ?? ""
                XCTAssertTrue(text.hasPrefix("+0,49"), text)
                XCTAssertTrue(text.contains(symbol), text)
                if code == "RUB" {
                    XCTAssertEqual(text, "+0,49\u{202F}₽")
                } else {
                    XCTAssertFalse(text.contains("₽"), text)
                }
                XCTAssertEqual(label.font, firing ? AppTypography.moneyXl : AppTypography.moneyLg)
                XCTAssertEqual(fixture.delays, [2])
                // A second delivery must not replace the receipt or restart dismissal.
                fixture.postSuccess(999.0)
                XCTAssertEqual(label.attributedText?.string ?? label.text, text)
                XCTAssertEqual(fixture.delays, [2])
                XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, stored)
            }
        }
    }

    func testMalformedEventsCannotInventSuccessAndCancellationPendingAndValidRetryStillWork() throws {
        for firing in [false, true] {
            let fixture = try Fixture()
            defer { fixture.clear() }
            let sheet = fixture.makeSheet(firing: firing)
            sheet.loadViewIfNeeded()
            let button = try purchaseButton(in: sheet)
            button.sendActions(for: .touchUpInside)
            let stored = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
            let malformed: [Any?] = [nil, "0.49", true, Double.nan, Double.infinity, -Double.infinity, 0.0, -1.0]
            for value in malformed {
                fixture.postSuccess(value)
                let label = try successLabel(in: sheet)
                XCTAssertNil(label.attributedText?.string ?? label.text)
                XCTAssertTrue(fixture.delays.isEmpty)
                XCTAssertFalse(button.isEnabled, "Malformed completion must not become cancellation")
                XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, stored)
            }
            fixture.center.post(name: StoreKitService.purchaseCancelledNotification, object: nil)
            XCTAssertTrue(button.isEnabled)
            button.sendActions(for: .touchUpInside)
            fixture.center.post(name: StoreKitService.purchasePendingNotification, object: nil)
            XCTAssertFalse(button.isEnabled)
            let usd = try XCTUnwrap(Currency(code: "USD"))
            XCTAssertEqual(fixture.balance.topUpFromPurchase(amount: 0.49, currency: usd), .credited)
            fixture.postSuccess(0.49)
            XCTAssertEqual(fixture.delays, [2])
            let label = try successLabel(in: sheet)
            XCTAssertTrue((label.attributedText?.string ?? label.text ?? "").contains("$"))
        }
    }

    func testInjectedCenterObserversDoNotKeepEitherSheetAlive() throws {
        for firing in [false, true] {
            let fixture = try Fixture()
            defer { fixture.clear() }
            weak var released: UIViewController?
            autoreleasepool {
                let sheet = fixture.makeSheet(firing: firing)
                sheet.loadViewIfNeeded()
                released = sheet
            }
            XCTAssertNil(released)
            fixture.postSuccess(0.49)
            XCTAssertTrue(fixture.delays.isEmpty)
        }
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }

    private func successLabel(in sheet: UIViewController) throws -> UILabel {
        try XCTUnwrap(descendants(in: sheet.view).compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == "deposit.successAmount"
                || $0.accessibilityIdentifier == "firingTopUp.successAmount"
        })
    }

    private func purchaseButton(in sheet: UIViewController) throws -> SPButton {
        try XCTUnwrap(descendants(in: sheet.view).compactMap { $0 as? SPButton }.first {
            $0.accessibilityIdentifier == "deposit.purchaseButton"
                || $0.accessibilityIdentifier == "firingTopUp.purchaseButton"
        })
    }

    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let center: NotificationCenter
        let balance: BalanceService
        var delays: [TimeInterval] = []
        var requested: [String] = []

        init() throws {
            let suite = "TopUpSuccessCurrencyTests.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let center = NotificationCenter()
            self.suite = suite
            self.defaults = defaults
            self.center = center
            self.balance = BalanceService(defaults: defaults, notificationCenter: center)
        }

        func clear() { defaults.removePersistentDomain(forName: suite) }

        func makeSheet(firing: Bool) -> UIViewController {
            let schedule: TopUpSuccessDismissal = { [weak self] delay, _ in self?.delays.append(delay) }
            let purchase: (String) -> Void = { [weak self] in self?.requested.append($0) }
            if firing {
                return FiringTopUpBottomSheetViewController(
                    currentBalance: balance.balance, balance: balance, notificationCenter: center,
                    scheduleSuccessDismissal: schedule, purchaseProduct: purchase
                )
            }
            return DepositBottomSheetViewController(
                balance: balance, notificationCenter: center,
                scheduleSuccessDismissal: schedule, purchaseProduct: purchase
            )
        }

        func postSuccess(_ amount: Any?) {
            center.post(name: StoreKitService.purchaseCompletedNotification, object: nil,
                        userInfo: amount.map { [StoreKitService.amountUserInfoKey: $0] })
        }
    }
}
