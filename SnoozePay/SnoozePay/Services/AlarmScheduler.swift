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
        /// The scheduler was torn down (or the operation cancelled) while the
        /// async 64-pending pre-flight was in flight, so nothing was actually
        /// registered. Previously this branch reported `.success(())`, which
        /// produced a phantom "scheduled" outcome — the penalty stayed charged
        /// but no notification existed (issue #199). Surfacing a typed failure
        /// lets callers refund / retry instead of trusting a fake success.
        case cancelled

        var errorDescription: String? {
            switch self {
            case .system(let message):
                return "Не удалось запланировать будильник: \(message). "
                     + "Включите уведомления в Настройках или удалите старые будильники."
            case .pendingLimitReached(let count):
                return "Достигнут лимит iOS на запланированные уведомления (\(count) из 64). "
                     + "Удалите старые будильники, чтобы освободить место."
            case .cancelled:
                return "Планирование будильника было прервано. Попробуйте ещё раз."
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

    /// Lock-screen fallback burst (issue #19). Without the Critical Alerts
    /// entitlement the alarm arrives as a single `.timeSensitive` notification
    /// — one ping, no continuous sound. If the user doesn't catch that one
    /// banner the alarm is effectively missed. To make the fallback more
    /// insistent within standard-notification limits we schedule a small set
    /// of follow-up notifications a few seconds apart, so a missed first ping
    /// re-pings instead of going silent.
    ///
    /// Offsets are in SECONDS after the primary fire time. Kept deliberately
    /// short and few (3 follow-ups over 90s) so we never spam dozens of
    /// notifications or crowd out the 64-pending cap. The follow-ups share the
    /// alarm's `alarm_<id>_` identifier prefix, so the existing prefix-sweep in
    /// `cancel(_:)` removes them the moment the alarm is dismissed / snoozed —
    /// no orphan notifications survive a handled alarm.
    static let fallbackBurstOffsetsSeconds = [30, 60, 90]

    private let notificationCenter: NotificationScheduling

    // Notification category and action IDs
    private let categoryID = "ALARM_CATEGORY"
    private let dismissActionID = "DISMISS_ACTION"
    private let snoozeActionID = "SNOOZE_ACTION"

    /// Whether the app has the critical alerts entitlement (set after permission request)
    private(set) static var criticalAlertsAvailable = false

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
                Self.criticalAlertsAvailable = false
                let standardOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
                self.notificationCenter.requestAuthorization(options: standardOptions) { granted, fallbackError in
                    Self.criticalAlertsAvailable = false
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
                Self.criticalAlertsAvailable = granted
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
                // Scheduler deallocated mid-preflight — report a typed failure,
                // never a phantom success (issue #199).
                completion?(.failure(.cancelled))
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

        // Lock-screen fallback burst (#19): make the snooze re-fire as
        // insistent as the original alarm. Follow-ups carry the snooze
        // identifier prefix so `cancel(_:)` sweeps them away once the alarm is
        // handled. Skipped on the critical-alerts path (continuous sound).
        var requests = [request]
        if !Self.criticalAlertsAvailable {
            // Build the burst identifier from the index directly — `snooze_<id>
            // _burstN` — so it matches the explicit-ID set `cancel(_:)` /
            // `cancelFallbackBursts(_:)` remove (`"\(snoozeID)_burst\(i)"`).
            // Routing through `burst.label` would double the suffix
            // (`burst_burst0`) and the belt-and-suspenders removal would miss it,
            // orphaning the snooze burst (#19 QA).
            requests += Self.burstTriggers(after: components, label: "burst", repeats: false)
                .enumerated()
                .map { index, burst in
                    UNNotificationRequest(
                        identifier: "\(snoozeNotificationID(for: alarm.id))_burst\(index)",
                        content: content,
                        trigger: burst.trigger
                    )
                }
        }

        runPendingLimitPreflight(triggerCount: requests.count) { [weak self] preflight in
            guard let self else {
                // Scheduler deallocated mid-preflight — report a typed failure,
                // never a phantom success (issue #199). The coordinator refunds
                // the already-charged penalty on this failure.
                completion?(.failure(.cancelled))
                return
            }
            if case .failure(let error) = preflight {
                completion?(.failure(error))
                return
            }
            self.dispatchAdds(requests: requests, completion: completion)
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
        // Match the snooze identifier itself AND its fallback-burst follow-ups
        // (`snooze_<id>_burstN`, #19) — using a prefix check rather than an
        // exact match so a handled alarm leaves no orphan burst notifications.
        let belongsToAlarm: (String) -> Bool = {
            $0.hasPrefix(prefix) || $0 == snoozeID || $0.hasPrefix("\(snoozeID)_")
        }

        // Belt-and-suspenders: explicit-IDs sync removal first (no async dependency).
        // If the async `getPendingNotificationRequests` completion returns an empty
        // array — system glitch, background suspension, permission revoked — the
        // prefix sweep below silently exits without removing anything. The sync
        // call here guarantees the canonical day0..day6 / once / snooze IDs and
        // their burst follow-ups (#19) are removed regardless. Per #92 follow-up to #70.
        let labels = (0..<7).map { "day\($0)" } + ["once"]
        let explicitIDs = labels.map { notificationID(for: alarmID, trigger: $0) }
            + labels.flatMap { label in
                Self.fallbackBurstOffsetsSeconds.indices.map {
                    notificationID(for: alarmID, trigger: "\(label)_burst\($0)")
                }
            }
            + [snoozeID]
            + Self.fallbackBurstOffsetsSeconds.indices.map { "\(snoozeID)_burst\($0)" }
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

    /// Cancel ONLY the lock-screen fallback-burst follow-ups (`#19`) for an
    /// alarm — the `_burstN` notifications — while leaving the primary triggers
    /// (`day0…day6`, `once`, `snooze`) armed. Called from the lock-screen
    /// dismiss / snooze action paths, where the current firing's bursts are
    /// still pending at +30/60/90s and would spuriously re-ring after the user
    /// already got up or snoozed (#19 QA — the orphan-re-ring fix). A blanket
    /// `cancel(_:)` would also drop a repeating alarm's future weekday triggers,
    /// disabling it — so this is deliberately burst-only.
    func cancelFallbackBursts(_ alarmID: UUID) {
        let prefix = notificationIDPrefix(for: alarmID)
        let snoozeID = snoozeNotificationID(for: alarmID)
        // A burst id is the alarm/snooze id plus a `_burstN` suffix. Primary
        // triggers never contain `_burst`, so this never touches them.
        let isBurst: (String) -> Bool = {
            ($0.hasPrefix(prefix) || $0.hasPrefix(snoozeID)) && $0.contains("_burst")
        }

        // Belt-and-suspenders explicit removal (sync, no async dependency —
        // mirrors `cancel(_:)`): covers day0..day6 / once / snooze burst IDs.
        let labels = (0..<7).map { "day\($0)" } + ["once"]
        let explicitBurstIDs = labels.flatMap { label in
            Self.fallbackBurstOffsetsSeconds.indices.map {
                notificationID(for: alarmID, trigger: "\(label)_burst\($0)")
            }
        }
            + Self.fallbackBurstOffsetsSeconds.indices.map { "\(snoozeID)_burst\($0)" }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: explicitBurstIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: explicitBurstIDs)

        // Prefix sweep for any stragglers the explicit set didn't cover.
        notificationCenter.getPendingNotificationRequests { [notificationCenter] requests in
            let ids = requests.map { $0.identifier }.filter(isBurst)
            guard !ids.isEmpty else { return }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        }
        notificationCenter.getDeliveredNotifications { [notificationCenter] notifications in
            let ids = notifications.map { $0.request.identifier }.filter(isBurst)
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
        content.subtitle = "+\(alarm.snoozeMinutes) минут · −\(MoneyFormatter.string(penalty))"

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

        // Critical alerts (when entitled) deliver continuous lock-screen sound,
        // so the lock-screen fallback burst (#19) is only added on the degraded
        // `.timeSensitive` path where a single ping can be missed.
        let withBurst = !Self.criticalAlertsAvailable

        if alarm.repeatDays.isEmpty {
            // One-time alarm: fire at the next occurrence of this time, plus a
            // short self-cancelling follow-up burst (#19).
            var components = DateComponents()
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let primary = TriggerWithLabel(label: "once", trigger: trigger)
            guard withBurst else { return [primary] }
            return [primary] + Self.burstTriggers(after: components, label: "once", repeats: false)
        }

        // One-shot mode (#229): non-repeating triggers fire once at the next
        // occurrence of each selected weekday and are never re-armed by iOS.
        // The alarm itself is auto-disabled on dismiss
        // (`AlarmFiringViewModel.dismiss`), which also cancels the remaining
        // per-day triggers via `cancel(_:)`.
        let repeats = alarm.repeatMode == .weekly

        // Map our 0=Mon system to iOS weekday (1=Sun, 2=Mon, ..., 7=Sat)
        return alarm.repeatDays.flatMap { day -> [TriggerWithLabel] in
            let weekday = ((day + 1) % 7) + 1 // Convert: 0(Mon)->2, 6(Sun)->1
            var components = DateComponents()
            components.weekday = weekday
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
            let primary = TriggerWithLabel(label: "day\(day)", trigger: trigger)
            guard withBurst else { return [primary] }
            return [primary] + Self.burstTriggers(after: components, label: "day\(day)", repeats: repeats)
        }
    }

    /// Build the self-cancelling follow-up burst for a primary trigger (#19).
    ///
    /// Each follow-up reuses the primary's date components and shifts them
    /// forward by one of `fallbackBurstOffsetsSeconds`, carrying any weekday so
    /// the burst lands on the same day as the alarm. Labels are suffixed
    /// `<label>_burstN` so they share the alarm's identifier prefix and are
    /// swept away by `cancel(_:)` on dismiss/snooze — no orphans survive a
    /// handled alarm. Exposed `static` + `internal` so unit tests can pin the
    /// second/minute/hour roll-over arithmetic without touching UN.
    static func burstTriggers(
        after base: DateComponents,
        label: String,
        repeats: Bool
    ) -> [TriggerWithLabel] {
        fallbackBurstOffsetsSeconds.enumerated().map { index, offset in
            let shifted = burstComponents(base: base, offsetSeconds: offset)
            let trigger = UNCalendarNotificationTrigger(dateMatching: shifted, repeats: repeats)
            return TriggerWithLabel(label: "\(label)_burst\(index)", trigger: trigger)
        }
    }

    /// Shift `base`'s hour/minute/second forward by `offsetSeconds`, rolling
    /// minutes and hours over correctly (e.g. 07:59:00 + 90s = 08:00:30).
    /// `weekday` is preserved unchanged — the small offsets used here (≤90s)
    /// never cross midnight in practice, and crossing a day boundary would only
    /// move a follow-up to the wrong weekday, which we accept over the
    /// complexity of weekday roll-over for a best-effort fallback burst.
    static func burstComponents(base: DateComponents, offsetSeconds: Int) -> DateComponents {
        let totalSeconds = (base.hour ?? 0) * 3600
            + (base.minute ?? 0) * 60
            + (base.second ?? 0)
            + offsetSeconds
        let dayWrapped = ((totalSeconds % 86_400) + 86_400) % 86_400
        var shifted = base
        shifted.hour = dayWrapped / 3600
        shifted.minute = (dayWrapped % 3600) / 60
        shifted.second = dayWrapped % 60
        return shifted
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
