import Foundation

/// Global, user-tunable defaults that seed brand-new alarms (#283).
///
/// These mirror the per-alarm fields on `Alarm` (snooze duration, ring
/// volume, vibration, progressive price) but live at app scope so the
/// Settings screen can offer "set it once" defaults. Editing a default only
/// affects alarms created afterwards — existing alarms keep whatever they
/// were saved with, so changing the global never silently rewrites a user's
/// configured alarm.
///
/// Backed by `UserDefaults` + `Codable`-free primitives (per the project's
/// "UserDefaults, not Core Data" rule). Each accessor reads/writes a single
/// key so the store stays inspectable and migration-free.
final class AlarmDefaults {

    static let shared = AlarmDefaults()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Keys

    private enum Key {
        static let snoozeMinutes = "default_snooze_minutes"
        static let volume = "default_volume"
        static let vibration = "default_vibration"
        static let progressiveScale = "default_progressive_scale"
    }

    // MARK: - Factory fallbacks
    //
    // Match the historical `Alarm.init` defaults so a fresh install behaves
    // exactly as before this screen existed.

    static let fallbackSnoozeMinutes = 9
    static let fallbackVolume: Float = 1.0
    static let fallbackVibration = true
    static let fallbackProgressiveScale = false

    // MARK: - Snooze duration

    /// Default snooze length (minutes) for new alarms. Clamped to the
    /// create-form's allowed range so a corrupt blob can't seed an
    /// out-of-range alarm that `Alarm.init(validating:)` would later reject.
    var snoozeMinutes: Int {
        get {
            guard defaults.object(forKey: Key.snoozeMinutes) != nil else {
                return Self.fallbackSnoozeMinutes
            }
            let raw = defaults.integer(forKey: Key.snoozeMinutes)
            return min(
                max(raw, Alarm.snoozeMinutesRange.lowerBound),
                Alarm.snoozeMinutesRange.upperBound
            )
        }
        set {
            let clamped = min(
                max(newValue, Alarm.snoozeMinutesRange.lowerBound),
                Alarm.snoozeMinutesRange.upperBound
            )
            defaults.set(clamped, forKey: Key.snoozeMinutes)
        }
    }

    // MARK: - Volume

    /// Default ring volume (`0.0...1.0`) for new alarms.
    var volume: Float {
        get {
            guard defaults.object(forKey: Key.volume) != nil else {
                return Self.fallbackVolume
            }
            let raw = defaults.float(forKey: Key.volume)
            guard raw.isFinite else { return Self.fallbackVolume }
            return min(max(raw, 0), 1)
        }
        set {
            let clamped = newValue.isFinite ? min(max(newValue, 0), 1) : Self.fallbackVolume
            defaults.set(clamped, forKey: Key.volume)
        }
    }

    // MARK: - Vibration

    /// Default vibration flag for new alarms.
    var vibrationEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.vibration) != nil else {
                return Self.fallbackVibration
            }
            return defaults.bool(forKey: Key.vibration)
        }
        set { defaults.set(newValue, forKey: Key.vibration) }
    }

    // MARK: - Progressive price

    /// Default progressive-price flag for new alarms (the ×2 escalation
    /// chain). Off by default to match the pre-#283 create-form behaviour.
    var progressiveScale: Bool {
        get {
            guard defaults.object(forKey: Key.progressiveScale) != nil else {
                return Self.fallbackProgressiveScale
            }
            return defaults.bool(forKey: Key.progressiveScale)
        }
        set { defaults.set(newValue, forKey: Key.progressiveScale) }
    }
}
