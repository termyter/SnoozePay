import XCTest
@testable import SnoozePay

/// Tests for the StreakModal V3 (de-monetized, #236) helper logic — the
/// day-word declension that drives the h1 headline, and the savings
/// estimator that the alarms-list streak banner still consumes.
final class StreakModalCopyTests: XCTestCase {

    // MARK: - dayWord declension (h1 headline "N <dayWord> без откладываний")

    func testDayWordSingularForm() {
        XCTAssertEqual(StreakModalViewController.dayWord(for: 1), "день")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 21), "день")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 101), "день")
    }

    func testDayWordPaucalForm() {
        XCTAssertEqual(StreakModalViewController.dayWord(for: 2), "дня")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 3), "дня")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 4), "дня")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 24), "дня")
    }

    func testDayWordPluralForm() {
        XCTAssertEqual(StreakModalViewController.dayWord(for: 5), "дней")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 7), "дней")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 11), "дней")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 14), "дней")
        XCTAssertEqual(StreakModalViewController.dayWord(for: 30), "дней")
    }

    func testDayWordTeensAlwaysPlural() {
        for count in 11...14 {
            XCTAssertEqual(StreakModalViewController.dayWord(for: count), "дней")
            XCTAssertEqual(StreakModalViewController.dayWord(for: 100 + count), "дней")
        }
    }

    // MARK: - estimatedSavings (still used by the alarms-list streak banner)

    func testEstimatedSavingsZeroStreakIsZero() {
        XCTAssertEqual(StreakModalViewController.estimatedSavings(for: 0, alarms: []), 0)
    }

    func testEstimatedSavingsDefaultsToFiftyPerDayWithoutAlarms() {
        XCTAssertEqual(StreakModalViewController.estimatedSavings(for: 7, alarms: []), 350)
    }
}
