import XCTest
@testable import SnoozePay

/// Tests for the composed VoiceOver label `AlarmCell` builds from its display
/// fields (#418). Without this the screen reader announced "07:00", "50 ₽",
/// "×2" as disconnected fragments; the helper joins them into one sentence so
/// the card reads as a single coherent control.
final class AlarmCellAccessibilityTests: XCTestCase {

    func testFullLabelComposesAllParts() {
        let label = AlarmCell.accessibilityLabel(
            time: "07:00",
            daysCaps: "БУДНИ · ПН–ПТ",
            priceText: "50 ₽",
            multiplier: "×2",
            soundName: "Soft Dawn"
        )
        XCTAssertEqual(label, "Будильник 07:00, Будни · пн–пт, 50 ₽, ×2, Soft Dawn")
    }

    func testMinimalLabelDropsOptionalParts() {
        let label = AlarmCell.accessibilityLabel(
            time: "9:30",
            daysCaps: "ВЫХОДНЫЕ",
            priceText: "100 ₽",
            multiplier: nil,
            soundName: nil
        )
        XCTAssertEqual(label, "Будильник 9:30, Выходные, 100 ₽")
    }

    func testEmptyOptionalsAreSkipped() {
        // Empty / whitespace-only optional fields must not produce dangling
        // ", , " separators.
        let label = AlarmCell.accessibilityLabel(
            time: "6:00",
            daysCaps: "ПН, ВТ, СР",
            priceText: "30 ₽",
            multiplier: "",
            soundName: "   "
        )
        XCTAssertEqual(label, "Будильник 6:00, Пн, вт, ср, 30 ₽")
    }

    func testEmptyDaysCapsOmitsTheSegment() {
        let label = AlarmCell.accessibilityLabel(
            time: "8:15",
            daysCaps: "",
            priceText: "25 ₽",
            multiplier: nil,
            soundName: nil
        )
        XCTAssertEqual(label, "Будильник 8:15, 25 ₽")
    }

    func testAlwaysStartsWithAlarmAndTime() {
        let label = AlarmCell.accessibilityLabel(
            time: "00:00",
            daysCaps: "",
            priceText: "",
            multiplier: nil,
            soundName: nil
        )
        XCTAssertEqual(label, "Будильник 00:00")
    }
}
