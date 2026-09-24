import XCTest
import os
import UserNotifications
@testable import SnoozePay

/// `willPresent` used to treat every foreground notification as an alarm: the
/// app's own banners (resume-audio-failed, reschedule-failed,
/// snooze-schedule-failed, deferred purchase feedback) carry no alarm payload,
/// so each one got `[]` — never shown while the app was open — and an
/// `invalid alarm payload` error line (#842).
///
/// Driven through `AppDelegate.routeForegroundNotification(identifier:userInfo:)`
/// because `UNNotification` cannot be constructed in a test. The routing is
/// synchronous and emits on the calling thread, so the sink window below sees
/// every line it produces without a drain; the filter on `willPresent:` keeps
/// the assertions to this function's own lines.
final class ForegroundNotificationRouteTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    private static let invalidPayloadMarker = "invalid alarm payload"

    private func route(
        identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> (route: AppDelegate.ForegroundRoute, lines: [Line]) {
        var lines: [Line] = []
        let outcome = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            AppDelegate.routeForegroundNotification(identifier: identifier, userInfo: userInfo)
        })
        return (outcome, lines.filter { $0.message.contains("willPresent:") })
    }

    private func validAlarmUserInfo() -> [String: Any] {
        AlarmNotificationPayload(
            alarmID: UUID(),
            penaltyAmount: 50,
            progressiveScale: false,
            snoozeCount: 0,
            snoozeMinutes: 5,
            soundID: "classic"
        ).asUserInfo()
    }

    // MARK: - App banners

    func testEveryAppBanner_isPresentedAsABanner_withoutAnInvalidPayloadLine() {
        for banner in AppBannerNotification.allCases {
            let result = route(identifier: banner.makeIdentifier(), userInfo: [:])

            XCTAssertEqual(result.route, .appBanner(banner), "\(banner)")
            XCTAssertEqual(
                result.route.presentationOptions, [.banner, .sound, .list],
                "\(banner) must be shown in the foreground, not suppressed"
            )
            XCTAssertFalse(
                result.lines.contains { $0.message.contains(Self.invalidPayloadMarker) },
                "\(banner) is not a corrupt alarm; the sink saw \(result.lines.map(\.message))"
            )
            XCTAssertFalse(
                result.lines.contains { $0.level == .error || $0.level == .fault },
                "\(banner) must not log at error level; the sink saw \(result.lines.map(\.message))"
            )
            XCTAssertEqual(
                result.lines.map(\.level), [.info],
                "exactly one info line per banner; the sink saw \(result.lines.map(\.message))"
            )
        }
    }

    /// The identifiers the builders used before #842, spelled out. A banner
    /// scheduled by the previous build and delivered after an update carries
    /// one of these, and a rename of a raw value would otherwise pass the
    /// round-trip test above while dropping it.
    func testPreviousBuildsBannerIdentifiers_stillRouteAsBanners() {
        let suffix = UUID().uuidString
        let expected: [(String, AppBannerNotification)] = [
            ("resume_audio_failed_" + suffix, .resumeAudioFailed),
            ("reschedule_failed_" + suffix, .rescheduleFailed),
            ("snooze_schedule_failed_" + suffix, .snoozeScheduleFailed),
            ("snoozepay.storekit.feedback." + suffix, .purchaseFeedback)
        ]
        XCTAssertEqual(expected.count, AppBannerNotification.allCases.count, "a new banner needs a row here")

        for (identifier, banner) in expected {
            XCTAssertEqual(route(identifier: identifier, userInfo: [:]).route, .appBanner(banner), identifier)
        }
    }

    // MARK: - Alarms

    func testMalformedAlarmPayload_isSuppressed_andLogsTheErrorLine() {
        var userInfo = validAlarmUserInfo()
        userInfo[AlarmNotificationPayload.Key.snoozeMinutes] = 0 // out of range

        let result = route(identifier: UUID().uuidString, userInfo: userInfo)

        XCTAssertEqual(result.route, .invalidAlarmPayload)
        XCTAssertEqual(result.route.presentationOptions, [])
        guard let line = result.lines.first(where: { $0.message.contains(Self.invalidPayloadMarker) }) else {
            return XCTFail("a corrupt alarm must still be reported; the sink saw \(result.lines.map(\.message))")
        }
        XCTAssertEqual(line.level, .error)
        XCTAssertEqual(line.category, .appDelegate)
        XCTAssertFalse(
            line.message.contains(userInfo[AlarmNotificationPayload.Key.alarmID] as? String ?? "?"),
            "the line is public; it must not carry the alarm UUID: \(line.message)"
        )
    }

    /// An empty payload under an identifier that is no banner is still read as
    /// a broken alarm — the pre-#842 verdict for anything unrecognised.
    func testUnrecognisedNotification_keepsTheInvalidAlarmVerdict() {
        let result = route(identifier: "something_else_\(UUID().uuidString)", userInfo: [:])

        XCTAssertEqual(result.route, .invalidAlarmPayload)
        XCTAssertEqual(result.route.presentationOptions, [])
        XCTAssertTrue(result.lines.contains { $0.level == .error && $0.message.contains(Self.invalidPayloadMarker) })
    }

    /// The decode runs first: a valid alarm payload is an alarm even under an
    /// identifier that happens to carry a banner prefix.
    func testValidAlarmPayload_isAnAlarm_evenUnderABannerPrefix() throws {
        let userInfo = validAlarmUserInfo()
        let payload = try XCTUnwrap(AlarmNotificationPayload(userInfo: userInfo))

        let result = route(identifier: AppBannerNotification.rescheduleFailed.makeIdentifier(), userInfo: userInfo)

        XCTAssertEqual(result.route, .alarm(payload))
        XCTAssertEqual(result.route.presentationOptions, [])
        XCTAssertTrue(result.lines.isEmpty, "the alarm path logs nothing here: \(result.lines.map(\.message))")
    }
}
