import XCTest
@testable import SnoozePay

/// Tests for the StreakModal copy + savings helpers.
///
/// The sheet leads with the money saved and offers a "Поделиться победой" CTA
/// again (#347, PM decision 2026-07-30), so the caption / headline / share-text
/// composers and the savings estimator all carry user-visible strings and are
/// pinned here.
final class StreakModalCopyTests: XCTestCase {

    // MARK: - dayWord declension

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

    // MARK: - Caption (the streak demoted below the money hero)

    func testStreakCaptionIsUppercasedWithDeclension() {
        XCTAssertEqual(
            StreakModalViewController.streakCaption(for: 7),
            "СЕРИЯ · 7 ДНЕЙ БЕЗ ОТКЛАДЫВАНИЙ"
        )
        XCTAssertEqual(
            StreakModalViewController.streakCaption(for: 3),
            "СЕРИЯ · 3 ДНЯ БЕЗ ОТКЛАДЫВАНИЙ"
        )
        XCTAssertEqual(
            StreakModalViewController.streakCaption(for: 1),
            "СЕРИЯ · 1 ДЕНЬ БЕЗ ОТКЛАДЫВАНИЙ"
        )
    }

    // MARK: - Savings headline

    func testSavingsHeadlineUsesWeekWordingForSevenDays() {
        XCTAssertEqual(StreakModalViewController.savingsHeadline(for: 7), "Сэкономили за неделю")
    }

    func testSavingsHeadlineSpellsDayCountOtherwise() {
        XCTAssertEqual(StreakModalViewController.savingsHeadline(for: 3), "Сэкономили за 3 дня")
        XCTAssertEqual(StreakModalViewController.savingsHeadline(for: 14), "Сэкономили за 14 дней")
        XCTAssertEqual(StreakModalViewController.savingsHeadline(for: 21), "Сэкономили за 21 день")
    }

    // MARK: - Hero amount

    func testFormatSavedAmountIsSignedAndGrouped() {
        XCTAssertEqual(
            StreakModalViewController.formatSavedAmount(350),
            "+350\(MoneyFormatter.narrowSpace)₽"
        )
        XCTAssertEqual(
            StreakModalViewController.formatSavedAmount(1500),
            "+\(MoneyFormatter.digits(Decimal(1500)))\(MoneyFormatter.narrowSpace)₽"
        )
    }

    func testFormatSavedAmountMatchesDesignArtboardForDefaultWeek() {
        // `28-streak` shows "+350 ₽" for a 7-day streak at the default price.
        let saved = StreakModalViewController.estimatedSavings(for: 7, alarms: [])
        XCTAssertEqual(
            StreakModalViewController.formatSavedAmount(saved),
            "+350\(MoneyFormatter.narrowSpace)₽"
        )
    }

    // MARK: - Share text

    func testShareTextMentionsStreakAndSavedAmount() {
        XCTAssertEqual(
            StreakModalViewController.shareText(streakDays: 7, savedAmount: 350),
            "Я не откладываю будильник 7 дней и сэкономил 350\(MoneyFormatter.narrowSpace)₽ — SnoozePay"
        )
    }

    func testShareTextDeclinesTheDayWord() {
        XCTAssertTrue(
            StreakModalViewController.shareText(streakDays: 1, savedAmount: 50)
                .hasPrefix("Я не откладываю будильник 1 день ")
        )
        XCTAssertTrue(
            StreakModalViewController.shareText(streakDays: 3, savedAmount: 150)
                .hasPrefix("Я не откладываю будильник 3 дня ")
        )
    }

    // MARK: - estimatedSavings

    func testEstimatedSavingsZeroStreakIsZero() {
        XCTAssertEqual(StreakModalViewController.estimatedSavings(for: 0, alarms: []), 0)
        XCTAssertEqual(StreakModalViewController.estimatedSavings(for: -5, alarms: []), 0)
    }

    func testEstimatedSavingsDefaultsToFiftyPerDayWithoutAlarms() {
        XCTAssertEqual(StreakModalViewController.estimatedSavings(for: 7, alarms: []), 350)
    }

    func testEstimatedSavingsUsesSingleAlarmPenaltyPerDay() {
        let alarm = Alarm(penaltyAmount: 200, progressiveScale: false)
        XCTAssertEqual(StreakModalViewController.estimatedSavings(for: 3, alarms: [alarm]), 600)
    }

    func testEstimatedSavingsAveragesAcrossAlarms() {
        let cheap = Alarm(penaltyAmount: 50, progressiveScale: false)
        let pricey = Alarm(penaltyAmount: 150, progressiveScale: false)
        // (50 + 150) / 2 = 100 ₽/day × 7 days.
        XCTAssertEqual(
            StreakModalViewController.estimatedSavings(for: 7, alarms: [cheap, pricey]),
            700
        )
    }

    func testEstimatedSavingsScalesLinearlyWithStreakLength() {
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: false)
        let week = StreakModalViewController.estimatedSavings(for: 7, alarms: [alarm])
        let fortnight = StreakModalViewController.estimatedSavings(for: 14, alarms: [alarm])
        XCTAssertEqual(fortnight, week * 2)
    }
}
