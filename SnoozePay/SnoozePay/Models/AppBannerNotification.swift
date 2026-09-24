import Foundation

/// The local notifications this app posts that are NOT alarms: banners that
/// carry no ``AlarmNotificationPayload`` and exist to be read (#842).
///
/// The raw value is the request-identifier prefix. Each builder mints its
/// identifier through ``makeIdentifier()``, and the notification delegate
/// recognises a banner through ``init(identifier:)``
/// (`AppDelegate.routeNotification(_:site:)`), so both sides read the same list.
///
/// ⚠️ That is a convention, not something the compiler enforces. A new banner
/// posted with a literal identifier still compiles, and then fails exactly the
/// way all four did before #842: `willPresent` suppresses it in the foreground
/// (`[]`), a tap on it stops a ringing alarm, and the only trace is an
/// `invalid alarm payload` `.error` line pointing at the alarm path. Add the
/// case here and build the identifier with ``makeIdentifier()``.
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
