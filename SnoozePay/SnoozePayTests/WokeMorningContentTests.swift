import XCTest
@testable import SnoozePay

/// Tests for the WokeMorning summary screen (#228) copy logic — variant
/// selection (clean vs recovered), the genitive declension of «откладывание»
/// after «после N …», and the rendered headline / subtitle strings.
///
/// Lives in the pure `WokeMorningContent` so no UIKit is needed.
final class WokeMorningContentTests: XCTestCase {

    // MARK: - Variant selection

    func testZeroSnoozesSelectsClean() {
        XCTAssertEqual(WokeMorningContent(snoozes: 0, charged: 0).variant, .clean)
    }

    func testPositiveSnoozesSelectRecovered() {
        XCTAssertEqual(WokeMorningContent(snoozes: 1, charged: 50).variant, .recovered)
        XCTAssertEqual(WokeMorningContent(snoozes: 5, charged: 300).variant, .recovered)
    }

    func testNegativeSnoozesClampToClean() {
        // Defensive: a stray negative count must not crash or read "recovered".
        XCTAssertEqual(WokeMorningContent(snoozes: -3, charged: 0).variant, .clean)
    }

    // MARK: - Eyebrow (constant)

    func testEyebrowIsGoodMorning() {
        XCTAssertEqual(WokeMorningContent.eyebrow, "Доброе утро")
    }

    // MARK: - Clean variant copy

    func testCleanHeadlineAndSubtitle() {
        let content = WokeMorningContent(snoozes: 0, charged: 0)
        XCTAssertEqual(content.headline, "Встал с первого раза")
        XCTAssertEqual(content.subtitle, "Баланс в полной сохранности. Так держать.")
    }

    // MARK: - Recovered variant copy

    func testRecoveredHeadlineEmbedsCountAndDeclension() {
        XCTAssertEqual(
            WokeMorningContent(snoozes: 1, charged: 50).headline,
            "Удержались после 1 откладывания"
        )
        XCTAssertEqual(
            WokeMorningContent(snoozes: 2, charged: 100).headline,
            "Удержались после 2 откладываний"
        )
        XCTAssertEqual(
            WokeMorningContent(snoozes: 5, charged: 300).headline,
            "Удержались после 5 откладываний"
        )
    }

    func testRecoveredSubtitleEmbedsChargedSum() {
        XCTAssertEqual(
            WokeMorningContent(snoozes: 2, charged: 150).subtitle,
            "Сегодня списано 150 ₽. Завтра попробуем не списать ничего."
        )
    }

    // MARK: - Declension («после N откладывани…», genitive after «после»)

    func testSnoozeWordSingularGenitive() {
        // N % 10 == 1 && N % 100 != 11 → "откладывания".
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 1), "откладывания")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 21), "откладывания")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 101), "откладывания")
    }

    func testSnoozeWordPluralGenitive() {
        // Everything else → "откладываний" (incl. the 2-4 paucal: genitive
        // after «после» does NOT take the nominative 2-4 form).
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 0), "откладываний")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 2), "откладываний")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 3), "откладываний")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 4), "откладываний")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 5), "откладываний")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 22), "откладываний")
    }

    func testSnoozeWordTeensAlwaysPlural() {
        // 11 ends in 1 but the -teen exception forces the plural form.
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 11), "откладываний")
        XCTAssertEqual(WokeMorningContent.snoozeWord(for: 111), "откладываний")
    }
}
