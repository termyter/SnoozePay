import Foundation
import UIKit
import UserNotifications
import os

/// Can the app actually ring an alarm right now? (#428)
///
/// This is THE single source of truth for that question — no screen should
/// re-derive it by hand-rolling an "AlarmKit OR notifications" condition.
/// Everything user-facing (the alarms-list banner, the create / enable gate)
/// reads this enum, so when the notification fallback is retired in favour of
/// AlarmKit-only scheduling the whole guard collapses by editing exactly one
/// function — `SystemAlarmBackendProbe.probe(completion:)` — down to
/// `alarmKitAuthorized() ? .available : .unavailable`.
///
/// Four cases, deliberately: "we haven't asked yet" and "we asked and couldn't
/// tell" must never be flattened into "everything is fine" (that flattening is
/// exactly how the original silent-failure bug reads to the user).
enum AlarmBackendAvailability: Equatable {

    /// No probe has answered yet (app just launched). Claim nothing: no banner,
    /// no gate.
    case unresolved

    /// At least one backend can ring an alarm.
    case available

    /// Every backend is unauthorized — a saved alarm will NOT ring. Drives the
    /// proactive banner and gates the create / enable CTAs.
    case unavailable

    /// The probe answered with something we can't interpret (a future
    /// `UNAuthorizationStatus` case). We surface a "couldn't verify" banner
    /// rather than pretending the alarms are armed — but we do NOT gate the
    /// CTAs, because the failure is ours, not the user's.
    case indeterminate
}

// MARK: - Probe

/// Seam over the two OS authorization queries. Injectable so the availability
/// logic is unit-testable without `UNUserNotificationCenter` / AlarmKit —
/// deliberately NOT bolted onto `NotificationScheduling`, whose 6+ test doubles
/// would all need updating for a status query none of them care about.
protocol AlarmBackendProbing {
    /// Resolves the current availability. The completion may fire on any
    /// queue; `AlarmBackendMonitor` marshals to main.
    func probe(completion: @escaping (AlarmBackendAvailability) -> Void)
}

/// Production probe: AlarmKit grant first (synchronous), notification
/// authorization second.
struct SystemAlarmBackendProbe: AlarmBackendProbing {

    private let alarmKitAuthorized: () -> Bool
    private let notificationStatus: (@escaping (UNAuthorizationStatus) -> Void) -> Void

    init(
        alarmKitAuthorized: @escaping () -> Bool = { AlarmScheduler.shared.usesAlarmKit },
        notificationStatus: @escaping (@escaping (UNAuthorizationStatus) -> Void) -> Void = { completion in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                completion(settings.authorizationStatus)
            }
        }
    ) {
        self.alarmKitAuthorized = alarmKitAuthorized
        self.notificationStatus = notificationStatus
    }

    func probe(completion: @escaping (AlarmBackendAvailability) -> Void) {
        // Strategy A. `usesAlarmKit` already folds in "iOS 26+, backend wired,
        // user authorized" — the deployment target is 26.2, so in practice this
        // is purely the authorization question.
        if alarmKitAuthorized() {
            completion(.available)
            return
        }
        // Strategy B (notification fallback). DELETE THIS BRANCH when the
        // fallback is retired — the AlarmKit check above is then the whole
        // answer and this type stays synchronous.
        notificationStatus { status in
            completion(Self.availability(forNotificationStatus: status))
        }
    }

    /// Maps a notification authorization status onto "can this ring an alarm".
    ///
    /// Only `.authorized` counts. `.provisional` delivers quietly straight to
    /// Notification Center — it cannot wake a sleeping user, so treating it as
    /// a working alarm backend would recreate the silent failure this guard
    /// exists to prevent. `.ephemeral` is App-Clip-only and equally unable to
    /// carry an alarm. `.notDetermined` is not a backend *yet* — the user still
    /// has to grant, which is precisely what the banner asks for.
    static func availability(forNotificationStatus status: UNAuthorizationStatus) -> AlarmBackendAvailability {
        switch status {
        case .authorized:
            return .available
        case .denied, .notDetermined, .provisional, .ephemeral:
            return .unavailable
        @unknown default:
            // A status this build doesn't know. Refusing to guess is the point:
            // reporting `.available` here would be the exact "swallowed the
            // error and claimed everything is fine" behaviour we're fixing.
            AppLogger.scheduler.error(
                """
                unknown UNAuthorizationStatus raw=\(status.rawValue, privacy: .public); \
                alarm backend availability indeterminate
                """
            )
            return .indeterminate
        }
    }
}

