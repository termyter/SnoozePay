import Foundation
import os
import UserNotifications
import XCTest
@testable import SnoozePay

@MainActor
final class AppDelegateSnoozeDiagnosticTests: XCTestCase {

    private struct LoggedLine {
        let category: AppLogCategory
        let level: OSLogType
        let message: String
    }

    func testInvalidPayload_actualHandlerLeavesTheErrorWithoutPostingABanner() throws {
        try assertOutcome(
            .invalidPayload, level: .error,
            message: "SNOOZE_ACTION: invalid payload, snooze skipped"
        )
    }

    func testMissingAlarm_actualHandlerLeavesTheNoticeWithoutPostingABanner() throws {
        try assertOutcome(
            .alarmNotFound, level: .default,
            message: "SNOOZE_ACTION: alarm not found, snooze skipped"
        )
    }

    func testInsufficientFunds_actualHandlerLeavesTheNoticeWithoutPostingABanner() throws {
        try assertOutcome(
            .insufficientFunds, level: .default,
            message: "SNOOZE_ACTION: insufficient funds — snooze skipped, alarm will not repeat"
        )
    }

    /// #1136: its own line, not "insufficient funds".
    func testCurrencyMismatch_actualHandlerNamesBothCurrenciesWithoutPostingABanner() throws {
        try assertOutcome(
            .currencyMismatch(price: Currency(code: "USD")!, wallet: .rub), level: .default,
            message: "SNOOZE_ACTION: price in USD, wallet in RUB — snooze skipped, nothing charged"
        )
    }

    /// #1136: logged, and the one refusal here that posts the lost-snooze banner.
    func testPriceUnavailable_actualHandlerLogsTheErrorAndPostsTheBanner() throws {
        try assertOutcome(
            .priceUnavailable(currency: Currency(code: "USD")!), level: .error,
            message: "SNOOZE_ACTION: no snooze price in USD — snooze skipped, nothing charged — posting banner",
            postsBanner: true
        )
    }

    /// #1136: a price that resolved but cannot be debited is a defect, not an
    /// unloaded catalogue, so no "open the app" banner.
    func testPriceNotRepresentable_actualHandlerLogsTheErrorWithoutPostingABanner() throws {
        try assertOutcome(
            .priceNotRepresentable(currency: Currency(code: "USD")!), level: .error,
            message: "SNOOZE_ACTION: snooze price in USD not chargeable — snooze skipped, nothing charged"
        )
    }

    func testScheduled_actualHandlerReportsItsPublicCountAndChargeWithoutPostingABanner() throws {
        try assertOutcome(
            .scheduled(newSnoozeCount: 3, charged: 2.5), level: .info,
            message: "SNOOZE_ACTION: scheduled #3 charged=2.5"
        )
        try assertOutcome(
            .scheduled(newSnoozeCount: 8, charged: 99.125), level: .info,
            message: "SNOOZE_ACTION: scheduled #8 charged=99.125"
        )
    }

    private func assertOutcome(
        _ outcome: AlarmFiringCoordinator.SnoozeOutcome, level: OSLogType, message: String,
        postsBanner: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let defaults = makeIsolatedDefaults()
        let warnings = CriticalWarningCenter(defaults: defaults)
        warnings.isForegroundActive = { false }
        let delegate = AppDelegate()
        delegate.criticalWarnings = warnings
        let poster = LocalNotificationPosterSpy()
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(LoggedLine(category: $0, level: $1, message: $2)) }, perform: {
            delegate.handleSnoozeOutcome(outcome, poster: poster)
        })

        XCTAssertEqual(lines.count, 1, file: file, line: line)
        XCTAssertEqual(lines.first?.category, .appDelegate, file: file, line: line)
        XCTAssertEqual(lines.first?.level, level, file: file, line: line)
        XCTAssertEqual(lines.first?.message, message, file: file, line: line)
        XCTAssertEqual(
            poster.requests.count, postsBanner ? 1 : 0, "failure banners posted", file: file, line: line
        )
        XCTAssertTrue(
            warnings.pending.isEmpty, "these outcomes do not create critical warnings", file: file, line: line
        )
    }
}
