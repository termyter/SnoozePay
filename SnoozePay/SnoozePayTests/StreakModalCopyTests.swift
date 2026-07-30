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
        // `28-streak` shows "+350 ₽" for a 7-day streak — i.e. one week of the
        // default 50 ₽ alarm price.
        let defaultPriced = Alarm(penaltyAmount: 50, progressiveScale: false)
        let saved = StreakModalViewController.estimatedSavings(for: 7, alarms: [defaultPriced])
        XCTAssertEqual(
            saved.map(StreakModalViewController.formatSavedAmount),
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

    func testEstimatedSavingsNonPositiveStreakHasNoFigure() {
        XCTAssertNil(StreakModalViewController.estimatedSavings(for: 0, alarms: []))
        XCTAssertNil(StreakModalViewController.estimatedSavings(for: -5, alarms: []))
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: false)
        XCTAssertNil(StreakModalViewController.estimatedSavings(for: 0, alarms: [alarm]))
    }

    /// Replaces the pre-review `testEstimatedSavingsDefaultsToFiftyPerDay…`,
    /// which froze a fabricated 50 ₽/day into the contract. No alarms → no
    /// prices → no figure the app is entitled to show or share.
    func testEstimatedSavingsWithoutAlarmsHasNoFigure() {
        XCTAssertNil(StreakModalViewController.estimatedSavings(for: 7, alarms: []))
    }

    /// A 0 ₽ alarm is legal (`Alarm` only requires `penaltyAmount >= 0`), and
    /// "сэкономили 0 ₽" is not a celebration.
    func testEstimatedSavingsAllFreeAlarmsHasNoFigure() {
        let free = Alarm(penaltyAmount: 0, progressiveScale: false)
        XCTAssertNil(StreakModalViewController.estimatedSavings(for: 7, alarms: [free, free]))
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

    /// A free alarm alongside a priced one lowers the average honestly — the
    /// zero is a real price, unlike an unparsable one (which is excluded from
    /// both numerator and denominator; that path trips `assertionFailure` and
    /// so can't be exercised from a Debug test run).
    func testEstimatedSavingsCountsFreeAlarmInTheAverage() {
        let free = Alarm(penaltyAmount: 0, progressiveScale: false)
        let priced = Alarm(penaltyAmount: 100, progressiveScale: false)
        XCTAssertEqual(
            StreakModalViewController.estimatedSavings(for: 7, alarms: [free, priced]),
            350
        )
    }

    func testEstimatedSavingsScalesLinearlyWithStreakLength() {
        let alarm = Alarm(penaltyAmount: 50, progressiveScale: false)
        let week = StreakModalViewController.estimatedSavings(for: 7, alarms: [alarm])
        let fortnight = StreakModalViewController.estimatedSavings(for: 14, alarms: [alarm])
        XCTAssertEqual(fortnight, (week ?? 0) * 2)
        XCTAssertEqual(week, 350)
    }

    // MARK: - Mode — when the sheet is allowed to talk about money

    func testModeShowsSavingsForPositiveStreakAndAmount() {
        XCTAssertEqual(
            StreakModalViewController.mode(streakDays: 7, savedAmount: 350),
            .savings(350)
        )
    }

    /// Caller couldn't compute a figure (e.g. the alarm store failed to read):
    /// celebrate the habit, never invent roubles.
    func testModeFallsBackToBehavioralWhenAmountUnavailable() {
        XCTAssertEqual(
            StreakModalViewController.mode(streakDays: 7, savedAmount: nil),
            .behavioral
        )
    }

    func testModeFallsBackToBehavioralForNonPositiveAmount() {
        XCTAssertEqual(StreakModalViewController.mode(streakDays: 7, savedAmount: 0), .behavioral)
        XCTAssertEqual(StreakModalViewController.mode(streakDays: 7, savedAmount: -50), .behavioral)
    }

    /// `StatisticsViewController` opens the sheet with `max(streak, 1)`, so a
    /// zero — or unreadable — streak reaches the modal as 1. The modal itself
    /// refuses to mint money out of it.
    func testModeFallsBackToBehavioralForNonPositiveStreak() {
        XCTAssertEqual(StreakModalViewController.mode(streakDays: 0, savedAmount: 350), .behavioral)
        XCTAssertEqual(StreakModalViewController.mode(streakDays: -3, savedAmount: 350), .behavioral)
    }

    // MARK: - Copy per mode

    func testSavingsModeCopyLeadsWithMoney() {
        let copy = StreakModalViewController.copy(streakDays: 7, mode: .savings(350))
        XCTAssertEqual(copy.caps, "СЕРИЯ · 7 ДНЕЙ БЕЗ ОТКЛАДЫВАНИЙ")
        XCTAssertEqual(copy.headline, "Сэкономили за неделю")
        XCTAssertTrue(copy.body.contains("остались у вас на балансе"))
    }

    func testBehavioralModeCopyMentionsNoMoney() {
        let copy = StreakModalViewController.copy(streakDays: 7, mode: .behavioral)
        XCTAssertEqual(copy.caps, "СЕРИЯ")
        XCTAssertEqual(copy.headline, "7 дней без откладываний")
        for line in [copy.caps, copy.headline, copy.body] {
            XCTAssertFalse(line.contains("₽"), "behavioral copy must not quote money: \(line)")
            XCTAssertFalse(
                line.lowercased().contains("сэкономи"),
                "behavioral copy must not claim savings: \(line)"
            )
        }
    }

    // MARK: - Rendered sheet
    //
    // The mode decision only matters if it reaches the view tree: these walk
    // the loaded sheet and assert what the user can actually see and tap.

    func testRenderedSheetShowsHeroAndShareForRealSavings() {
        let vc = StreakModalViewController(streakDays: 7, savedAmount: 350)
        vc.loadViewIfNeeded()

        let texts = Self.renderedText(in: vc.view)
        XCTAssertTrue(
            texts.contains { $0.contains("350") && $0.contains("₽") },
            "money hero missing from the sheet: \(texts)"
        )
        XCTAssertTrue(texts.contains("Поделиться победой"), "share CTA missing: \(texts)")
        XCTAssertTrue(texts.contains("Закрыть"))
    }

    func testRenderedSheetHidesHeroAndShareWhenAmountUnavailable() {
        let vc = StreakModalViewController(streakDays: 7, savedAmount: nil)
        vc.loadViewIfNeeded()

        let texts = Self.renderedText(in: vc.view)
        XCTAssertFalse(
            texts.contains { $0.contains("₽") },
            "sheet must not quote money without a figure: \(texts)"
        )
        XCTAssertFalse(texts.contains("Поделиться победой"), "share CTA must be gone: \(texts)")
        XCTAssertTrue(texts.contains("Закрыть"))
        XCTAssertTrue(texts.contains("7 дней без откладываний"))
    }

    func testRenderedSheetHidesHeroAndShareForZeroSavings() {
        let vc = StreakModalViewController(streakDays: 7, savedAmount: 0)
        vc.loadViewIfNeeded()

        let texts = Self.renderedText(in: vc.view)
        XCTAssertFalse(texts.contains { $0.contains("₽") }, "no +0 ₽ hero: \(texts)")
        XCTAssertFalse(texts.contains("Поделиться победой"))
    }

    func testRenderedSheetHidesMoneyForZeroStreak() {
        let vc = StreakModalViewController(streakDays: 0, savedAmount: 350)
        vc.loadViewIfNeeded()

        let texts = Self.renderedText(in: vc.view)
        XCTAssertFalse(texts.contains { $0.contains("₽") }, "no money out of a 0-day streak: \(texts)")
        XCTAssertFalse(texts.contains("Поделиться победой"))
    }

    /// The money hero is centred, not left-pinned — the label is stretched to
    /// the full sheet width, so only `textAlignment` keeps the glyphs in the
    /// middle (`applyGradientMask` reproduces it when it rasterises the mask).
    func testMoneyHeroIsCentreAligned() {
        let vc = StreakModalViewController(streakDays: 7, savedAmount: 350)
        vc.loadViewIfNeeded()

        let hero = Self.labels(in: vc.view).first {
            ($0.text ?? "").contains("350") && ($0.text ?? "").contains("₽")
        }
        XCTAssertNotNil(hero)
        XCTAssertEqual(hero?.textAlignment, .center)
        // Auto-shrink keeps a long amount whole instead of clipping it.
        XCTAssertTrue(hero?.adjustsFontSizeToFitWidth == true)
    }

    // MARK: - Helpers

    private static func labels(in view: UIView) -> [UILabel] {
        var found: [UILabel] = []
        for subview in view.subviews {
            if let label = subview as? UILabel {
                found.append(label)
            }
            found.append(contentsOf: labels(in: subview))
        }
        return found
    }

    /// Every user-visible string in the tree: label text plus the
    /// accessibility label `SPButton` derives from its title.
    private static func renderedText(in view: UIView) -> [String] {
        var found: [String] = []
        for subview in view.subviews {
            if let label = subview as? UILabel, let text = label.text {
                found.append(text)
            }
            if let button = subview as? SPButton, let title = button.accessibilityLabel {
                found.append(title)
            }
            found.append(contentsOf: renderedText(in: subview))
        }
        return found
    }
}
