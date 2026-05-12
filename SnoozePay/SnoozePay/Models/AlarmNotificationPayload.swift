import Foundation

/// Typed payload encoded into `UNNotificationContent.userInfo` so callers do not
/// have to scrape stringly-typed dictionaries with `as? String` / `as? Int`.
///
/// Three sites used to read this dict independently (`AlarmFiringCoordinator`,
/// `AppDelegate.userNotificationCenter(_:willPresent:...)`, and
/// `AppDelegate.userNotificationCenter(_:didReceive:...)`) — a single key typo
/// (`"alarmId"` vs `"alarmID"`) or type mismatch was enough to silently drop a
/// snooze action. This struct is the single source of truth for what we put in
/// and what we get out.
///
/// The payload bridges through a plain `[String: Any]` dictionary (instead of a
/// JSON blob) because Apple's local-push pipeline already accepts `userInfo`
/// dictionaries verbatim and we want the keys to remain inspectable in
/// Console.app and in unit tests. Each field is encoded with its primitive
/// representation (`UUID` → `String`, others as-is).
///
/// Phase 2 of #31 (typed `Money` / `AlarmSound`) will tighten the field types;
/// today we mirror the underlying `Alarm` storage so the refactor stays a
/// pure rename.
struct AlarmNotificationPayload: Equatable {

    let alarmID: UUID
    let penaltyAmount: Double
    let progressiveScale: Bool
    let snoozeCount: Int
    let snoozeMinutes: Int
    let soundID: String

    // MARK: - userInfo keys
    //
    // Centralised so a typo lives in exactly one place. The string values match
    // the historical keys used before this refactor — changing them would
    // invalidate any pending notifications scheduled by an older build.
    enum Key {
        static let alarmID = "alarmID"
        static let penaltyAmount = "penaltyAmount"
        static let progressiveScale = "progressiveScale"
        static let snoozeCount = "snoozeCount"
        static let snoozeMinutes = "snoozeMinutes"
        static let soundID = "soundID"
    }

    // MARK: - Construction from an alarm

    /// Build the payload that goes into a fresh / snooze notification. The
    /// `snoozeCount` is the count *up to and including* the most recent snooze
    /// the user has performed — the firing coordinator increments it before
    /// charging the next penalty.
    init(alarm: Alarm, snoozeCount: Int) {
        self.alarmID = alarm.id
        self.penaltyAmount = alarm.penaltyAmount
        self.progressiveScale = alarm.progressiveScale
        self.snoozeCount = snoozeCount
        self.snoozeMinutes = alarm.snoozeMinutes
        self.soundID = alarm.soundID
    }

    /// Designated init for tests / decode paths.
    init(
        alarmID: UUID,
        penaltyAmount: Double,
        progressiveScale: Bool,
        snoozeCount: Int,
        snoozeMinutes: Int,
        soundID: String
    ) {
        self.alarmID = alarmID
        self.penaltyAmount = penaltyAmount
        self.progressiveScale = progressiveScale
        self.snoozeCount = snoozeCount
        self.snoozeMinutes = snoozeMinutes
        self.soundID = soundID
    }

    // MARK: - userInfo bridge

    /// Decode from a `UNNotificationContent.userInfo` dictionary. Returns `nil`
    /// if any required field is missing, has the wrong type, OR is out of
    /// range — callers MUST surface this as a typed error path (log + early
    /// return), never proceed with synthesised defaults.
    ///
    /// Range validation matters because `userInfo` is a `[AnyHashable: Any]`
    /// dict that arrives from the notification daemon and could in principle
    /// carry tampered or schema-drifted values. Without these guards
    /// `AlarmFiringCoordinator` would compute `pow(2.0, negativeCount)` for
    /// a progressive penalty, schedule a 0-minute snooze trigger, or attempt
    /// to charge a `NaN` penalty (issue #208).
    init?(userInfo: [AnyHashable: Any]) {
        guard
            let alarmIDString = userInfo[Key.alarmID] as? String,
            let alarmID = UUID(uuidString: alarmIDString),
            let penaltyAmount = userInfo[Key.penaltyAmount] as? Double,
            let progressiveScale = userInfo[Key.progressiveScale] as? Bool,
            let snoozeCount = userInfo[Key.snoozeCount] as? Int,
            let snoozeMinutes = userInfo[Key.snoozeMinutes] as? Int,
            let soundID = userInfo[Key.soundID] as? String
        else {
            return nil
        }
        guard
            penaltyAmount.isFinite, penaltyAmount >= 0,
            snoozeCount >= 0,
            snoozeMinutes >= 1, snoozeMinutes <= 60
        else {
            return nil
        }

        self.alarmID = alarmID
        self.penaltyAmount = penaltyAmount
        self.progressiveScale = progressiveScale
        self.snoozeCount = snoozeCount
        self.snoozeMinutes = snoozeMinutes
        self.soundID = soundID
    }

    /// Encode as the dictionary that `UNMutableNotificationContent.userInfo`
    /// expects. Only `Plist`-compatible value types are produced so iOS can
    /// serialize it across the notification daemon.
    func asUserInfo() -> [String: Any] {
        [
            Key.alarmID: alarmID.uuidString,
            Key.penaltyAmount: penaltyAmount,
            Key.progressiveScale: progressiveScale,
            Key.snoozeCount: snoozeCount,
            Key.snoozeMinutes: snoozeMinutes,
            Key.soundID: soundID
        ]
    }
}
