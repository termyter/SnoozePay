import Foundation
import UserNotifications
import os

/// Subset of `UNUserNotificationCenter` the scheduler depends on. Extracted as a
/// protocol so unit tests can substitute a mock and verify error-propagation
/// paths (issue #118) — the real `UNUserNotificationCenter.current()` is a
/// process-wide singleton whose `add(_:)` failure modes (permission revoked
/// mid-session, malformed trigger, 64-pending limit) cannot otherwise be
/// reproduced deterministically.
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

/// Handles scheduling and cancelling alarms.
/// Uses UNUserNotificationCenter (iOS 18+) as the scheduling backend.
/// On iOS 26+ with AlarmKit, the system alarm engine takes over — this service
/// manages the notification fallback and snooze rescheduling.
final class AlarmScheduler: AlarmScheduling {

    static let shared = AlarmScheduler()

    /// Errors surfaced to UI callers so the user sees a real explanation
    /// instead of a fake "Будильник создан" toast on a notification that
    /// never registered (issue #118).
    enum SchedulingError: LocalizedError, Equatable {
        /// `UNUserNotificationCenter.add` returned an error — typically a
        /// revoked notification permission or a malformed trigger.
        case system(message: String)
        /// Pre-flight check found we are at or above the iOS 64-pending
        /// notification cap. Adding another would silently evict an
        /// existing one, so we refuse and let the user delete old alarms.
        case pendingLimitReached(currentCount: Int)

        var errorDescription: String? {
            switch self {
            case .system(let message):
                return "Не удалось запланировать будильник: \(message). "
                     + "Включите уведомления в Настройках или удалите старые будильники."
            case .pendingLimitReached(let count):
                return "Достигнут лимит iOS на запланированные уведомления (\(count) из 64). "
                     + "Удалите старые будильники, чтобы освободить место."
            }
        }
        // Equatable synthesis is automatic — `String` and `Int` associated
        // values both conform out of the box.
    }

    /// iOS hard-cap on pending notification requests per app. Above this the
    /// system silently drops additional requests (oldest-first), so we
    /// pre-flight check and refuse rather than scheduling a request that may
    /// or may not survive eviction.
    static let pendingNotificationLimit = 64

    private let notificationCenter: NotificationScheduling

    // Notification category and action IDs
    private let categoryID = "ALARM_CATEGORY"
    private let dismissActionID = "DISMISS_ACTION"
    private let snoozeActionID = "SNOOZE_ACTION"

    /// Whether the app has the critical alerts entitlement (set after permission request).
    ///
    /// Writes come from the UN-delegate background thread (`requestAuthorization`
    /// callback), reads come from `makeContent` on whatever thread is scheduling.
    /// Without synchronization there was a brief window after permission grant
    /// where a parallel `schedule` call read a stale `false` and built a
    /// non-critical alert content (issue #204). `os_unfair_lock` is enough
    /// here — both halves are constant-time and contention is rare.
    private static let criticalAlertsLock = NSLock()
    private static var _criticalAlertsAvailable = false
    static var criticalAlertsAvailable: Bool {
        criticalAlertsLock.lock()
        defer { criticalAlertsLock.unlock() }
        return _criticalAlertsAvailable
    }
    private static func setCriticalAlertsAvailable(_ value: Bool) {
        criticalAlertsLock.lock()
        _criticalAlertsAvailable = value
        criticalAlertsLock.unlock()
    }

    private init() {
        self.notificationCenter = UNUserNotificationCenter.current()
    }

    /// Test-only initializer that swaps the notification-center seam.
    /// Production code MUST use `AlarmScheduler.shared` (see `singleton`).
    init(notificationCenter: NotificationScheduling) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Permission

