import XCTest
@testable import SnoozePay

/// Large-count copy must retain every integer digit and its noun form (#1059).
final class SnoozeAffordabilityLargeCountTests: XCTestCase {
    func testHintPreservesLargeIntegerDigitsAndRussianForms() {
        let cases: [(count: Int, expected: String)] = [
            (9_007_199_254_740_991,
             "Хватит на ~9\u{00A0}007\u{00A0}199\u{00A0}254\u{00A0}740\u{00A0}991 откладывание"),
            (9_007_199_254_740_992,
             "Хватит на ~9\u{00A0}007\u{00A0}199\u{00A0}254\u{00A0}740\u{00A0}992 откладывания"),
            (9_007_199_254_740_996,
             "Хватит на ~9\u{00A0}007\u{00A0}199\u{00A0}254\u{00A0}740\u{00A0}996 откладываний"),
            (9_007_199_254_741_012,
             "Хватит на ~9\u{00A0}007\u{00A0}199\u{00A0}254\u{00A0}741\u{00A0}012 откладываний"),
            (9_223_372_036_854_774_784,
             "Хватит на ~9\u{00A0}223\u{00A0}372\u{00A0}036\u{00A0}854\u{00A0}774\u{00A0}784 откладывания")
        ]

        for testCase in cases {
            XCTAssertEqual(
                SnoozeAffordability.hint(
                    balance: Double(testCase.count),
                    alarms: [Alarm(penaltyAmount: 1, enabled: true)]
                ),
                testCase.expected
            )
        }
    }

    func testLargeCountTemplateFormatsExactRussianAndEnglishCompiledResources() throws {
        let cases: [(language: String, expected: String)] = [
            ("ru", "Хватит на ~9\u{00A0}223\u{00A0}372\u{00A0}036\u{00A0}854\u{00A0}775\u{00A0}807 откладываний"),
            ("en", "Enough for ~9,223,372,036,854,775,807 snoozes")
        ]

        for testCase in cases {
            let url = try XCTUnwrap(Bundle.main.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: "\(testCase.language).lproj"
            ))
            let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            let template = try XCTUnwrap(strings["common.snooze_affordability_large"])
            let noun = try XCTUnwrap(strings["plural.snoozes.many"])
            let locale = Locale(identifier: testCase.language == "ru" ? "ru_RU" : "en_US")
            let number = IntegerFormatStyle<Int>(locale: locale).format(Int.max)

            XCTAssertEqual(
                String(format: template, locale: locale, arguments: [number, noun]),
                testCase.expected
            )
        }
    }
}