// MARK: - Monitor

/// Owns the current `AlarmBackendAvailability` and keeps it fresh.
///
/// Authorization changes happen OUTSIDE the app (iOS Settings), so a value
/// resolved at cold launch goes stale the moment the user leaves. The monitor
/// re-probes on every foreground activation, which is the return path from
/// Settings — that's what makes the banner honest without a relaunch (#428).
final class AlarmBackendMonitor {

    /// Exposed so tests can drive the foreground path without importing UIKit
    /// semantics of their own.
    static let foregroundNotificationName = UIApplication.didBecomeActiveNotification

    private let probe: AlarmBackendProbing
    private let notificationCenter: NotificationCenter
    private var foregroundObserver: NSObjectProtocol?

    /// Latest resolved availability. Starts `.unresolved` — never `.available`,
    /// so an un-probed app can't render a false all-clear.
    private(set) var availability: AlarmBackendAvailability = .unresolved

    /// Fired on the main queue whenever `availability` actually changes.
    var onChange: ((AlarmBackendAvailability) -> Void)?

    init(
        probe: AlarmBackendProbing = SystemAlarmBackendProbe(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.probe = probe
        self.notificationCenter = notificationCenter
        foregroundObserver = notificationCenter.addObserver(
            forName: Self.foregroundNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let token = foregroundObserver {
            notificationCenter.removeObserver(token)
        }
    }

    /// Re-query the OS. Safe to call repeatedly — `onChange` only fires on a
    /// real transition.
    func refresh() {
        probe.probe { [weak self] resolved in
            // `getNotificationSettings` answers on an arbitrary queue, so hop
            // to main before touching UI-facing state. A probe that already
            // resolved on main (AlarmKit fast path, test stubs) stays
            // synchronous so callers observe the new value immediately.
            if Thread.isMainThread {
                self?.apply(resolved)
            } else {
                DispatchQueue.main.async { self?.apply(resolved) }
            }
        }
    }

    private func apply(_ resolved: AlarmBackendAvailability) {
        guard resolved != availability else { return }
        let previous = String(describing: availability)
        let next = String(describing: resolved)
        AppLogger.scheduler.notice(
            "alarm backend availability \(previous, privacy: .public) → \(next, privacy: .public)"
        )
        availability = resolved
        onChange?(resolved)
    }
}

// MARK: - User-facing copy

/// Banner / alert copy for a non-ringing state. `nil` init means "nothing to
/// warn about", so call sites read as `if let warning = ...`.
struct AlarmBackendWarning: Equatable {

    let title: String
    let message: String
    let actionTitle: String

    /// `true` when the state is severe enough to gate the create / enable
    /// CTAs. We gate on "no backend at all" only — an indeterminate probe is
    /// our failure, and blocking the user over it would be worse than the bug.
    let gatesAlarmCreation: Bool

    init?(availability: AlarmBackendAvailability) {
        switch availability {
        case .unresolved, .available:
            return nil
        case .unavailable:
            title = "Будильники не зазвонят"
            message = "Разрешение на будильники и уведомления выключено. "
                + "Включите его в Настройках — иначе созданные будильники не сработают."
            actionTitle = "Открыть Настройки"
            gatesAlarmCreation = true
        case .indeterminate:
            title = "Не удалось проверить разрешения"
            message = "Приложение не смогло узнать, разрешены ли будильники и уведомления. "
                + "Проверьте их в Настройках — без разрешения будильники не сработают."
            actionTitle = "Открыть Настройки"
            gatesAlarmCreation = false
        }
    }
}
