import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class WalletHistoryCurrencyTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let russian = Locale(identifier: "ru_RU")

    private func currency(_ code: String) -> Currency {
        Currency(code: code)!
    }

    private func amount(_ value: String) -> Decimal {
        Decimal(string: value)!
    }

    func testExplicitCurrencyPreservesCentsAndCurrencySpecificMinorUnits() {
        XCTAssertEqual(MoneyFormatter.string(amount("0.49"), currency: currency("USD"), locale: english), "$0.49")
        XCTAssertEqual(MoneyFormatter.string(amount("0.49"), currency: currency("EUR"), locale: english), "€0.49")
        let yen = MoneyFormatter.string(amount("1234"), currency: currency("JPY"), locale: english)
        XCTAssertTrue(yen.contains("1,234"))
        XCTAssertFalse(yen.contains("."))
        XCTAssertFalse(yen.contains("₽"))
        for value in ["1.234", "1.000"] {
            let result = MoneyFormatter.string(amount(value), currency: currency("KWD"), locale: english)
            XCTAssertTrue(result.contains(value), result)
            XCTAssertTrue(result.contains("KWD"), result)
        }
        let german = MoneyFormatter.string(
            amount("0.49"), currency: currency("EUR"), locale: Locale(identifier: "de_DE")
        )
        XCTAssertTrue(german.contains("0,49"), german)
        XCTAssertTrue(german.contains("€"), german)
        XCTAssertFalse(german.contains("₽"), german)
    }

    func testDoubleBridgePreservesFractionalPaidValues() {
        let usd = currency("USD")
        for (value, expected) in [(0.49, "$0.49"), (2.99, "$2.99"), (1.79, "$1.79")] {
            XCTAssertEqual(MoneyFormatter.string(value, currency: usd, locale: english), expected)
            let transaction = Transaction(type: .topup, amount: value, currency: usd)
            let preview = WalletTransactionPreview.item(for: transaction).amountText
            let history = WalletTransactionHistoryViewController.makeAmountLabel(for: transaction).attributedText?.string
            XCTAssertEqual(preview, history)
            XCTAssertEqual(preview.filter(\.isNumber), expected.filter(\.isNumber))
            XCTAssertTrue(preview.contains("$"), preview)
            XCTAssertTrue(preview.hasPrefix("+"), preview)
        }
    }

    func testExplicitRublesKeepCanonWithoutTruncatingPaidKopecks() {
        XCTAssertEqual(
            MoneyFormatter.string(amount("1234"), currency: .rub, locale: russian),
            "1\u{00A0}234\u{202F}₽"
        )
        XCTAssertEqual(
            MoneyFormatter.string(amount("49.99"), currency: .rub, locale: russian),
            "49,99\u{202F}₽"
        )
        // The old API remains a compatibility path until its other callers migrate.
        XCTAssertEqual(MoneyFormatter.string(amount("49.99")), "49\u{202F}₽")
    }

    func testAttributedTextPreservesFoundationOrderFontsAndCallerColor() {
        let font = UIFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        for code in ["RUB", "USD", "EUR", "JPY", "KWD"] {
            let unit = currency(code)
            let text = MoneyFormatter.attributed(
                amount("1.234"), currency: unit, digitsFont: font,
                prefix: "−", color: .red, locale: english
            )
            XCTAssertEqual(text.string, "−" + MoneyFormatter.string(amount("1.234"), currency: unit, locale: english))
            let gap = (text.string as NSString).range(of: "\u{202F}₽").location
            for index in 0..<text.length {
                let actual = text.attribute(.font, at: index, effectiveRange: nil) as? UIFont
                if unit == .rub && index == gap {
                    XCTAssertNotEqual(actual, font)
                    XCTAssertEqual(actual?.pointSize, font.pointSize)
                } else {
                    XCTAssertEqual(actual, font)
                }
                XCTAssertEqual(text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor, .red)
            }
            let uncolored = MoneyFormatter.attributed(amount("0.49"), currency: unit, digitsFont: font)
            for index in 0..<uncolored.length {
                XCTAssertNil(uncolored.attribute(.foregroundColor, at: index, effectiveRange: nil))
            }
        }
    }

    func testRealPreviewAndHistoryLabelsUseEachRowsCurrencyFractionAndDirection() {
        let cases: [(TransactionType, String)] = [
            (.charge, "−"), (.topup, "+"), (.refund, "+"), (.unknown("future"), "")
        ]
        for code in ["RUB", "USD", "EUR"] {
            for (type, sign) in cases {
                let transaction = Transaction(type: type, amount: 0.49, currency: currency(code))
                let preview = WalletTransactionPreview.item(for: transaction)
                let label = WalletTransactionHistoryViewController.makeAmountLabel(for: transaction)
                let rendered = label.attributedText?.string ?? ""
                XCTAssertEqual(preview.amountText, rendered)
                XCTAssertTrue(rendered.hasPrefix(sign), rendered)
                XCTAssertTrue(rendered.contains("0,49"), rendered)
                switch code {
                case "RUB": XCTAssertTrue(rendered.hasSuffix("\u{202F}₽"), rendered)
                case "USD": XCTAssertTrue(rendered.contains("$"), rendered)
                default: XCTAssertTrue(rendered.contains("€"), rendered)
                }
                if code != "RUB" { XCTAssertFalse(rendered.contains("₽"), rendered) }
                if sign.isEmpty {
                    XCTAssertFalse(rendered.hasPrefix("+"), rendered)
                    XCTAssertFalse(rendered.hasPrefix("−"), rendered)
                }
                XCTAssertEqual(label.font, AppTypography.moneyMd)
                XCTAssertEqual(label.textColor, WalletAmountTint.ink(for: WalletLedgerDirection(type)))
            }
        }
    }

    func testHistoryBeyondIntAndInvalidAmountsDoNotBecomeZero() {
        let exact = MoneyFormatter.string(amount("18446744073709551616"), currency: .rub, locale: russian)
        XCTAssertEqual(exact.filter(\.isNumber), "18446744073709551616")
        let large = Transaction(type: .topup, amount: 18_446_744_073_709_551_616, currency: .rub)
        let plain = MoneyFormatter.string(large.amount, currency: .rub)
        XCTAssertEqual(plain.filter(\.isNumber), "18446744073709551616")
        let label = WalletTransactionHistoryViewController.makeAmountLabel(for: large)
        let digits = (label.attributedText?.string ?? "").filter(\.isNumber)
        XCTAssertEqual(digits, "18446744073709551616")
        XCTAssertEqual(WalletTransactionPreview.item(for: large).amountText.filter(\.isNumber), digits)
        for invalid in [Decimal.nan, amount("-1")] {
            XCTAssertEqual(MoneyFormatter.string(invalid, currency: currency("USD")), "—")
        }
        // 2^128 is within Decimal's exponent range but has 39 significant
        // digits. Decimal rounding may still round-trip to this same Double.
        let tooPrecise: Double = 340_282_366_920_938_463_463_374_607_431_768_211_456
        for invalid in [Double.nan, .infinity, -.infinity, 1e200, .leastNonzeroMagnitude, tooPrecise] {
            XCTAssertEqual(MoneyFormatter.string(invalid, currency: currency("USD")), "—")
            let transaction = Transaction(type: .unknown("future"), amount: invalid, currency: currency("USD"))
            XCTAssertEqual(WalletTransactionPreview.item(for: transaction).amountText, "—")
            XCTAssertEqual(
                WalletTransactionHistoryViewController.makeAmountLabel(for: transaction).attributedText?.string, "—"
            )
        }
    }

    func testLegacyJSONWithoutCurrencyStillRendersCanonicalRubles() throws {
        let original = Transaction(type: .topup, amount: 500)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        object.removeValue(forKey: "currency")
        let decoded = try JSONDecoder().decode(Transaction.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.currency, .rub)
        XCTAssertEqual(WalletTransactionPreview.item(for: decoded).amountText, "+500\u{202F}₽")
        XCTAssertEqual(
            WalletTransactionHistoryViewController.makeAmountLabel(for: decoded).attributedText?.string,
            "+500\u{202F}₽"
        )
    }
}