    func requestPermission(completion: @escaping (Bool) -> Void) {
        // Request critical alerts if entitled, fall back to standard alerts otherwise.
        // Always log the resolved state so QA can tell if we're on the degraded
        // (no critical-alert) path even when standard permission succeeds.
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
            if let error = error {
                let desc = error.localizedDescription
                AppLogger.scheduler.error(
                    "critical-alert request failed: \(desc, privacy: .public). Falling back to standard."
                )
                Self.setCriticalAlertsAvailable(false)
                let standardOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
                self.notificationCenter.requestAuthorization(options: standardOptions) { granted, fallbackError in
                    Self.setCriticalAlertsAvailable(false)
                    if let fallbackError = fallbackError {
                        let fallbackDesc = fallbackError.localizedDescription
                        AppLogger.scheduler.error(
                            "resolved path=fallback granted=\(granted, privacy: .public) critical=false error=\(fallbackDesc, privacy: .public)"
                        )
                    } else {
                        AppLogger.scheduler.notice(
                            "resolved path=fallback granted=\(granted, privacy: .public) critical=false"
                        )
                    }
                    DispatchQueue.main.async { completion(granted) }
                }
            } else {
                Self.setCriticalAlertsAvailable(granted)
                AppLogger.scheduler.notice(
                    "resolved path=primary granted=\(granted, privacy: .public) critical=\(granted, privacy: .public)"
                )
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - Register notification categories

    func registerCategories() {
        let dismissAction = UNNotificationAction(
            identifier: dismissActionID,
            title: "Выключить",
            options: [.foreground]
        )
        // Snooze action title is updated dynamically in the notification content
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionID,
            title: "Отложить",
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

    /// Schedule the user's alarm.
    /// - Parameters:
    ///   - alarm: alarm model to schedule (no-op when `enabled == false`).
    ///   - completion: optional callback invoked once on the main queue once
    ///     all triggers have either landed or one of them failed. Failures
    ///     are reported as `SchedulingError.system(message:)`. Default `nil`
    ///     keeps the scheduler-driven call sites (`AlarmRepository.save`)
    ///     backwards compatible (issue #118).
    func schedule(_ alarm: Alarm, completion: ((Result<Void, SchedulingError>) -> Void)? = nil) {
        guard alarm.enabled else {
            completion?(.success(()))
            return
        }

        let content = makeContent(for: alarm, snoozeCount: 0)
        let triggers = makeTriggers(for: alarm)

        guard !triggers.isEmpty else {
            completion?(.success(()))
            return
        }

        // Pre-flight 64-pending limit check. We refuse to schedule when the
        // batch we're about to add would push us over — iOS would otherwise
        // silently evict our oldest pending request. Surface the situation
        // to the user instead so they know to delete old alarms.
        runPendingLimitPreflight(triggerCount: triggers.count) { [weak self] preflight in
            guard let self else {
                completion?(.success(()))
                return
            }
            if case .failure(let error) = preflight {
                completion?(.failure(error))
                return
            }
            self.dispatchAdds(
                requests: triggers.map { trigger in
                    UNNotificationRequest(
                        identifier: self.notificationID(for: alarm.id, trigger: trigger.label),
                        content: content,
                        trigger: trigger.trigger
                    )
                },
                completion: completion
            )
        }
    }

    // MARK: - Schedule snooze

    /// Schedule a follow-up snooze notification.
    /// Carries the same `completion` semantics as `schedule(_:completion:)`
    /// so `AlarmFiringViewModel` / `AlarmFiringCoordinator` can surface
    /// scheduling failures instead of silently leaving the user without a
    /// re-fire (issue #118).
    func scheduleSnooze(
        for alarm: Alarm,
        snoozeCount: Int,
        completion: ((Result<Void, SchedulingError>) -> Void)? = nil
    ) {
        let content = makeContent(for: alarm, snoozeCount: snoozeCount)

        let fireDate = Self.scheduledFireDate(now: Date(), snoozeMinutes: alarm.snoozeMinutes)
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: snoozeNotificationID(for: alarm.id),
            content: content,
            trigger: trigger
        )

        runPendingLimitPreflight(triggerCount: 1) { [weak self] preflight in
            guard let self else {
                completion?(.success(()))
                return
            }
            if case .failure(let error) = preflight {
                completion?(.failure(error))
                return
            }
            self.dispatchAdds(requests: [request], completion: completion)
        }
    }

    // MARK: - Private scheduling helpers

    /// Run the iOS 64-pending-limit pre-flight. Resolves to `.failure` when
    /// adding `triggerCount` requests would push us over the cap.
    /// Always resolves on the main queue so callers don't need to bounce.
    private func runPendingLimitPreflight(
        triggerCount: Int,
        completion: @escaping (Result<Void, SchedulingError>) -> Void
    ) {
        notificationCenter.getPendingNotificationRequests { requests in
            let pending = requests.count
            DispatchQueue.main.async {
                if pending + triggerCount > Self.pendingNotificationLimit {
                    let limit = Self.pendingNotificationLimit
                    AppLogger.scheduler.error(
                        "schedule blocked: pending=\(pending, privacy: .public) batch=\(triggerCount, privacy: .public) limit=\(limit, privacy: .public)"
                    )
                    completion(.failure(.pendingLimitReached(currentCount: pending)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// Add a batch of notification requests sequentially, fan-in their
    /// completion blocks, and report the first error to the caller. We
    /// fan-in instead of bailing on the first failure so partial success
    /// (e.g. 5/7 weekday triggers landed, 2 rejected) is logged for every
    /// failure even though only the first is surfaced to the UI.
    private func dispatchAdds(
        requests: [UNNotificationRequest],
        completion: ((Result<Void, SchedulingError>) -> Void)?
    ) {
        guard !requests.isEmpty else {
            completion?(.success(()))
            return
        }

        let group = DispatchGroup()
        var firstError: Error?
        let errorLock = NSLock()

        for request in requests {
            group.enter()
            notificationCenter.add(request) { error in
                if let error = error {
                    AppLogger.scheduler.error(
                        "schedule failed: \(error.localizedDescription, privacy: .public)"
                    )
                    errorLock.lock()
                    if firstError == nil { firstError = error }
                    errorLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion?(.failure(.system(message: error.localizedDescription)))
            } else {
                completion?(.success(()))
            }
        }
    }

    /// Pure factory for the snooze fire date — extracted so unit tests can pin the
    /// arithmetic without touching UNUserNotificationCenter. Bug guard for mistaken
    /// unit conversions (minutes vs seconds vs hours).
    static func scheduledFireDate(now: Date, snoozeMinutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
    }

    // MARK: - Cancel

    /// Cancel every notification scheduled for the given alarm, regardless of trigger label
    /// (e.g. `day0`-`day6`, `once`, future labels) and the snooze follow-up.
    ///
    /// We fetch pending requests and filter by `alarmID` prefix instead of hard-coding the
    /// label list — this prevents regressions like IOS-070 where a one-off (`once`) alarm
    /// kept ringing after deletion because its identifier was missing from the cancel set.
    func cancel(_ alarmID: UUID) {
        let prefix = notificationIDPrefix(for: alarmID)
        let snoozeID = snoozeNotificationID(for: alarmID)
        let belongsToAlarm: (String) -> Bool = { $0.hasPrefix(prefix) || $0 == snoozeID }

        // Belt-and-suspenders: explicit-IDs sync removal first (no async dependency).
        // If the async `getPendingNotificationRequests` completion returns an empty
        // array — system glitch, background suspension, permission revoked — the
        // prefix sweep below silently exits without removing anything. The sync
        // call here guarantees the canonical day0..day6 / once / snooze IDs are
        // removed regardless. Per #92 follow-up to #70.
        let explicitIDs = (0..<7).map { notificationID(for: alarmID, trigger: "day\($0)") }
            + [notificationID(for: alarmID, trigger: "once")]
            + [snoozeID]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: explicitIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: explicitIDs)

        // Then prefix sweep for any future label additions / stragglers the
        // explicit set didn't cover (idempotent — already-removed IDs are no-ops).
        notificationCenter.getPendingNotificationRequests { [notificationCenter] requests in
            let ids = requests.map { $0.identifier }.filter(belongsToAlarm)
            if ids.isEmpty {
                AppLogger.scheduler.info("cancel sweep: no pending requests matched alarmID \(alarmID, privacy: .private) (explicit removal already ran)")
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

    // MARK: - Private helpers

    func makeContent(for alarm: Alarm, snoozeCount: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.name
        content.body = "Время вставать!"

        let penalty = alarm.penalty(forSnoozeCount: snoozeCount + 1)
        content.subtitle = "Отложить · \(Int(penalty)) ₽"

        // Use critical sound if entitled, otherwise fall back to standard sound.
        // Critical alerts bypass DND and silent mode (requires Apple approval).
        if let soundName = alarmSoundFileName(for: alarm.soundID) {
            let soundN = UNNotificationSoundName(soundName)
            content.sound = Self.criticalAlertsAvailable
                ? UNNotificationSound.criticalSoundNamed(soundN, withAudioVolume: 1.0)
                : UNNotificationSound(named: soundN)
        } else {
            content.sound = Self.criticalAlertsAvailable
                ? UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
                : .default
        }

        content.categoryIdentifier = categoryID
        content.interruptionLevel = Self.criticalAlertsAvailable ? .critical : .timeSensitive

        // Pass alarm metadata via a typed payload so AppDelegate /
        // AlarmFiringCoordinator can decode it without ad-hoc `as?` casts.
        content.userInfo = AlarmNotificationPayload(alarm: alarm, snoozeCount: snoozeCount)
            .asUserInfo()

        return content
    }

    struct TriggerWithLabel {
        let label: String
        let trigger: UNNotificationTrigger
    }

    /// Build triggers for all active repeat days, or a one-time trigger if no repeat days.
    /// Exposed as `internal` so tests can pin the legacy 0=Mon → Calendar.weekday 1=Sun
    /// mapping; an off-by-one here means "alarm on Saturday rings on Sunday".
    func makeTriggers(for alarm: Alarm) -> [TriggerWithLabel] {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: alarm.time)

        if alarm.repeatDays.isEmpty {
            // One-time alarm: fire at the next occurrence of this time
            var components = DateComponents()
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return [TriggerWithLabel(label: "once", trigger: trigger)]
        }

        // Map our 0=Mon system to iOS weekday (1=Sun, 2=Mon, ..., 7=Sat)
        return alarm.repeatDays.map { day in
            let weekday = ((day + 1) % 7) + 1 // Convert: 0(Mon)->2, 6(Sun)->1
            var components = DateComponents()
            components.weekday = weekday
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            return TriggerWithLabel(label: "day\(day)", trigger: trigger)
        }
    }

    private func notificationID(for alarmID: UUID, trigger: String) -> String {
        "\(notificationIDPrefix(for: alarmID))\(trigger)"
    }

    /// Shared prefix for every per-trigger notification belonging to an alarm.
    /// Used by `cancel(_:)` to remove pending requests for any trigger label.
    private func notificationIDPrefix(for alarmID: UUID) -> String {
        "alarm_\(alarmID.uuidString)_"
    }

    func snoozeNotificationID(for alarmID: UUID) -> String {
        "snooze_\(alarmID.uuidString)"
    }

    /// Resolve alarm soundID to an actual file name with extension in the bundle.
    /// Returns nil if no matching file is found (falls back to default critical sound).
    func alarmSoundFileName(for soundID: String) -> String? {
        let extensions = ["caf", "m4a", "wav", "mp3"]
        for ext in extensions {
            if Bundle.main.url(forResource: soundID, withExtension: ext) != nil {
                return "\(soundID).\(ext)"
            }
        }
        // Try default alarm sound
        for ext in extensions {
            if Bundle.main.url(forResource: "default_alarm", withExtension: ext) != nil {
                return "default_alarm.\(ext)"
            }
        }
        return nil
    }
}
