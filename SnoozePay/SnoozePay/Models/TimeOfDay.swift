import Foundation

/// Wall-clock time-of-day, decoupled from any specific calendar date.
///
/// `Alarm.time` historically stored a `Date` whose date components were
/// meaningless — only `(hour, minute)` was ever read. This invited bugs where
/// the date portion leaked into scheduling logic. `TimeOfDay` makes the
/// "only hour/minute" intent explicit and validates ranges at construction.
///
/// Phase 1 of #31: introduced as a parallel API; `Alarm.time: Date` remains
/// the storage primary so existing UserDefaults JSON keeps decoding. Callers
/// that want validated semantics can read `Alarm.timeOfDay`.
struct TimeOfDay: Equatable, Hashable, Codable {

    let hour: Int    // 0...23
    let minute: Int  // 0...59

    /// Failable init that enforces hour/minute ranges. Returns `nil` for
    /// any out-of-range input rather than clamping silently — silent clamp
    /// would mask programmer errors at construction time.
    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Build from a `Date` by extracting wall-clock components in the given
    /// calendar. Returns `nil` only if the calendar refuses to provide both
    /// components (in practice, never for `Calendar.current` + a real date).
    init?(from date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// Project this time-of-day onto the same calendar day as `referenceDate`.
    /// Returns the computed `Date` or `nil` if the calendar refuses
    /// (DST gaps, unusual calendars) — callers must handle that edge.
    func toDate(on referenceDate: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }
}
