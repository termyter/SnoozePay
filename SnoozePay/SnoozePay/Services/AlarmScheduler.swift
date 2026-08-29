import Foundation
import UserNotifications
import os

/// Subset of `UNUserNotificationCenter` the scheduler depends on. Extracted as a
/// protocol so unit tests can substitute a mock and verify error-propagation
/// paths (issue #118) — the real `UNUserNotificationCenter.current()` is a
/// process-wide singleton whose `add(_:)` failure modes (permission revoked
/// mid-session, malformed trigger, 64-pending limit) cannot otherwise be
/// reproduced deterministically.
///
/// Since #472 the app never SCHEDULES a notification; what is left of this seam
/// serves the legacy sweep in `cancel(_:)`, which removes alarm notifications
/// left pending by a pre-#472 build.
protocol NotificationScheduling: AnyObject {
    // Sendable closures match `UNUserNotificationCenter`'s post-Swift-6
    // signature. Without them the implicit conformance is a warning
    // today and an error under Swift 6 strict concurrency.
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completion: (@Sendable (Error?) -> Void)?
    )
    func getPendingNotificationRequests(
        completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void
    )
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func getDeliveredNotifications(
        completionHandler: @escaping @Sendable ([UNNotification]) -> Void
    )
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func removeAllPendingNotificationRequests()
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )
}

extension UNUserNotificationCenter: NotificationScheduling {}

/// Subset of `AlarmScheduler` that `AlarmRepository` depends on. Extracted as
/// a protocol so unit tests covering repository → scheduler error propagation
/// (issue #129 — toggle on alarm with denied permission must surface the
/// failure to the VM instead of silently flipping the switch) can substitute a
/// stub without bringing up `UNUserNotificationCenter`.
protocol AlarmScheduling: AnyObject {
    func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?)
    func cancel(_ alarmID: UUID)
}

/// Schedules and cancels alarms through AlarmKit — the ONLY backend
/// (`docs/SPEC.md` §3.2.1, #472).
///
/// An AlarmKit alarm is a real system alarm: it rings continuously, pierces
/// silent mode and Focus/DND, and shows a full-screen lock-screen alert — like
/// Clock.app — without the (unapproved) Critical Alerts entitlement. Stop /
/// snooze buttons on the system alert route back through `AlarmKitActionRouter`.
///
/// **There is no notification fallback (#472).** Until then a denied or failed
/// AlarmKit schedule silently degraded to a `.timeSensitive` notification, which
/// pings once and cannot wake a sleeping user. Holding two backends at once made
/// "is this alarm armed?" ambiguous and produced #456, #459 and #460 in a row.
/// Now the answer is single-valued: either AlarmKit armed the alarm, or
/// `schedule` fails with a typed error and the UI must say so. `AlarmRepository`
/// surfaces that failure to the caller, and the create / enable CTAs are gated
/// upstream by `AlarmBackendAvailability`.
final class AlarmScheduler: AlarmScheduling {

    static let shared = AlarmScheduler()

    /// Errors surfaced to UI callers so the user sees a real explanation
    /// instead of a fake "Будильник создан" toast on an alarm that never
    /// registered (issue #118).
    enum SchedulingError: LocalizedError, Equatable {
        /// AlarmKit rejected the schedule — a revoked authorization, the
        /// per-app alarm limit, or a backend error.
        case system(message: String)
        /// No AlarmKit authorization, so nothing can be armed at all. Distinct
        /// from `.system`: nothing failed, we refused. Saving an alarm anyway
        /// would leave the user with a switch that reads "on" and an alarm that
        /// never rings — the worst outcome of the two (#472).
        case backendUnavailable

        var errorDescription: String? {
            switch self {
            case .system(let message):
                return "Не удалось запланировать будильник: \(message). "
                     + "Попробуйте ещё раз или удалите старые будильники."
            case .backendUnavailable:
                return "Приложению не разрешено ставить будильники, "
                     + "поэтому будильник не зазвонит. Разрешите будильники в Настройках."
            }
        }
        // Equatable synthesis is automatic — `String` associated values
        // conform out of the box.
    }

    private let notificationCenter: NotificationScheduling

    /// The AlarmKit backend. Non-nil in production; injectable (and omittable)
    /// in tests so the "no backend at all" refusal can be exercised.
    private let alarmKitScheduler: AlarmKitScheduling?

    /// Whether AlarmKit can arm an alarm right now — a backend is wired AND the
    /// user has authorized it. `internal` (#383) so the firing screen can mirror
    /// the scheduler: the system owns the alarm sound and the snooze re-fires as
    /// a system alarm, so the in-app screen must NOT start its own
    /// `AudioService` and must dismiss after a snooze.
    ///
    /// Since #472 this is also the answer to "will a saved alarm ring at all".
    var usesAlarmKit: Bool {
        guard let alarmKitScheduler else { return false }
        return alarmKitScheduler.isAuthorized
    }

