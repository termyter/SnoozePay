import UIKit
import XCTest
@testable import SnoozePay

final class SPSnoozePriceAccessibilityTests: XCTestCase {
    func testEnabledTransitionsExposeDisabledStateAndPreserveOtherTraits() {
        let control = SPSnoozePrice(price: 50, currency: .rub)
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.accessibilityTraits.contains(.button))
        XCTAssertFalse(control.accessibilityTraits.contains(.notEnabled))
        control.accessibilityTraits.insert(.selected)

        for enabled in [false, true, false, true] {
            control.isEnabled = enabled
            XCTAssertEqual(control.accessibilityTraits.contains(.notEnabled), !enabled)
            XCTAssertTrue(control.accessibilityTraits.contains(.button))
            XCTAssertTrue(control.accessibilityTraits.contains(.selected),
                          "Changing enabled state must preserve traits supplied by the caller")
        }
    }

    func testPriceAndMinutesUpdatesPreserveDisabledAccessibilityState() {
        let control = SPSnoozePrice(price: 50, currency: .rub, minutes: 5)
        control.accessibilityTraits.insert(.selected)
        control.isEnabled = false
        let previousValue = control.accessibilityValue
        let previousLabel = control.accessibilityLabel

        control.update(price: 137, currency: .rub, minutes: 10, hint: "Updated hint")

        XCTAssertEqual(control.price, 137)
        XCTAssertEqual(control.minutes, 10)
        XCTAssertNotEqual(control.accessibilityValue, previousValue)
        XCTAssertNotEqual(control.accessibilityLabel, previousLabel)
        XCTAssertFalse(control.isEnabled)
        XCTAssertTrue(control.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(control.accessibilityTraits.contains(.button))
        XCTAssertTrue(control.accessibilityTraits.contains(.selected))
    }
}
