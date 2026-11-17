import os
import XCTest
@testable import SnoozePay

final class CalendarDateFormatterDiagnosticTests: XCTestCase {
    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let locale = Locale(identifier: "en_US")
    private let prefix = "CalendarDateFormatter: "

    func testEmptyRenderingLeavesExactlyTheOriginalUIFault() {
        var calls = 0
        var lines: [LoggedLine] = []
        let rendered = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            CalendarDateFormatter.string(from: date, style: .dayMonthShort, locale: locale) { _, input in
                calls += 1
                XCTAssertEqual(input, self.date)
                return ""
            }
        })

        let target = lines.filter { $0.message.hasPrefix(prefix) }
        XCTAssertEqual(calls, 1, "the fault must be reached through actual rendering")
        XCTAssertEqual(rendered, "", "diagnostics must not silently replace the existing result")
        XCTAssertEqual(target.count, 1)
        XCTAssertEqual(target.first?.category, .ui)
        XCTAssertEqual(target.first?.level, .fault)
        XCTAssertEqual(target.first?.message, "CalendarDateFormatter: dMMM rendered nothing for en_US")
    }

    func testNonemptyRenderingReturnsTheResultWithoutAFormatterFault() {
        var calls = 0
        var lines: [LoggedLine] = []
        let rendered = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            CalendarDateFormatter.string(from: date, style: .dayMonth, locale: locale) { _, _ in
                calls += 1
                return "rendered date"
            }
        })

        XCTAssertEqual(calls, 1, "an empty sink must not be explained by skipping rendering")
        XCTAssertEqual(rendered, "rendered date")
        XCTAssertFalse(lines.contains { $0.message.hasPrefix(prefix) })
    }
}
