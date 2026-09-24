import Foundation

/// The local notifications this app posts that are NOT alarms: banners that
/// carry no ``AlarmNotificationPayload`` and exist to be read (#842).
///
/// The raw value is the request-identifier prefix. Each builder mints its
/// identifier through ``makeIdentifier()``, and `willPresent` recognises a
/// banner through ``init(identifier:)``, so both sides read the same list. A
/// banner added without a case here has no identifier to build with, which is
/// the point: before #842 the list lived only in the builders, and `willPresent`
/// treated every one of these as a corrupt alarm — `[]` presentation options
/// (the banner never showed while the app was in the foreground) and an
/// `invalid alarm payload` error that sent diagnosis down the alarm path.
///
/// The strings are the ones the builders used before #842, kept verbatim: a
/// banner scheduled by the previous build and delivered after an update still
/// matches. `AppBannerNotificationTests` pins them.
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
    /// (alarms included). No prefix is a prefix of another, so at most one
    /// case can match.
    init?(identifier: String) {
        guard let match = Self.allCases.first(where: { identifier.hasPrefix($0.rawValue) }) else {
            return nil
        }
        self = match
    }
}