    /// Full AlarmKit authorization state for `SystemAlarmBackendProbe`. With no
    /// backend wired we answer `.denied` rather than `.notDetermined`: offering
    /// an in-app prompt that cannot possibly resolve would be worse than
    /// pointing at Settings.
    var alarmKitAuthorization: AlarmKitAuthorization {
        alarmKitScheduler?.authorization ?? .denied
    }

    // Notification category and action IDs. Legacy (#472): no new alarm
    // notification is ever scheduled, but a notification left pending by an
    // older build still routes its actions through this category.
    private let categoryID = "ALARM_CATEGORY"
    private let dismissActionID = "DISMISS_ACTION"
    private let snoozeActionID = "SNOOZE_ACTION"

    private init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        self.alarmKitScheduler = AlarmKitScheduler()
    }

    /// Test-only initializer that swaps the notification-center seam and,
    /// optionally, the AlarmKit backend. Production code MUST use
    /// `AlarmScheduler.shared` (see `singleton`). Passing an `alarmKit` mock
    /// lets tests drive the scheduling path with a stub backend; passing `nil`
    /// models "no backend authorized", which must refuse rather than schedule.
    init(
        notificationCenter: NotificationScheduling,
        alarmKit: AlarmKitScheduling? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.alarmKitScheduler = alarmKit
    }

    // MARK: - Permission

    /// Request AlarmKit authorization. No-op when no backend is wired.
    /// Completes with the resolved grant.
    func requestAlarmKitAuthorization(completion: @escaping (Bool) -> Void) {
        guard let alarmKitScheduler else {
            completion(false)
            return
        }
        alarmKitScheduler.requestAuthorization(completion: completion)
    }

    /// Drive the OS permission prompt for the alarm backend and report the
    /// grant on the main queue.
    ///
    /// Before #472 this also requested notification authorization, so the
    /// `.timeSensitive` fallback would stay available and the reported grant was
    /// the NOTIFICATION one. Both are gone: notifications no longer ring
    /// anything, so asking for them would train the user to dismiss a prompt
    /// that buys them nothing, and reporting their grant would tell the caller
    /// "you're covered" while AlarmKit is still denied.
    func requestPermission(completion: @escaping (Bool) -> Void) {
        requestAlarmKitAuthorization { granted in
            AppLogger.scheduler.notice(
                "AlarmKit authorization granted=\(granted, privacy: .public)"
            )
            // Already-decided grants resolve synchronously on the calling
            // thread; the prompt path resolves on the main actor. Normalize so
            // UI callers never have to check.
            if Thread.isMainThread {
                completion(granted)
            } else {
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - Register notification categories

    /// Legacy (#472): registers the actions for alarm notifications scheduled by
    /// a pre-#472 build that may still be pending on the device. Nothing new is
    /// ever scheduled against this category.
    func registerCategories() {
        let dismissAction = UNNotificationAction(
            identifier: dismissActionID,
            title: "Выключить",
            options: [.foreground]
        )
        // Snooze action title is updated dynamically in the notification content
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionID,
            title: "Поспать ещё",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [dismissAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        notificationCenter.setNotificationCategories([category])
    }

    // MARK: - Schedule alarm

    /// Schedule the user's alarm as an AlarmKit system alarm.
    /// - Parameters:
    ///   - alarm: alarm model to schedule (no-op when `enabled == false`).
    ///   - completion: optional callback invoked once with the outcome.
    ///     `.failure(.backendUnavailable)` when AlarmKit is not authorized,
    ///     `.failure(.system)` when AlarmKit rejected the schedule. Default
    ///     `nil` keeps the scheduler-driven call sites (`AlarmRepository.save`)
    ///     backwards compatible (issue #118).
    ///
    /// The AlarmKit `schedule` is async: we report `.success` ONLY after that
    /// await resolves. A success reported earlier could tell the user "Будильник
    /// создан" with nothing armed (#417, same phantom-success class as
    /// #118/#199).
    func schedule(_ alarm: Alarm, completion: ((Result<Void, SchedulingError>) -> Void)? = nil) {
        guard alarm.enabled else {
            completion?(.success(()))
            return
        }

        guard usesAlarmKit, let alarmKitScheduler else {
            AppLogger.scheduler.error(
                """
                schedule refused: AlarmKit not authorized alarm=\(alarm.id, privacy: .private) \
                — no alarm armed (#472)
                """
            )
            completion?(.failure(.backendUnavailable))
            return
        }

        alarmKitScheduler.schedule(alarm) { result in
            switch result {
            case .success:
                AppLogger.scheduler.info(
                    "scheduled via AlarmKit alarm=\(alarm.id, privacy: .private)"
                )
                completion?(.success(()))
            case .failure(let error):
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    "AlarmKit schedule failed alarm=\(alarm.id, privacy: .private): \(desc, privacy: .public)"
                )
                completion?(.failure(.system(message: desc)))
            }
        }
    }

    // MARK: - Schedule snooze

    /// Reschedule the alarm as a one-shot AlarmKit alarm at now + snoozeMinutes.
    ///
    /// Stops the currently-alerting system alarm first (the in-app firing screen
    /// also silences its audio), then reschedules under a separate snooze id
    /// (#394) so a repeating original keeps its weekday schedule.
    ///
    /// Carries the same `completion` semantics as `schedule(_:completion:)` so
    /// `AlarmFiringViewModel` / `AlarmFiringCoordinator` refund the already
    /// charged penalty instead of leaving the user with nothing re-ringing
    /// (#118, #394 Finding 1).
    func scheduleSnooze(
        for alarm: Alarm,
        snoozeCount: Int,
        completion: ((Result<Void, SchedulingError>) -> Void)? = nil
    ) {
        guard usesAlarmKit, let alarmKitScheduler else {
            AppLogger.scheduler.error(
                """
                snooze refused: AlarmKit not authorized alarm=\(alarm.id, privacy: .private) \
                — penalty must be refunded (#472)
                """
            )
            completion?(.failure(.backendUnavailable))
            return
        }

        let fireDate = Self.scheduledFireDate(now: Date(), snoozeMinutes: alarm.snoozeMinutes)
        alarmKitScheduler.stop(alarm.id)
        alarmKitScheduler.scheduleSnooze(alarm, fireDate: fireDate) { result in
            switch result {
            case .success:
                AppLogger.scheduler.info(
                    "scheduled snooze via AlarmKit alarm=\(alarm.id, privacy: .private)"
                )
                completion?(.success(()))
            case .failure(let error):
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    """
                    AlarmKit snooze schedule failed alarm=\(alarm.id, privacy: .private): \
                    \(desc, privacy: .public)
                    """
                )
                completion?(.failure(.system(message: desc)))
            }
        }
    }

    /// Pure factory for the snooze fire date — extracted so unit tests can pin the
    /// arithmetic without touching the backend. Bug guard for mistaken
    /// unit conversions (minutes vs seconds vs hours).
    static func scheduledFireDate(now: Date, snoozeMinutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
    }

    // MARK: - Cancel

    /// Cancel the alarm on every backend it could have been armed on: the
    /// AlarmKit system alarm, plus any notification a pre-#472 build left
    /// pending for this alarm.
    ///
    /// The notification half filters by `alarmID` prefix instead of hard-coding
    /// the label list — this prevents regressions like IOS-070 where a one-off
    /// (`once`) alarm kept ringing after deletion because its identifier was
    /// missing from the cancel set.
    func cancel(_ alarmID: UUID) {
        // Always attempt the AlarmKit cancel regardless of `usesAlarmKit` so an
        // alarm scheduled while authorized is still cancellable if the
        // authorization later changed.
        if let alarmKitScheduler {
            alarmKitScheduler.cancel(alarmID)
        }

        let prefix = notificationIDPrefix(for: alarmID)
        let snoozeID = snoozeNotificationID(for: alarmID)
        // Prefix match rather than an exact one, so legacy per-day, one-off and
        // `_burstN` follow-up identifiers are all covered.
        let belongsToAlarm: (String) -> Bool = {
            $0.hasPrefix(prefix) || $0 == snoozeID || $0.hasPrefix("\(snoozeID)_")
        }

        // Belt-and-suspenders: explicit-IDs sync removal first (no async dependency).
        // If the async `getPendingNotificationRequests` completion returns an empty
        // array — system glitch, background suspension, permission revoked — the
        // prefix sweep below silently exits without removing anything. The sync
        // call here guarantees the canonical day0..day6 / once / snooze IDs are
        // removed regardless. Per #92 follow-up to #70.
        let labels = (0..<7).map { "day\($0)" } + ["once"]
        let explicitIDs = labels.map { notificationID(for: alarmID, trigger: $0) } + [snoozeID]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: explicitIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: explicitIDs)

        // Then prefix sweep for stragglers the explicit set didn't cover —
        // including the `_burstN` follow-ups of a pre-#472 install (idempotent:
        // already-removed IDs are no-ops).
        notificationCenter.getPendingNotificationRequests { [notificationCenter] requests in
            let ids = requests.map { $0.identifier }.filter(belongsToAlarm)
            if ids.isEmpty {
                AppLogger.scheduler.info(
                    """
                    cancel sweep: no pending requests matched alarmID \
                    \(alarmID, privacy: .private) (explicit removal already ran)
                    """
                )
                return
            }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        }
        notificationCenter.getDeliveredNotifications { [notificationCenter] notifications in
            let ids = notifications.map { $0.request.identifier }.filter(belongsToAlarm)
            guard !ids.isEmpty else { return }
            notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func cancelAll() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    /// Re-arm every enabled alarm from scratch — cancel its existing triggers
    /// and schedule it again. Mirrors the `cancel` → `schedule` sequence
    /// `AlarmRepository.save(_:)` already uses, so the wallet semantics are
    /// identical to a normal save.
    ///
    /// Called when something that silently invalidates already-scheduled
    /// alarms may have changed out from under us (#427):
    ///
    /// - **Timezone / DST shift.** An alarm armed in TZ A can fire at the wrong
    ///   wall-clock after moving to TZ B, and a repeating schedule drifts an
    ///   hour across a DST boundary. Re-arming recomputes it against the current
    ///   calendar.
    /// - **Reboot.** Re-evaluates the schedule in case the clock / timezone
    ///   changed while the device was powered off.
    /// - **Authorization change.** `usesAlarmKit` is computed live, so toggling
    ///   the AlarmKit grant in Settings changes whether an alarm can be armed at
    ///   all. Re-arming after a re-grant is what turns saved alarms back on;
    ///   after a revoke it is what makes the failures countable instead of
    ///   invisible.
    ///
    /// Disabled alarms are skipped: they hold nothing to re-arm and
    /// `schedule(_:)` is already a no-op for them.
    /// - Parameter completion: invoked on the main queue once every re-arm has
    ///   resolved, carrying the number that FAILED to re-arm. Previously each
    ///   `schedule` was fired with a `nil` completion, so every typed
    ///   `SchedulingError` was silently dropped — an alarm could fail to re-arm
    ///   after a DST/TZ shift, reboot or permission change and never ring, with
    ///   only a Console log (#442). Aggregating the outcomes lets the caller
    ///   surface it (see `AppDelegate.handleRescheduleOutcome`).
    func rescheduleAll(_ alarms: [Alarm], completion: ((_ failedCount: Int) -> Void)? = nil) {
        let enabled = alarms.filter { $0.enabled }
        AppLogger.scheduler.info(
            "rescheduleAll: re-arming \(enabled.count, privacy: .public) of \(alarms.count, privacy: .public) alarms"
        )
        guard !enabled.isEmpty else {
            completion?(0)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var failedCount = 0

        for alarm in enabled {
            cancel(alarm.id)
            group.enter()
            schedule(alarm) { result in
                if case .failure = result {
                    lock.lock()
                    failedCount += 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if failedCount > 0 {
                let total = enabled.count
                AppLogger.scheduler.error(
                    "rescheduleAll failed: \(failedCount, privacy: .public)/\(total, privacy: .public)"
                )
            }
            completion?(failedCount)
        }
    }

    /// Stop a currently-alerting AlarmKit system alarm — invoked from
    /// `AlarmKitActionRouter` when the user taps stop / snooze on the system
    /// alert. No-op when no AlarmKit backend is wired. (#377)
    func stopSystemAlarm(_ alarmID: UUID) {
        if let alarmKitScheduler {
            alarmKitScheduler.stop(alarmID)
        }
    }

    // MARK: - Private helpers

    private func notificationID(for alarmID: UUID, trigger: String) -> String {
        "\(notificationIDPrefix(for: alarmID))\(trigger)"
    }

    /// Shared prefix for every legacy per-trigger notification belonging to an
    /// alarm. Used by `cancel(_:)` to remove pending requests for any label.
    private func notificationIDPrefix(for alarmID: UUID) -> String {
        "alarm_\(alarmID.uuidString)_"
    }

    func snoozeNotificationID(for alarmID: UUID) -> String {
        "snooze_\(alarmID.uuidString)"
    }

    /// Resolve alarm soundID to an actual file name with extension in the bundle.
    /// Returns nil if no matching file is found (AlarmKit then uses its default
    /// alert sound).
    func alarmSoundFileName(for soundID: String) -> String? {
        let extensions = ["caf", "m4a", "wav", "mp3"]
        for ext in extensions where Bundle.main.url(forResource: soundID, withExtension: ext) != nil {
            return "\(soundID).\(ext)"
        }
        // Try default alarm sound
        for ext in extensions where Bundle.main.url(forResource: "default_alarm", withExtension: ext) != nil {
            return "default_alarm.\(ext)"
        }
        return nil
    }
}
