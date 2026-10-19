import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class PenaltyCellAmountTests: XCTestCase {
    func testConfigureRendersLargeFiniteAmountsWithoutNarrowingOrEmitting() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        let field = try amountField(in: cell)
        var changes: [Double] = []
        cell.onValueChanged = { changes.append($0) }
        for amount in [Double(Int.max).nextDown, Double(Int.max), Double(Int.max) * 2, .greatestFiniteMagnitude] {
            cell.configure(amount: amount, currency: .rub)
            let text = try XCTUnwrap(field.text)
            XCTAssertEqual(Double(text), amount)
            XCTAssertTrue(text.utf8.allSatisfy { (48...57).contains($0) })
        }
        XCTAssertTrue(changes.isEmpty, "Rendering must not rewrite persisted money")
    }

    func testIntMaxInputCommitsTheDoubleRepresentationAndInvalidEditRestoresIt() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        let field = try amountField(in: cell)
        cell.configure(amount: 50, currency: .rub)
        var changes: [Double] = []
        cell.onValueChanged = { changes.append($0) }
        field.text = "9223372036854775807"
        field.sendActions(for: .editingChanged)
        XCTAssertTrue(changes.isEmpty)
        field.sendActions(for: .editingDidEnd)
        XCTAssertEqual(changes, [Double(Int.max)])
        XCTAssertEqual(field.text, "9223372036854775808", "Show the actual stored Double before Save")
        for invalid in ["", "0", "-1", "1.5", "1e3", "NaN", String(repeating: "9", count: 400)] {
            field.text = invalid
            field.sendActions(for: .editingChanged)
            field.sendActions(for: .editingDidEnd)
            XCTAssertEqual(field.text, "9223372036854775808")
            XCTAssertEqual(changes.count, 1, "Invalid editing must not change money")
        }
    }

    func testInputBeyondIntRangeUsesFiniteDoubleRepresentationWithoutABusinessCap() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        let field = try amountField(in: cell)
        cell.configure(amount: 50, currency: .rub)
        var changes: [Double] = []
        cell.onValueChanged = { changes.append($0) }
        field.text = "18446744073709551616"
        field.sendActions(for: .editingDidEnd)
        XCTAssertEqual(changes, [Double(Int.max) * 2])
        XCTAssertEqual(field.text, "18446744073709551616")
    }

    func testInvalidStoredAmountAndReconfigurationNeverInventAFallbackPrice() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        let field = try amountField(in: cell)
        let helper = try XCTUnwrap(descendant(UILabel.self, in: cell) {
            $0.text == Localized.text("create_alarm.penalty.minimum")
        })
        for amount in [Double.nan, .infinity, -.infinity, 0, -1] {
            cell.configure(amount: 50, currency: .rub)
            cell.prepareForReuse()
            var changes: [Double] = []
            cell.onValueChanged = { changes.append($0) }
            cell.configure(amount: amount, currency: .rub)
            XCTAssertTrue(field.text?.isEmpty != false)
            XCTAssertFalse(helper.isHidden)
            field.text = "0"
            field.sendActions(for: .editingDidEnd)
            XCTAssertEqual(field.text, "0", "Do not restore the previous cell's price or invent 1")
            XCTAssertFalse(helper.isHidden)
            XCTAssertTrue(changes.isEmpty)
            cell.configure(amount: 137, currency: .rub)
            XCTAssertEqual(field.text, "137")
            XCTAssertTrue(helper.isHidden)
            XCTAssertTrue(changes.isEmpty)
        }
    }

    func testOrdinaryCustomPresetAndFractionalDisplayBehaviorIsPreserved() throws {
        let cell = PenaltyCell(style: .default, reuseIdentifier: nil)
        let field = try amountField(in: cell)
        var changes: [Double] = []
        cell.onValueChanged = { changes.append($0) }
        cell.configure(amount: 49.5, currency: .rub)
        XCTAssertEqual(field.text, "50")
        XCTAssertTrue(changes.isEmpty, "Display rounding must not rewrite fractional billing data")
        let preset = try XCTUnwrap(descendant(UIButton.self, in: cell) { $0.title(for: .normal) == "20" })
        preset.sendActions(for: .touchUpInside)
        XCTAssertEqual(field.text, "20")
        field.text = "137"
        field.sendActions(for: .editingChanged)
        XCTAssertEqual(changes, [20])
        field.sendActions(for: .editingDidEnd)
        XCTAssertEqual(changes, [20, 137])
    }

    private func amountField(in cell: PenaltyCell) throws -> UITextField {
        try XCTUnwrap(descendant(UITextField.self, in: cell) {
            $0.accessibilityIdentifier == "createAlarm.penaltyField"
        })
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView, matching predicate: (T) -> Bool) -> T? {
        if let found = view as? T, predicate(found) { return found }
        for child in view.subviews {
            if let found = descendant(type, in: child, matching: predicate) { return found }
        }
        return nil
    }
}
