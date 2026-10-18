import UIKit
import XCTest
@testable import SnoozePay

final class StreakSavingsCurrencyTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() {
        for window in windows {
            window.isHidden = true
            window.rootViewController = nil
        }
        windows.removeAll()
        super.tearDown()
    }

    func testFractionsReachRealHeroBannerAndShareInTheirCurrency() throws {
        for (code, price, digits, symbol) in [("RUB", 0.49, "0,49", "₽"),
                                             ("USD", 0.49, "0,49", "$"),
                                             ("KWD", 0.001, "0,001", "KWD")] {
            let currency = try XCTUnwrap(Currency(code: code))
            let saved = try XCTUnwrap(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(
                cleanDays: 1, price: price
            ))
            XCTAssertEqual(saved, Decimal(string: String(price)))
            let modal = StreakModalViewController(streakDays: 1, savedAmount: saved, currency: currency)
            modal.loadViewIfNeeded()
            let banner = AlarmsStreakBannerView()
            banner.configure(streakDays: 1, savedAmount: saved, currency: currency)
            let share = StreakModalViewController.shareText(streakDays: 1, savedAmount: saved, currency: currency)
            let formatted = MoneyFormatter.string(saved, currency: currency)
            let hero = try XCTUnwrap(modal.amountLabel.text)
            let caption = try XCTUnwrap(labels(in: banner).first { ($0.text ?? "").hasPrefix("Сэкономили ") }?.text)

            XCTAssertEqual(hero, "+" + formatted)
            XCTAssertEqual(caption, Localized.format("alarms.streak.saved", formatted))
            XCTAssertEqual(share, Localized.format("streak.share.message", 1, "день", formatted))
            for rendered in [hero, caption, share] {
                XCTAssertTrue(rendered.contains(digits), rendered)
                XCTAssertTrue(rendered.contains(symbol), rendered)
                if currency != .rub { XCTAssertFalse(rendered.contains("₽"), rendered) }
            }
        }
    }

    func testBannerThemeReplayRetainsFractionAndCurrency() throws {
        for code in ["RUB", "USD", "KWD"] {
            let currency = try XCTUnwrap(Currency(code: code))
            let amount = try XCTUnwrap(Decimal(string: code == "KWD" ? "0.001" : "0.49"))
            let (banner, window) = hostedBanner()
            banner.configure(streakDays: 3, savedAmount: amount, currency: currency)
            let expected = Localized.format("alarms.streak.saved", MoneyFormatter.string(amount, currency: currency))
            for style in [UIUserInterfaceStyle.dark, .light, .dark] {
                window.overrideUserInterfaceStyle = style
                window.layoutIfNeeded()
                XCTAssertEqual(banner.traitCollection.userInterfaceStyle, style)
                let caption = try XCTUnwrap(labels(in: banner).first {
                    ($0.text ?? "").hasPrefix("Сэкономили ")
                })
                XCTAssertEqual(caption.text, expected)
            }
        }
    }

    func testUnavailableAndNonpositiveEstimatesCannotBecomeShareableClaims() {
        let invalid: [Double?] = [nil, 0, -1, .nan, .infinity, -.infinity]
        for price in invalid {
            let saved = StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 7, price: price)
            XCTAssertNil(saved)
            assertBehavioral(saved)
        }
        assertBehavioral(.nan)
        assertBehavioral(0)
        assertBehavioral(-1)
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 0, price: 0.49))
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: -1, price: 0.49))
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 7, alarms: []))
        XCTAssertNil(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(
            cleanDays: 7, alarms: [Alarm(penaltyAmount: 0, progressiveScale: false)]
        ))
    }

    func testExactLargeEstimateSurvivesWhileUnsupportedAndOverflowStayUnknown() throws {
        let exact: Double = 18_446_744_073_709_551_616
        let saved = try XCTUnwrap(StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 1, price: exact))
        XCTAssertEqual(saved, Decimal(string: "18446744073709551616"))
        let modal = StreakModalViewController(streakDays: 1, savedAmount: saved, currency: .rub)
        modal.loadViewIfNeeded()
        XCTAssertEqual(modal.amountLabel.text?.filter(\.isNumber), "18446744073709551616")
        let tooPrecise: Double = 340_282_366_920_938_463_463_374_607_431_768_211_456
        for price in [tooPrecise, Double.greatestFiniteMagnitude, .leastNonzeroMagnitude] {
            let unsupported = StatisticsViewModel.SavingsEstimate.savedDisplayAmount(cleanDays: 1, price: price)
            XCTAssertNil(unsupported)
            assertBehavioral(unsupported)
        }
        let overflow = StatisticsViewModel.SavingsEstimate.savedDisplayAmount(
            cleanDays: Int.max, price: .greatestFiniteMagnitude
        )
        XCTAssertNil(overflow)
        assertBehavioral(overflow)
    }

    private func assertBehavioral(_ amount: Decimal?, file: StaticString = #filePath, line: UInt = #line) {
        let modal = StreakModalViewController(streakDays: 7, savedAmount: amount, currency: Currency(code: "USD")!)
        modal.loadViewIfNeeded()
        XCTAssertFalse(labels(in: modal.view).contains { $0 is SPGradientTextLabel }, file: file, line: line)
        XCTAssertFalse(controls(in: modal.view).contains {
            $0.accessibilityLabel == Localized.text("streak.button.share")
        }, file: file, line: line)
    }

    private func hostedBanner() -> (AlarmsStreakBannerView, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIViewController()
        let banner = AlarmsStreakBannerView(frame: CGRect(x: 0, y: 0, width: 393, height: 84))
        host.view.addSubview(banner)
        window.rootViewController = host
        window.isHidden = false
        windows.append(window)
        return (banner, window)
    }

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { subview in
            let own = (subview as? UILabel).map { [$0] } ?? []
            return own + labels(in: subview)
        }
    }

    private func controls(in view: UIView) -> [SPButton] {
        view.subviews.flatMap { subview in
            let own = (subview as? SPButton).map { [$0] } ?? []
            return own + controls(in: subview)
        }
    }
}
