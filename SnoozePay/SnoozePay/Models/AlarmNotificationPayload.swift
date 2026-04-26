import Foundation

/// Typed wrapper for the `userInfo` dictionary attached to an alarm
/// `UNNotificationContent`.
///
/// Without this struct, three sites (`AlarmScheduler.makeContent`,
/// `AlarmFiringCoordinator.handleSnooze`, `AppDelegate`) each formed/parsed
/// a stringly-typed `[AnyHashable: Any]` independently. A single typo in a
/// key (e.g. `"alarmId"` vs `"alarmID"`) silently dropped the snooze with no
/// compiler help. `init?(userInfo:)` + `asUserInfo()` give one source of
/// truth and a typed failure path.
///
/// Money-typed `penalty` stays `Double` until phase-2 of #31 migrates the
/// underlying `Alarm.penaltyAmount` storage. Once that lands this should
/// switch to `Money`.
struct AlarmNotificationPayload: Equatable {

    /// Identifier of the alarm that fired. Used to look up the persisted
    /// `Alarm` from `AlarmRepository` on the read side.
    let alarmID: UUID

    /// Penalty (RUB) recorded at scheduling time. Currently informational —
    /// read-sites recompute the actual charge from the live `Alarm` so a
    /// changed setting takes effect on the next fire — but kept on the
    /// payload for telemetry / debugging and for the notification subtitle.
    let penalty: Double

    /// How many times this alarm has already been snoozed in the current
    /// firing cycle. Drives progressive-penalty arithmetic on the read side.
    let snoozeCount: Int

    /// Identifier of the sound asset to play. Read by `AppDelegate` /
    /// `AudioService` before the firing screen is presented so audio starts
    /// even if the alarm has been deleted from the repository.
    let soundID: String

    // MARK: - userInfo bridging

    /// Keys used in the underlying `userInfo` dict. Centralised here so
    /// the write and read sites cannot drift.
    enum Keys {
        static let alarmID = "alarmID"
        static let penalty = "penaltyAmount"
        static let snoozeCount = "snoozeCount"
        static let soundID = "soundID"
    }
}

extension AlarmNotificationPayload {

    /// Decode a notification's `userInfo` into a typed payload.
    /// Returns `nil` if any required key is missing or has the wrong type —
    /// callers are expected to log + bail out rather than guessing defaults.
    init?(userInfo: [AnyHashable: Any]) {
        guard
            let alarmIDString = userInfo[Keys.alarmID] as? String,
            let alarmID = UUID(uuidString: alarmIDString),
            let penalty = userInfo[Keys.penalty] as? Double,
            let snoozeCount = userInfo[Keys.snoozeCount] as? Int,
            let soundID = userInfo[Keys.soundID] as? String
        else {
            return nil
        }
        self.alarmID = alarmID
        self.penalty = penalty
        self.snoozeCount = snoozeCount
        self.soundID = soundID
    }

    /// Encode the payload as a `[String: Any]` ready for
    /// `UNMutableNotificationContent.userInfo`.
    func asUserInfo() -> [String: Any] {
        [
            Keys.alarmID: alarmID.uuidString,
            Keys.penalty: penalty,
            Keys.snoozeCount: snoozeCount,
            Keys.soundID: soundID
        ]
    }
}
