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
    /// Per-alarm playback volume (#150). Optional for backwards-compat with
    /// notifications scheduled by pre-#150 builds — `nil` decodes to the
    /// historical "ring at full volume" default.
    let volume: Float?
    /// Per-alarm fade-in flag (#150). Same backward-compat policy as
    /// `volume`.
    let volumeFadeIn: Bool?

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
        static let volume = "volume"
        static let volumeFadeIn = "volumeFadeIn"
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
        self.volume = alarm.volume
        self.volumeFadeIn = alarm.volumeFadeIn
    }

    /// Designated init for tests / decode paths.
    init(
        alarmID: UUID,
        penaltyAmount: Double,
        progressiveScale: Bool,
        snoozeCount: Int,
        snoozeMinutes: Int,
        soundID: String,
        volume: Float? = nil,
        volumeFadeIn: Bool? = nil
    ) {
        self.alarmID = alarmID
        self.penaltyAmount = penaltyAmount
        self.progressiveScale = progressiveScale
        self.snoozeCount = snoozeCount
        self.snoozeMinutes = snoozeMinutes
        self.soundID = soundID
        self.volume = volume
        self.volumeFadeIn = volumeFadeIn
    }

    // MARK: - userInfo bridge

    /// Decode from a `UNNotificationContent.userInfo` dictionary. Returns `nil`
    /// if any required field is missing or has the wrong type — callers MUST
    /// surface this as a typed error path (log + early return), never proceed
    /// with synthesised defaults.
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

        self.alarmID = alarmID
        self.penaltyAmount = penaltyAmount
        self.progressiveScale = progressiveScale
        self.snoozeCount = snoozeCount
        self.snoozeMinutes = snoozeMinutes
        self.soundID = soundID
        // Optional fields added in #150 — pre-#150 builds didn't write these
        // into userInfo, so absence falls back to the documented defaults at
        // the call site (full volume, no fade) without breaking decode.
        self.volume = userInfo[Key.volume] as? Float
            ?? (userInfo[Key.volume] as? Double).map { Float($0) }
        self.volumeFadeIn = userInfo[Key.volumeFadeIn] as? Bool
    }

    /// Encode as the dictionary that `UNMutableNotificationContent.userInfo`
    /// expects. Only `Plist`-compatible value types are produced so iOS can
    /// serialize it across the notification daemon.
    func asUserInfo() -> [String: Any] {
        var dict: [String: Any] = [
            Key.alarmID: alarmID.uuidString,
            Key.penaltyAmount: penaltyAmount,
            Key.progressiveScale: progressiveScale,
            Key.snoozeCount: snoozeCount,
            Key.snoozeMinutes: snoozeMinutes,
            Key.soundID: soundID
        ]
        // Only emit the new keys when set so a downgraded build's payload
        // decoder still succeeds (it ignores unknown keys, but emitting nil
        // would coerce to NSNull and break the userInfo plist serialiser).
        if let volume = volume {
            // Plist-encode as Double — `Float` is not a plist-compatible
            // type on every iOS version's serialiser.
            dict[Key.volume] = Double(volume)
        }
        if let volumeFadeIn = volumeFadeIn {
            dict[Key.volumeFadeIn] = volumeFadeIn
        }
        return dict
    }
}
