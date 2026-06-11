import Foundation

/// How an alarm recurs across weeks (#229).
///
/// `weekly` is the historical behaviour — repeating calendar triggers fire
/// every week on the selected days. `never` makes the alarm one-shot: it
/// fires once on the next occurrence of the selected days/time and is
/// auto-disabled after the user dismisses the firing screen
/// (`AlarmFiringViewModel.dismiss`).
///
/// Persisted as a raw string inside the alarm JSON. Decoding is sanitizing,
/// not throwing: `Alarm.init(from:)` maps a missing key (pre-#229 alarms) or
/// an unknown raw value (corrupt storage / future mode rolled back) to
/// `.weekly`, so legacy payloads keep their existing behaviour and the store
/// never locks (#72 / #117).
enum AlarmRepeatMode: String, Codable {
    /// One-shot: ring once on the next occurrence of the selected days, then
    /// auto-disable after dismiss. Triggers are scheduled non-repeating so
    /// iOS itself never re-fires the alarm a week later.
    case never
    /// Default: repeat every week on the selected days (repeating triggers).
    case weekly
}
