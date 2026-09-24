import XCTest
import UserNotifications
@testable import SnoozePay

/// Each `AppDelegate` banner builder posts under its OWN
/// `AppBannerNotification` case (#844).
///
/// #842 taught `willPresent` to recognise the app's banners by identifier
/// prefix, and `ForegroundNotificationRouteTests` pins that routing. What it
/// could not see is the builders themselves: they were `private` and wrote
/// straight to `UNUserNotificationCenter.current()`, so a builder that minted
/// the wrong case, or a literal, stayed green. Here each builder posts into
/// `LocalNotificationPosterSpy` and the request it handed over is classified
/// the way the delegate would classify it.
///
/// The copy, the time-sensitive level and the one-second trigger are pinned
/// alongside, because #844 moved the posting and was not meant to move any of
/// them.
@MainActor
final class AppBannerPostingTests: XCTestCase {

    /// The one request `post` handed to the poster.
    private func postedRequest(
        _ post: (LocalNotificationPosting) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> UNNotificationRequest {
        let poster = LocalNotificationPosterSpy()
        post(poster)
        XCTAssertEqual(poster.requests.count, 1, "a builder posts exactly one request", file: file, line: line)
        return try XCTUnwrap(poster.requests.first, file: file, line: line)
    }

    /// Time-sensitive, with a sound, delivered one second out and once — what
    /// all three builders set before #844.
    private func assertSharedShape(
        _ request: UNNotificationRequest,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(request.content.interruptionLevel, .timeSensitive, file: file, line: line)
        // `UNNotificationSound` exposes nothing to compare against `.default`.
        XCTAssertNotNil(request.content.sound, file: file, line: line)
        let trigger = try XCTUnwrap(
            request.trigger as? UNTimeIntervalNotificationTrigger, file: file, line: line
        )
        XCTAssertEqual(trigger.timeInterval, 1, file: file, line: line)
        XCTAssertFalse(trigger.repeats, file: file, line: line)
    }

    func testResumeAudioFailedBanner_postsUnderItsOwnCase() throws {
        let request = try postedRequest { AppDelegate.postResumeAudioFailedBanner(poster: $0) }

        XCTAssertEqual(AppBannerNotification(identifier: request.identifier), .resumeAudioFailed)
        XCTAssertEqual(request.content.title, "Будильник звучит беззвучно")
        XCTAssertEqual(
            request.content.body,
            "Не удалось включить звук — откройте приложение и выключите будильник вручную."
        )
        try assertSharedShape(request)
    }

    func testRescheduleFailedBanner_postsUnderItsOwnCase() throws {
        let request = try postedRequest { AppDelegate.postRescheduleFailedBanner(failedCount: 3, poster: $0) }

        XCTAssertEqual(AppBannerNotification(identifier: request.identifier), .rescheduleFailed)
        XCTAssertEqual(request.content.title, "Будильники не перевзведены")
        XCTAssertEqual(
            request.content.body,
            "Не удалось перепланировать будильники (3) — "
                + "откройте приложение и проверьте разрешения на уведомления."
        )
        try assertSharedShape(request)
    }

    /// Both arms of the refund branch, because each writes its own body.
    func testSnoozeScheduleFailedBanner_postsUnderItsOwnCase() throws {
        let error = AlarmScheduler.SchedulingError.system(message: "limit")
        let detail = try XCTUnwrap(error.errorDescription)

        let refunded = try postedRequest {
            AppDelegate.postSnoozeScheduleFailedBanner(error: error, refundLanded: true, poster: $0)
        }
        let charged = try postedRequest {
            AppDelegate.postSnoozeScheduleFailedBanner(error: error, refundLanded: false, poster: $0)
        }

        for request in [refunded, charged] {
            XCTAssertEqual(AppBannerNotification(identifier: request.identifier), .snoozeScheduleFailed)
            XCTAssertEqual(request.content.title, "Откладывание не запланировано")
            try assertSharedShape(request)
        }
        XCTAssertEqual(refunded.content.body, "Установите запасной — \(detail)")
        XCTAssertEqual(
            charged.content.body,
            "Установите запасной. Списание не возвращено — обратитесь в поддержку. \(detail)"
        )
    }

    /// Two postings of one banner are two notifications, not one replacing the
    /// other: the center treats a repeated identifier as an update.
    func testEachPostingMintsAFreshIdentifier() throws {
        let first = try postedRequest { AppDelegate.postResumeAudioFailedBanner(poster: $0) }
        let second = try postedRequest { AppDelegate.postResumeAudioFailedBanner(poster: $0) }

        XCTAssertNotEqual(first.identifier, second.identifier)
    }
}
