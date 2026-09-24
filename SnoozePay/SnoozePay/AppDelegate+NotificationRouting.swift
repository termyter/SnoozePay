//
//  AppDelegate+NotificationRouting.swift
//  SnoozePay
//

import UserNotifications
import os

/// How `willPresent` and a default-action tap in `didReceive` tell an alarm
/// from one of the app's own banners (#842).
///
/// Both used to decode an alarm payload and treat every failure as a corrupt
/// alarm. The app's banners carry no alarm payload, so in the foreground they
/// were suppressed with `[]` and logged as `invalid alarm payload`, and a tap
/// on one called `stopAlarmSound()` — silencing whatever alarm was ringing.
///
/// Everything here is static and takes a `UNNotificationRequest`, which a test
/// can build, rather than a `UNNotification` or `UNNotificationResponse`, which
/// it cannot. The side effects arrive as closures so a test can see which one
/// ran.
extension AppDelegate {

    /// What a notification is, as far as the delegate callbacks care.
    enum NotificationRoute: Equatable {
        /// A decodable alarm.
        case alarm(AlarmNotificationPayload)
        /// One of the app's own non-alarm banners.
        case appBanner(AppBannerNotification)
        /// Neither — treated as an alarm whose payload failed to decode.
        case invalidAlarmPayload
    }

    /// Classifies `request` and writes the line that says which way it went,
    /// prefixed with `site` (`willPresent`, `default action`).
    ///
    /// The alarm decode runs FIRST, so a notification carrying a valid alarm
    /// payload is an alarm whatever its identifier. Only what fails to decode
    /// is checked against ``AppBannerNotification``; anything that matches no
    /// banner keeps the pre-#842 verdict — a corrupt alarm, `.error`.
    ///
    /// Main-actor like the rest of `AppDelegate`, which is what
    /// ``AppLogger/emit(_:_:_:)`` requires.
    static func routeNotification(_ request: UNNotificationRequest, site: String) -> NotificationRoute {
        let userInfo = request.content.userInfo
        if let payload = AlarmNotificationPayload(userInfo: userInfo) {
            return .alarm(payload)
        }
        if let banner = AppBannerNotification(identifier: request.identifier) {
            AppLogger.emit(.appDelegate, .info, "\(site): app banner \(banner)")
            return .appBanner(banner)
        }
        // Keys only, not values: this line goes out `.public`, and the values
        // carry the alarm UUID. The keys are enough to tell a schema drift
        // from a foreign notification.
        let keys = userInfo.keys.map { "\($0)" }.sorted().joined(separator: ", ")
        AppLogger.emit(.appDelegate, .error, "\(site): invalid alarm payload, userInfo keys [\(keys)]")
        return .invalidAlarmPayload
    }

    /// Everything `willPresent` decides. `startAlarm` runs for a decodable
    /// alarm, before the options are returned.
    ///
    /// - alarm: `[]` — its presentation is the firing screen, and a system
    ///   banner on top would duplicate it;
    /// - app banner: `[.banner, .sound, .list]` — it exists to be read;
    /// - anything else: `[]`, as before #842. No audio either: the firing
    ///   screen will never be presented, so nothing could stop it.
    static func foregroundPresentationOptions(
        for request: UNNotificationRequest,
        startAlarm: (AlarmNotificationPayload) -> Void
    ) -> UNNotificationPresentationOptions {
        switch routeNotification(request, site: "willPresent") {
        case let .alarm(payload):
            startAlarm(payload)
            return []
        case .appBanner:
            return [.banner, .sound, .list]
        case .invalidAlarmPayload:
            return []
        }
    }

    /// Everything a default-action tap (the user tapped the notification body)
    /// decides.
    ///
    /// - alarm: present the firing screen, which owns the audio from there;
    /// - app banner: nothing beyond opening the app. In particular NOT
    ///   `stopAlarmSound` — since #842 these banners show in the foreground,
    ///   so one can be tapped while an alarm rings, and stopping it here would
    ///   silence that alarm with no dismiss and no charge;
    /// - anything else: stop the sound, as before #842 — a corrupt alarm has
    ///   no firing screen that could stop it later.
    static func handleDefaultTap(
        on request: UNNotificationRequest,
        presentAlarm: (AlarmNotificationPayload) -> Void,
        stopAlarmSound: () -> Void
    ) {
        switch routeNotification(request, site: "default action") {
        case let .alarm(payload):
            presentAlarm(payload)
        case .appBanner:
            break
        case .invalidAlarmPayload:
            stopAlarmSound()
        }
    }
}
