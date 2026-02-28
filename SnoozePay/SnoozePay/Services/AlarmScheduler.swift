import Foundation
import UserNotifications

/// Handles scheduling and cancelling alarms.
/// Uses UNUserNotificationCenter (iOS 18+) as the scheduling backend.
/// On iOS 26+ with AlarmKit, the system alarm engine takes over — this service
/// manages the notification fallback and snooze rescheduling.
final class AlarmScheduler {

    static let shared = AlarmScheduler()

    private let notificationCenter = UNUserNotificationCenter.current()

    // Notification category and action IDs
    private let categoryID = "ALARM_CATEGORY"
    private let dismissActionID = "DISMISS_ACTION"
    private let snoozeActionID = "SNOOZE_ACTION"

    private init() {}

    // MARK: - Permission

    func requestPermission(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
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

    func schedule(_ alarm: Alarm) {
        guard alarm.enabled else { return }

        let content = makeContent(for: alarm, snoozeCount: 0)
        let triggers = makeTriggers(for: alarm)

        for trigger in triggers {
            let request = UNNotificationRequest(
                identifier: notificationID(for: alarm.id, trigger: trigger.label),
                content: content,
                trigger: trigger.trigger
            )
            notificationCenter.add(request)
        }
    }

    // MARK: - Schedule snooze

    func scheduleSnooze(for alarm: Alarm, snoozeCount: Int) {
        let content = makeContent(for: alarm, snoozeCount: snoozeCount)

        let fireDate = Date().addingTimeInterval(TimeInterval(alarm.snoozeMinutes * 60))
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: snoozeNotificationID(for: alarm.id),
            content: content,
            trigger: trigger
        )
        notificationCenter.add(request)
    }

    // MARK: - Cancel

    func cancel(_ alarmID: UUID) {
        let allIDs = (0...6).map { notificationID(for: alarmID, trigger: "day\($0)") }
            + [snoozeNotificationID(for: alarmID)]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: allIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: allIDs)
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

        // Use critical alert sound to bypass Do Not Disturb and Silent Mode.
        // Requires NSCriticalAlertUsageDescription in Info.plist and
        // com.apple.developer.usernotifications.critical-alerts entitlement.
        if let soundName = alarmSoundFileName(for: alarm.soundID) {
            content.sound = UNNotificationSound.criticalSoundNamed(
                UNNotificationSoundName(soundName),
                withAudioVolume: 1.0
            )
        } else {
            content.sound = UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
        }

        content.categoryIdentifier = categoryID
        content.interruptionLevel = .critical

        // Pass alarm metadata via userInfo for handling in AppDelegate
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "penaltyAmount": alarm.penaltyAmount,
            "progressiveScale": alarm.progressiveScale,
            "snoozeCount": snoozeCount,
            "snoozeMinutes": alarm.snoozeMinutes,
            "soundID": alarm.soundID
        ]

        return content
    }

    private struct TriggerWithLabel {
        let label: String
        let trigger: UNNotificationTrigger
    }

    /// Build triggers for all active repeat days, or a one-time trigger if no repeat days.
    private func makeTriggers(for alarm: Alarm) -> [TriggerWithLabel] {
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
        "alarm_\(alarmID.uuidString)_\(trigger)"
    }

    private func snoozeNotificationID(for alarmID: UUID) -> String {
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
