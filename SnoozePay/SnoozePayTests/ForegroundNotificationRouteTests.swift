import XCTest
import os
import UserNotifications
@testable import SnoozePay

/// The notification delegate used to treat every notification as an alarm: the
/// app's own banners (resume-audio-failed, reschedule-failed,
/// snooze-schedule-failed, deferred purchase feedback) carry no alarm payload,
/// so in the foreground each one got `[]` — never shown — plus an
/// `invalid alarm payload` error line, and a tap on one stopped whatever alarm
/// was ringing (#842).
///
/// Driven through the static seams in `AppDelegate+NotificationRouting.swift`,
/// which take a `UNNotificationRequest` — constructible in a test, unlike the
/// `UNNotification` / `UNNotificationResponse` the delegate callbacks receive.
/// `willPresent` and the default-action branch of `didReceive` are one call
/// each into those seams. The side effects come in as closures, so each test
/// also sees which of them ran.
///
/// The routing is synchronous and emits on the calling thread, so the sink
/// window below sees every line it produces without a drain; the filter on the
/// call-site prefixes keeps the assertions to this code's own lines.
@MainActor
final class ForegroundNotificationRouteTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    private static let invalidPayloadMarker = "invalid alarm payload"

    private func request(identifier: String, userInfo: [AnyHashable: Any] = [:]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    /// Runs `body` with a sink installed and returns its result plus the lines
    /// the routing wrote.
    private func capturingLines<T>(_ body: () -> T) -> (result: T, lines: [Line]) {
        var lines: [Line] = []
        let result = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: body)
        let own = lines.filter { $0.message.hasPrefix("willPresent:") || $0.message.hasPrefix("default action:") }
        return (result, own)
    }

    /// `willPresent`, with a record of whether it started the alarm.
    private func present(
        _ request: UNNotificationRequest
    ) -> (options: UNNotificationPresentationOptions, started: [AlarmNotificationPayload], lines: [Line]) {
        var started: [AlarmNotificationPayload] = []
        let outcome = capturingLines {
            AppDelegate.foregroundPresentationOptions(for: request) { started.append($0) }
        }
        return (outcome.result, started, outcome.lines)
    }

    /// A default-action tap, with a record of which side effect ran.
    private func tap(
        _ request: UNNotificationRequest
    ) -> (presented: [AlarmNotificationPayload], stoppedSound: Int, lines: [Line]) {
        var presented: [AlarmNotificationPayload] = []
        var stoppedSound = 0
        let outcome = capturingLines {
            AppDelegate.handleDefaultTap(
                on: request,
                presentAlarm: { presented.append($0) },
                stopAlarmSound: { stoppedSound += 1 }
            )
        }
        return (presented, stoppedSound, outcome.lines)
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

    private func messages(_ lines: [Line]) -> [String] {
        lines.map(\.message)
    }

    // MARK: - willPresent: app banners

    func testEveryAppBanner_isPresentedAsABanner_withoutAnInvalidPayloadLine() {
        for banner in AppBannerNotification.allCases {
            let result = present(request(identifier: banner.makeIdentifier()))

            XCTAssertEqual(
                result.options, [.banner, .sound, .list],
                "\(banner) must be shown in the foreground, not suppressed"
            )
            XCTAssertTrue(result.started.isEmpty, "\(banner) is not an alarm and must not ring")
            XCTAssertFalse(
                result.lines.contains { $0.message.contains(Self.invalidPayloadMarker) },
                "\(banner) is not a corrupt alarm; the sink saw \(messages(result.lines))"
            )
            XCTAssertEqual(
                result.lines.map(\.level), [.info],
                "exactly one info line per banner; the sink saw \(messages(result.lines))"
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
            XCTAssertEqual(AppBannerNotification(identifier: identifier), banner, identifier)
            XCTAssertEqual(present(request(identifier: identifier)).options, [.banner, .sound, .list], identifier)
        }
    }

    /// `init?(identifier:)` takes the first case whose prefix matches, so two
    /// prefixes where one starts with the other would route by declaration
    /// order instead of by identifier.
    func testNoBannerPrefixIsAPrefixOfAnother() {
        for lhs in AppBannerNotification.allCases {
            for rhs in AppBannerNotification.allCases where lhs != rhs {
                XCTAssertFalse(
                    lhs.rawValue.hasPrefix(rhs.rawValue),
                    "\(lhs) (\(lhs.rawValue)) starts with \(rhs) (\(rhs.rawValue))"
                )
            }
        }
    }

    // MARK: - willPresent: alarms

    func testMalformedAlarmPayload_isSuppressed_andLogsTheErrorLine() {
        var userInfo = validAlarmUserInfo()
        userInfo[AlarmNotificationPayload.Key.snoozeMinutes] = 0 // out of range

        let result = present(request(identifier: UUID().uuidString, userInfo: userInfo))

        XCTAssertEqual(result.options, [])
        XCTAssertTrue(result.started.isEmpty, "a payload that fails to decode must not start audio")
        guard let line = result.lines.first(where: { $0.message.contains(Self.invalidPayloadMarker) }) else {
            return XCTFail("a corrupt alarm must still be reported; the sink saw \(messages(result.lines))")
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
        let result = present(request(identifier: "something_else_\(UUID().uuidString)"))

        XCTAssertEqual(result.options, [])
        XCTAssertTrue(result.lines.contains { $0.level == .error && $0.message.contains(Self.invalidPayloadMarker) })
    }

    /// The decode runs first: a valid alarm payload is an alarm even under an
    /// identifier that happens to carry a banner prefix.
    func testValidAlarmPayload_startsTheAlarm_evenUnderABannerPrefix() throws {
        let userInfo = validAlarmUserInfo()
        let payload = try XCTUnwrap(AlarmNotificationPayload(userInfo: userInfo))

        let result = present(
            request(identifier: AppBannerNotification.rescheduleFailed.makeIdentifier(), userInfo: userInfo)
        )

        XCTAssertEqual(result.started, [payload])
        XCTAssertEqual(result.options, [], "the firing screen is the presentation; no system banner on top")
        XCTAssertTrue(result.lines.isEmpty, "the alarm path logs nothing here: \(messages(result.lines))")
    }

    // MARK: - didReceive: default-action tap

    /// Since #842 these banners show while the app is open, so one can be
    /// tapped while an alarm rings. Stopping the sound there would silence the
    /// alarm with no dismiss and no charge.
    func testTappingAnAppBanner_doesNotStopTheAlarmSound() {
        for banner in AppBannerNotification.allCases {
            let result = tap(request(identifier: banner.makeIdentifier()))

            XCTAssertEqual(result.stoppedSound, 0, "a tap on \(banner) must not silence a ringing alarm")
            XCTAssertTrue(result.presented.isEmpty, "\(banner) has no firing screen")
            XCTAssertEqual(
                result.lines.map(\.level), [.info],
                "\(banner) is not a corrupt alarm; the sink saw \(messages(result.lines))"
            )
        }
    }

    func testTappingAMalformedAlarm_stillStopsTheSound_andLogsTheErrorLine() {
        var userInfo = validAlarmUserInfo()
        userInfo[AlarmNotificationPayload.Key.snoozeMinutes] = 0

        let result = tap(request(identifier: UUID().uuidString, userInfo: userInfo))

        XCTAssertEqual(result.stoppedSound, 1)
        XCTAssertTrue(result.presented.isEmpty)
        XCTAssertTrue(
            result.lines.contains {
                $0.level == .error && $0.message.hasPrefix("default action:")
                    && $0.message.contains(Self.invalidPayloadMarker)
            },
            "the sink saw \(messages(result.lines))"
        )
    }

    func testTappingAValidAlarm_presentsTheFiringScreen() throws {
        let userInfo = validAlarmUserInfo()
        let payload = try XCTUnwrap(AlarmNotificationPayload(userInfo: userInfo))

        let result = tap(request(identifier: UUID().uuidString, userInfo: userInfo))

        XCTAssertEqual(result.presented, [payload])
        XCTAssertEqual(result.stoppedSound, 0)
    }
}
