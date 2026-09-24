import Foundation
import UserNotifications

/// The local notifications this app posts that are NOT alarms: banners that
/// carry no ``AlarmNotificationPayload`` and exist to be read (#842).
///
/// The raw value is the request-identifier prefix. Every builder posts through
/// `LocalNotificationPosting.postAppBanner(_:content:trigger:onFailure:)`,
/// which mints the identifier with ``makeIdentifier()``. The notification
/// delegate recognises a banner through ``init(identifier:)``
/// (`AppDelegate.routeNotification(_:site:)`), so both sides read the same list.
///
/// ⚠️ The compiler does not enforce that. A new banner posted with a literal
/// identifier still compiles, and then fails exactly the way all four did
/// before #842: `willPresent` suppresses it in the foreground (`[]`), a tap on
/// it stops a ringing alarm, and the only trace is an `invalid alarm payload`
/// `.error` line pointing at the alarm path. `BannerIdentifierSourceScanTests`
/// holds the line instead (#844): it fails on any `UNNotificationRequest` in
/// app code whose identifier is not minted by ``makeIdentifier()``. Add the
/// case here and post through `postAppBanner`.
///
/// The strings are the ones the builders used before #842, kept verbatim: a
/// banner scheduled by the previous build and delivered after an update still
/// matches.
/// `ForegroundNotificationRouteTests.testPreviousBuildsBannerIdentifiers_stillRouteAsBanners`
/// pins them.
enum AppBannerNotification: String, CaseIterable {
    /// `AppDelegate.postResumeAudioFailedBanner` — the alarm is ringing
    /// silently because the audio session could not be reclaimed (#405).
    case resumeAudioFailed = "resume_audio_failed_"
    /// `AppDelegate.postRescheduleFailedBanner` — alarms failed to re-arm after
    /// a clock/timezone/permission change (#442).
    case rescheduleFailed = "reschedule_failed_"
    /// `AppDelegate.postSnoozeScheduleFailedBanner` — the snooze re-fire could
    /// not be scheduled.
    case snoozeScheduleFailed = "snooze_schedule_failed_"
    /// `StoreKitService.postLocalFeedbackNotification` — deferred purchase
    /// feedback when no screen is mounted to show it (#45).
    case purchaseFeedback = "snoozepay.storekit.feedback."

    /// A fresh, unique request identifier for one posting of this banner.
    func makeIdentifier() -> String {
        rawValue + UUID().uuidString
    }

    /// The banner a request identifier belongs to, or `nil` for anything else
    /// (alarms included). This takes the FIRST case that matches, so it relies
    /// on no prefix being a prefix of another —
    /// `ForegroundNotificationRouteTests.testNoBannerPrefixIsAPrefixOfAnother`
    /// checks that.
    init?(identifier: String) {
        guard let match = Self.allCases.first(where: { identifier.hasPrefix($0.rawValue) }) else {
            return nil
        }
        self = match
    }
}

/// Minimal seam for posting a local notification, so a test can see the
/// request a banner builder hands over without touching the process-wide
/// `UNUserNotificationCenter` singleton. Production uses
/// `UNUserNotificationCenter.current()`; tests inject `LocalNotificationPosterSpy`.
/// Introduced for the deferred-purchase fallback (#45); the `AppDelegate`
/// banners post through it too since #844.
@MainActor
protocol LocalNotificationPosting {
    /// Adds `request`, then calls `completion` on the main actor with the error
    /// the notification center reported, or `nil`.
    func add(_ request: UNNotificationRequest, completion: @escaping @MainActor @Sendable (Error?) -> Void)
}

extension UNUserNotificationCenter: LocalNotificationPosting {
    /// The center calls back on a queue of its own. This hops to the main
    /// actor, because the logger's test-visible `emit` seam is main-thread
    /// only, and a failure line written through it is one a test can read back.
    nonisolated func add(
        _ request: UNNotificationRequest,
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    ) {
        add(request, withCompletionHandler: { error in
            Task { @MainActor in completion(error) }
        })
    }
}

extension LocalNotificationPosting {
    /// The one place app code builds a `UNNotificationRequest` (#844). The
    /// identifier is minted from `banner`, so `willPresent` shows the banner in
    /// the foreground and a tap on it leaves a ringing alarm alone (#842).
    /// `onFailure` runs on the main actor when the center refuses the request,
    /// usually because notification permission was revoked.
    func postAppBanner(
        _ banner: AppBannerNotification,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger?,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) {
        let request = UNNotificationRequest(
            identifier: banner.makeIdentifier(),
            content: content,
            trigger: trigger
        )
        add(request) { error in
            if let error { onFailure(error) }
        }
    }
}
